import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import 'ai_insights_tab.dart';
import 'net_zero_screen.dart';
import 'user_settings.dart';

// ─── API Base URL ────────────────────────────────────────────────────
// Always uses the deployed Render backend — works on all platforms.
const String _kApiProduction = 'https://smart-inverter-api.onrender.com';
final String kApiBase = _kApiProduction;

// ─────────────────────────── App Entry ───────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UserSettings.init();
  runApp(const SmartInverterApp());
}

// ─────────────────────────── Colors ──────────────────────────────────
class AppColors {
  static const bg         = Color(0xFF070B14);
  static const surface    = Color(0xFF0F1625);
  static const card       = Color(0xFF161E30);
  static const cardAlt    = Color(0xFF1A2540);
  static const border     = Color(0xFF1F2D45);

  static const solar      = Color(0xFFFFBB3C);
  static const load       = Color(0xFF3B82F6);
  static const battery    = Color(0xFF10B981);
  static const temp       = Color(0xFFEF4444);
  static const co2        = Color(0xFF8B5CF6);
  static const savings    = Color(0xFF06D6A0);
  static const voltage    = Color(0xFFF97316);
  static const netZero    = Color(0xFF00D4AA);

  static const textPrimary   = Color(0xFFF1F5F9);
  static const textSecondary = Color(0xFF94A3B8);
  static const textMuted     = Color(0xFF475569);
}

// ─────────────────────────── Root Widget ─────────────────────────────
class SmartInverterApp extends StatelessWidget {
  const SmartInverterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Inverter',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3B82F6),
          surface: AppColors.surface,
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

// ─────────────────────────── Data Model ──────────────────────────────
class InverterData {
  final double voltage;
  final double current;
  final double power;
  final double loadPower;
  final double temperature;
  final int battery;
  final String status;
  final DateTime timestamp;
  final bool isLive;

  const InverterData({
    required this.voltage,
    required this.current,
    required this.power,
    required this.loadPower,
    required this.temperature,
    required this.battery,
    required this.status,
    required this.timestamp,
    this.isLive = true,
  });
}

// ─────────────────────────── History ─────────────────────────────────
class HistoryPoint {
  final DateTime time;
  final double value;
  const HistoryPoint({required this.time, required this.value});
}

// ─────────────────────────── Main Navigation ─────────────────────────
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    DashboardPage(),
    NetZeroScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Theme(
        data: ThemeData(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border, width: 1)),
          ),
          child: BottomNavigationBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedItemColor: AppColors.solar,
            unselectedItemColor: AppColors.textMuted,
            currentIndex: _currentIndex,
            type: BottomNavigationBarType.fixed,
            selectedLabelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
            unselectedLabelStyle: GoogleFonts.inter(fontSize: 11),
            onTap: (i) => setState(() => _currentIndex = i),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.eco_rounded),
                label: 'Net-Zero',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Dashboard Page ──────────────────────────
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  InverterData _data = InverterData(
    voltage: 0, current: 0, power: 0, loadPower: 0,
    temperature: 0, battery: 0, status: 'Initializing',
    timestamp: DateTime.now(), isLive: false,
  );
  bool _isLoading = true;
  Timer? _refreshTimer;
  late AnimationController _pulseCtrl;

  List<HistoryPoint> _historyPoints = [];
  List<HistoryPoint> _predictionPoints = [];
  bool _historyLoading = false;
  String _historyField  = 'pv_input_w';
  String _historyRange  = '1h';

  static const _fieldLabels = {
    'pv_input_w': 'Solar',
    'load_w': 'Load',
    'battery_percent': 'Battery',
    'temperature': 'Temp',
  };
  static const _fieldUnits = {
    'pv_input_w': 'W',
    'load_w': 'W',
    'battery_percent': '%',
    'temperature': '°C',
  };
  static const _fieldColors = {
    'pv_input_w': AppColors.solar,
    'load_w': AppColors.load,
    'battery_percent': AppColors.battery,
    'temperature': AppColors.temp,
  };

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _fetchData();
    _fetchHistory();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),  // Faster refresh for live data
      (_) { _fetchData(); _fetchHistory(); },
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final response = await http
          .get(Uri.parse('$kApiBase/power'))
          .timeout(const Duration(seconds: 10));  // Fail fast
      if (response.statusCode != 200) throw Exception('${response.statusCode}');
      final raw = json.decode(response.body) as Map<String, dynamic>;
      final voltage     = (raw['voltage']     ?? raw['battery_voltage']  ?? 0).toDouble();
      final power       = (raw['power']       ?? raw['pv_input_w']       ?? 0).toDouble();
      final loadPower   = (raw['load_w']      ?? 0).toDouble();
      final temperature = (raw['temperature'] ?? 0).toDouble();
      final current     = (raw['current']     ?? (voltage > 0 ? power / voltage : 0)).toDouble();
      final batteryRaw  = raw['battery'] ?? raw['battery_percent'] ?? 0;
      final battery     = (batteryRaw is double ? batteryRaw.toInt() : batteryRaw as int);
      final status      = (power > 2000 || loadPower > 2000) ? 'Overload' : 'Normal';
      setState(() {
        _data = InverterData(
          voltage: voltage, current: current, power: power,
          loadPower: loadPower, temperature: temperature,
          battery: battery, status: status,
          timestamp: DateTime.now(), isLive: true,
        );
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not reach API: $e', style: GoogleFonts.inter(fontSize: 12)),
          backgroundColor: AppColors.temp.withOpacity(0.9),
          action: SnackBarAction(label: 'Retry', textColor: Colors.white, onPressed: _fetchData),
        ));
      }
    }
  }

  Future<void> _fetchHistory() async {
    setState(() { _historyLoading = true; _predictionPoints = []; });
    try {
      final uri = Uri.parse('$kApiBase/history?field=$_historyField&range=$_historyRange');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw Exception('${response.statusCode}');
      final body = json.decode(response.body) as Map<String, dynamic>;
      final raw  = body['points'] as List<dynamic>;
      
      List<HistoryPoint> preds = [];

      setState(() {
        _historyPoints = raw.map((p) => HistoryPoint(
          time: DateTime.parse(p['time'] as String).toLocal(),
          value: (p['value'] as num).toDouble(),
        )).toList();
        _predictionPoints = preds;
        _historyLoading = false;
      });
    } catch (_) {
      setState(() => _historyLoading = false);
    }
  }

  // ── helpers ────────────────────────────────────────────────────────
  bool get _isNetZero => _data.power >= _data.loadPower && _data.power > 0;
  double get _dailySavings => (_data.power / 1000) * 5 * UserSettings.elecRate;
  double get _dailyCo2 => (_data.power / 1000) * 5 * UserSettings.co2Factor;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: TabBar(
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: const LinearGradient(
                      colors: [AppColors.solar, AppColors.voltage],
                      begin: Alignment.centerLeft, end: Alignment.centerRight,
                    ),
                  ),
                  dividerColor: Colors.transparent,
                  labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: GoogleFonts.inter(fontSize: 12),
                  labelColor: Colors.black,
                  unselectedLabelColor: AppColors.textSecondary,
                  tabs: const [Tab(text: 'Live View'), Tab(text: 'AI Forecasts')],
                ),
              ),
              Expanded(
                child: TabBarView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildLiveTab(),
                    const AIInsightsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () { _fetchData(); _fetchHistory(); },
          backgroundColor: AppColors.solar,
          foregroundColor: Colors.black,
          elevation: 0,
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Icon(Icons.refresh_rounded),
        ),
      ),
    );
  }

  Widget _buildLiveTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            _buildStatusBanner(),
            const SizedBox(height: 20),
            _buildEnergyOverviewRow(),
            const SizedBox(height: 20),
            _buildLabel('Power Metrics'),
            const SizedBox(height: 12),
            _buildMetricGrid(),
            const SizedBox(height: 20),
            _buildLabel('Energy Flow'),
            const SizedBox(height: 12),
            _buildEnergyFlowCard(),
            const SizedBox(height: 20),
            _buildLabel('Historical Trends'),
            const SizedBox(height: 12),
            _buildHistoryChart(),
            const SizedBox(height: 20),
            _buildLabel('Net-Zero Snapshot'),
            const SizedBox(height: 12),
            _buildNetZeroRow(),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.solar, Color(0xFFF97316)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.electric_bolt, color: Colors.black, size: 18),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Smart Inverter', style: GoogleFonts.inter(
                fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text('Home Dashboard', style: GoogleFonts.inter(
                fontSize: 10, color: AppColors.textSecondary)),
            ],
          ),
          const Spacer(),
          _LiveIndicator(isLoading: _isLoading),
        ],
      ),
    );
  }

  // ── Status Banner ─────────────────────────────────────────────────
  Widget _buildStatusBanner() {
    final isOverload = _data.status == 'Overload';
    final c = isOverload ? AppColors.temp : AppColors.battery;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.withOpacity(0.18), c.withOpacity(0.06)],
          begin: Alignment.centerLeft, end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => Container(
              width: 9, height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: c,
                boxShadow: [BoxShadow(color: c.withOpacity(_pulseCtrl.value * 0.9), blurRadius: 10, spreadRadius: 2)],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            isOverload ? '⚠  OVERLOAD DETECTED' : '✓  SYSTEM NORMAL',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: c, letterSpacing: 0.5),
          ),
          const Spacer(),
          Text(
            '${_data.timestamp.hour.toString().padLeft(2, '0')}:${_data.timestamp.minute.toString().padLeft(2, '0')}',
            style: GoogleFonts.spaceMono(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  // ── Energy Overview Row (Battery + Donut) ─────────────────────────
  Widget _buildEnergyOverviewRow() {
    return Row(
      children: [
        Expanded(child: _buildBatteryCard()),
        const SizedBox(width: 12),
        Expanded(child: _buildPowerDonut()),
      ],
    );
  }

  Widget _buildBatteryCard() {
    final c = _batteryColor(_data.battery);
    return _GlassCard(
      gradient: [c.withOpacity(0.15), c.withOpacity(0.04)],
      borderColor: c.withOpacity(0.35),
      child: Column(
        children: [
          SizedBox(
            width: 90, height: 90,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: _data.battery / 100),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => _BatteryGauge(progress: v, color: c),
            ),
          ),
          const SizedBox(height: 10),
          Text('Battery', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(_batteryLabel(_data.battery),
            style: GoogleFonts.inter(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildPowerDonut() {
    final total = _data.power + _data.loadPower;
    final solarPct = total > 0 ? (_data.power / total * 100) : 50;
    final loadPct  = total > 0 ? (_data.loadPower / total * 100) : 50;
    return _GlassCard(
      child: Column(
        children: [
          SizedBox(
            width: 90, height: 90,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(PieChartData(
                  sectionsSpace: 3,
                  centerSpaceRadius: 28,
                  sections: [
                    PieChartSectionData(value: solarPct.toDouble(), color: AppColors.solar,
                      radius: 18, showTitle: false),
                    PieChartSectionData(value: loadPct.toDouble(), color: AppColors.load,
                      radius: 18, showTitle: false),
                  ],
                )),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.bolt, color: AppColors.solar, size: 14),
                  Text('${solarPct.toInt()}%',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Dot(AppColors.solar), const SizedBox(width: 4),
              Text('Gen', style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary)),
              const SizedBox(width: 10),
              _Dot(AppColors.load), const SizedBox(width: 4),
              Text('Load', style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Metric Grid ───────────────────────────────────────────────────
  Widget _buildMetricGrid() {
    final metrics = [
      _Metric('Solar Power', _data.power.toStringAsFixed(0), 'W', Icons.wb_sunny_rounded, AppColors.solar,
          [const Color(0xFFFFBB3C), const Color(0xFFF97316)]),
      _Metric('Load Power', _data.loadPower.toStringAsFixed(0), 'W', Icons.power_rounded, AppColors.load,
          [const Color(0xFF3B82F6), const Color(0xFF2563EB)]),
      _Metric('Voltage', _data.voltage.toStringAsFixed(1), 'V', Icons.flash_on_rounded, AppColors.voltage,
          [const Color(0xFFF97316), const Color(0xFFEA580C)]),
      _Metric('Temperature', _data.temperature.toStringAsFixed(1), '°C', Icons.thermostat_rounded, AppColors.temp,
          [const Color(0xFFEF4444), const Color(0xFFDC2626)]),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.5,
      ),
      itemCount: metrics.length,
      itemBuilder: (_, i) => _MetricCard(data: metrics[i]),
    );
  }

  // ── Energy Flow Card ────────────────────────────────────────────────
  Widget _buildEnergyFlowCard() {
    final net = _data.power - _data.loadPower;
    final isExcess = net >= 0;
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Power Balance', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (isExcess ? AppColors.battery : AppColors.temp).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isExcess ? '+ Surplus' : '- Deficit',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600,
                    color: isExcess ? AppColors.battery : AppColors.temp),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _EnergyFlowItem('Generated', _data.power, 'W', AppColors.solar, Icons.wb_sunny_rounded),
              const Spacer(),
              Column(children: [
                Text(net >= 0 ? '+${net.toStringAsFixed(0)}' : net.toStringAsFixed(0),
                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800,
                    color: isExcess ? AppColors.battery : AppColors.temp)),
                Text('W', style: GoogleFonts.inter(fontSize: 10, color: AppColors.textMuted)),
              ]),
              const Spacer(),
              _EnergyFlowItem('Consumed', _data.loadPower, 'W', AppColors.load, Icons.home_rounded),
            ],
          ),
          const SizedBox(height: 16),
          // Visual bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              children: [
                Container(height: 10, color: AppColors.border),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0,
                    end: (_data.power + _data.loadPower) > 0
                        ? (_data.power / (_data.power + _data.loadPower))
                        : 0.5),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => FractionallySizedBox(
                    widthFactor: v,
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [AppColors.solar, AppColors.battery]),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── History Chart ─────────────────────────────────────────────────
  Widget _buildHistoryChart() {
    return _GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Metric tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _fieldLabels.keys.map((field) {
                final sel = field == _historyField;
                final c = _fieldColors[field]!;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () { setState(() => _historyField = field); _fetchHistory(); },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: sel ? c.withOpacity(0.2) : AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: sel ? c.withOpacity(0.6) : AppColors.border),
                      ),
                      child: Text(_fieldLabels[field]!,
                        style: GoogleFonts.inter(fontSize: 12,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                          color: sel ? c : AppColors.textSecondary)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          // Time range
          Row(
            children: ['1h', '6h', '24h'].map((r) {
              final sel = r == _historyRange;
              return GestureDetector(
                onTap: () { setState(() => _historyRange = r); _fetchHistory(); },
                child: Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.cardAlt : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(r.toUpperCase(),
                    style: GoogleFonts.inter(fontSize: 10,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      color: sel ? AppColors.textPrimary : AppColors.textMuted)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: _historyLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.solar))
                : _historyPoints.isEmpty
                    ? Center(child: Text('No data for this period',
                        style: GoogleFonts.inter(color: AppColors.textMuted)))
                    : _buildLineChart(),
          ),
        ],
      ),
    );
  }

  Widget _buildLineChart() {
    final color  = _fieldColors[_historyField]!;
    final unit   = _fieldUnits[_historyField]!;
    
    final allPoints = [..._historyPoints, ..._predictionPoints];
    if (allPoints.isEmpty) return const SizedBox();

    double minY  = allPoints.map((p) => p.value).reduce(math.min);
    double maxY  = allPoints.map((p) => p.value).reduce(math.max);
    final yRange = maxY - minY;
    if (yRange == 0) { minY -= 10; maxY += 10; }
    else { minY -= yRange * 0.1; maxY += yRange * 0.1; }
    if (minY < 0 && _historyField != 'temperature') minY = 0;

    final spots = _historyPoints.map((p) =>
      FlSpot(p.time.millisecondsSinceEpoch.toDouble(), p.value)).toList();
      
    final predSpots = _predictionPoints.map((p) =>
      FlSpot(p.time.millisecondsSinceEpoch.toDouble(), p.value)).toList();

    // If we have predictions, connect the last history point to the first prediction point
    if (spots.isNotEmpty && predSpots.isNotEmpty) {
      predSpots.insert(0, spots.last);
    }

    final intervalX = _historyRange == '1h' ? 10 * 60 * 1000.0
        : _historyRange == '6h' ? 60 * 60 * 1000.0 
        : 4 * 60 * 60 * 1000.0;

    return LineChart(LineChartData(
      gridData: FlGridData(
        show: true, drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(
          color: AppColors.border.withOpacity(0.5), strokeWidth: 1, dashArray: [4, 4]),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, reservedSize: 38,
          getTitlesWidget: (v, _) => Text('${v.toInt()}',
            style: GoogleFonts.spaceMono(fontSize: 9, color: AppColors.textMuted)),
        )),
        bottomTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, reservedSize: 22,
          interval: intervalX,
          getTitlesWidget: (v, _) {
            final d = DateTime.fromMillisecondsSinceEpoch(v.toInt());
            String text = '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
            
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(text,
                style: GoogleFonts.spaceMono(fontSize: 9, color: AppColors.textMuted)),
            );
          },
        )),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      minY: minY, maxY: maxY,
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => AppColors.cardAlt,
          getTooltipItems: (spots) => spots.map((s) {
            final d = DateTime.fromMillisecondsSinceEpoch(s.x.toInt());
            return LineTooltipItem(
              '${s.y.toStringAsFixed(1)} $unit\n',
              GoogleFonts.inter(color: color, fontWeight: FontWeight.bold, fontSize: 12),
              children: [TextSpan(
                text: '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}',
                style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 10))],
            );
          }).toList(),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots, isCurved: true, curveSmoothness: 0.2, color: color, barWidth: 2.5,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, gradient: LinearGradient(
            colors: [color.withOpacity(0.35), color.withOpacity(0)],
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
          )),
        ),
        if (predSpots.isNotEmpty)
          LineChartBarData(
            spots: predSpots, isCurved: true, curveSmoothness: 0.2, 
            color: color.withOpacity(0.8), barWidth: 2.5,
            dashArray: [5, 4], // Dashed line for predictions
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
      ],
    ));
  }

  // ── Net-Zero Snapshot row ─────────────────────────────────────────
  Widget _buildNetZeroRow() {
    return Row(
      children: [
        Expanded(child: _SnapshotCard(
          icon: Icons.eco_rounded, color: AppColors.netZero,
          label: 'Net-Zero',
          value: _isNetZero ? 'ACHIEVED' : 'PENDING',
          sub: _isNetZero ? 'Generating ≥ Usage' : 'Not Yet',
          achieved: _isNetZero,
        )),
        const SizedBox(width: 10),
        Expanded(child: _SnapshotCard(
          icon: Icons.currency_rupee_rounded, color: AppColors.savings,
          label: 'Est. Savings',
          value: '₹${_dailySavings.toStringAsFixed(1)}',
          sub: 'Today',
        )),
        const SizedBox(width: 10),
        Expanded(child: _SnapshotCard(
          icon: Icons.cloud_off_rounded, color: AppColors.co2,
          label: 'CO₂ Saved',
          value: '${_dailyCo2.toStringAsFixed(2)}',
          sub: 'kg Today',
        )),
      ],
    );
  }

  Widget _buildLabel(String label) => Text(
    label,
    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
  );

  Color _batteryColor(int pct) {
    if (pct >= 60) return AppColors.battery;
    if (pct >= 30) return AppColors.voltage;
    return AppColors.temp;
  }

  String _batteryLabel(int pct) {
    if (pct >= 80) return 'Excellent';
    if (pct >= 60) return 'Good';
    if (pct >= 30) return 'Moderate';
    return 'Critical';
  }
}

// ─────────────────────────── Reusable Widgets ────────────────────────

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final List<Color>? gradient;
  final Color? borderColor;
  const _GlassCard({required this.child, this.padding, this.gradient, this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: gradient != null
            ? LinearGradient(colors: gradient!, begin: Alignment.topLeft, end: Alignment.bottomRight)
            : null,
        color: gradient == null ? AppColors.card : null,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor ?? AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: child,
    );
  }
}

// GlassCard: standalone alias used by net_zero_screen
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  const GlassCard({super.key, required this.child, this.padding});
  @override
  Widget build(BuildContext context) => _GlassCard(padding: padding, child: child);
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot(this.color);
  @override
  Widget build(BuildContext context) => Container(
    width: 8, height: 8,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

class _EnergyFlowItem extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final Color color;
  final IconData icon;
  const _EnergyFlowItem(this.label, this.value, this.unit, this.color, this.icon);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      const SizedBox(height: 8),
      Text('${value.toStringAsFixed(0)} $unit',
        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
    ]);
  }
}

class _SnapshotCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String sub;
  final bool? achieved;
  const _SnapshotCard({required this.icon, required this.color, required this.label,
    required this.value, required this.sub, this.achieved});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(value, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.inter(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
          Text(sub, style: GoogleFonts.inter(fontSize: 10, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _Metric {
  final String label, value, unit;
  final IconData icon;
  final Color color;
  final List<Color> gradient;
  const _Metric(this.label, this.value, this.unit, this.icon, this.color, this.gradient);
}

class _MetricCard extends StatelessWidget {
  final _Metric data;
  const _MetricCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [data.color.withOpacity(0.18), AppColors.card],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: data.color.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: data.color.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: data.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(data.icon, color: Colors.white, size: 17),
            ),
            Text(data.unit, style: GoogleFonts.spaceMono(fontSize: 10, color: data.color)),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: double.tryParse(data.value) ?? 0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => Text(
                v.toStringAsFixed(data.unit == 'V' || data.unit == '°C' ? 1 : 0),
                style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary, height: 1),
              ),
            ),
            const SizedBox(height: 2),
            Text(data.label, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
          ]),
        ],
      ),
    );
  }
}

class _BatteryGauge extends StatelessWidget {
  final double progress;
  final Color color;
  const _BatteryGauge({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _GaugePainter(progress: progress, color: color),
    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.battery_charging_full_rounded, color: color, size: 18),
      const SizedBox(height: 2),
      Text('${(progress * 100).toInt()}%',
        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
    ])),
  );
}

class _GaugePainter extends CustomPainter {
  final double progress;
  final Color color;
  _GaugePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    const start = -math.pi * 0.75;
    const sweep = math.pi * 1.5;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start, sweep, false,
      Paint()..color = AppColors.border..style = PaintingStyle.stroke..strokeWidth = 8..strokeCap = StrokeCap.round);
    if (progress > 0) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start, sweep * progress, false,
        Paint()
          ..shader = SweepGradient(startAngle: start, endAngle: start + sweep,
            colors: [color.withOpacity(0.3), color]).createShader(Rect.fromCircle(center: center, radius: radius))
          ..style = PaintingStyle.stroke..strokeWidth = 8..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.progress != progress || old.color != color;
}

class _LiveIndicator extends StatefulWidget {
  final bool isLoading;
  const _LiveIndicator({required this.isLoading});
  @override
  State<_LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<_LiveIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 8, height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.isLoading ? AppColors.voltage : AppColors.battery,
          boxShadow: [BoxShadow(
            color: (widget.isLoading ? AppColors.voltage : AppColors.battery).withOpacity(_ctrl.value * 0.9),
            blurRadius: 8, spreadRadius: 2)],
        ),
      ),
      const SizedBox(width: 6),
      Text(widget.isLoading ? 'Syncing' : 'Live',
        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600,
          color: widget.isLoading ? AppColors.voltage : AppColors.battery)),
    ]),
  );
}