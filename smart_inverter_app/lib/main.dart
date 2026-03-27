import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

// ─── API Base URL ────────────────────────────────────────────────────
// Replace this with your actual deployed backend URL (e.g. Render)
const String kApiBase = 'https://smart-inverter-api.onrender.com';
// const String kApiBase = 'http://localhost:3000';     // ← desktop/web (active)
// const String kApiBase = 'http://10.0.2.2:3000';     // ← Android emulator
// const String kApiBase = 'http://192.168.1.5:3000';  // ← real device (use your PC's IP)

// ─────────────────────────── App Entry ─────────────────────────────
void main() {
  runApp(const SmartInverterApp());
}

// ─────────────────────────── Theme tokens ───────────────────────────
class AppColors {
  static const bg = Color(0xFF0A0E1A);
  static const surface = Color(0xFF111827);
  static const card = Color(0xFF1A2235);
  static const border = Color(0xFF243049);

  static const accentBlue = Color(0xFF3B82F6);
  static const accentCyan = Color(0xFF06B6D4);
  static const accentGreen = Color(0xFF10B981);
  static const accentOrange = Color(0xFFF59E0B);
  static const accentRed = Color(0xFFEF4444);
  static const accentPurple = Color(0xFF8B5CF6);

  static const textPrimary = Color(0xFFF1F5F9);
  static const textSecondary = Color(0xFF94A3B8);
  static const textMuted = Color(0xFF475569);
}

// ─────────────────────────── Root Widget ────────────────────────────
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
          primary: AppColors.accentBlue,
          surface: AppColors.surface,
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      home: const DashboardPage(),
    );
  }
}

// ─────────────────────────── Data Model ─────────────────────────────
class InverterData {
  final double voltage;     // battery_voltage (V)
  final double current;     // derived: pv_input_w / battery_voltage (A)
  final double power;       // pv_input_w (W) – solar generation
  final double loadPower;   // load_w (W) – consumption
  final double temperature; // temperature (°C)
  final int battery;        // battery_percent (%)
  final String status;
  final DateTime timestamp;
  final bool isLive;        // true = real API data, false = mock

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

// ─────────────────────────── History Data Model ─────────────────────────
class HistoryPoint {
  final DateTime time;
  final double value;
  const HistoryPoint({required this.time, required this.value});
}

// ─────────────────────────── Dashboard Page ─────────────────────────
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  InverterData _data = InverterData(
    voltage: 0,
    current: 0,
    power: 0,
    loadPower: 0,
    temperature: 0,
    battery: 0,
    status: 'Initializing',
    timestamp: DateTime.now(),
    isLive: false,
  );
  bool _isLoading = true;
  bool _hasError = false;
  Timer? _refreshTimer;
  late AnimationController _pulseController;

  // ── History chart state ───────────────────────────────────────────
  List<HistoryPoint> _historyPoints = [];
  bool _historyLoading = false;
  String _historyField = 'pv_input_w';
  String _historyRange = '1h';

  static const _fieldLabels = {
    'pv_input_w':      'Solar Power',
    'load_w':          'Load Power',
    'battery_percent': 'Battery %',
    'temperature':     'Temperature',
  };
  static const _fieldUnits = {
    'pv_input_w':      'W',
    'load_w':          'W',
    'battery_percent': '%',
    'temperature':     '°C',
  };
  static const _fieldColors = {
    'pv_input_w':      AppColors.accentCyan,
    'load_w':          AppColors.accentBlue,
    'battery_percent': AppColors.accentGreen,
    'temperature':     AppColors.accentOrange,
  };

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _fetchData();
    _fetchHistory();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) { _fetchData(); _fetchHistory(); },
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final response = await http
          .get(Uri.parse('$kApiBase/power'))
          .timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }

      final raw = json.decode(response.body) as Map<String, dynamic>;

      // ── Map real InfluxDB field names ──────────────────────────────
      // battery_voltage → voltage (V)
      // pv_input_w      → power / solar generation (W)
      // load_w          → load consumption (W)
      // battery_percent → battery (%)
      // temperature     → temperature (°C)
      // current derived as pv_input_w / battery_voltage
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
          voltage:     voltage,
          current:     current,
          power:       power,
          loadPower:   loadPower,
          temperature: temperature,
          battery:     battery,
          status:      status,
          timestamp:   DateTime.now(),
          isLive:      true,
        );
        _isLoading = false;
        _hasError  = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError  = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '⚠ Could not reach API: ${e.toString()}\n'
              'Check that the backend is running and kApiBase is set correctly.',
              style: GoogleFonts.inter(fontSize: 12),
            ),
            backgroundColor: AppColors.accentRed.withOpacity(0.9),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _fetchData,
            ),
          ),
        );
      }
    }
  }

  // ── Fetch historical data from InfluxDB ──────────────────────────
  Future<void> _fetchHistory() async {
    setState(() => _historyLoading = true);
    try {
      final uri = Uri.parse(
        '$kApiBase/history?field=$_historyField&range=$_historyRange',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) throw Exception('${response.statusCode}');
      final body = json.decode(response.body) as Map<String, dynamic>;
      final raw = body['points'] as List<dynamic>;
      setState(() {
        _historyPoints = raw.map((p) => HistoryPoint(
          time: DateTime.parse(p['time'] as String),
          value: (p['value'] as num).toDouble(),
        )).toList();
        _historyLoading = false;
      });
    } catch (_) {
      setState(() => _historyLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            _buildAppBar(),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSystemStatusBar(),
                    const SizedBox(height: 24),
                    _buildBatteryHero(),
                    const SizedBox(height: 28),
                    _buildSectionLabel('Live Metrics'),
                    const SizedBox(height: 12),
                    _buildMetricGrid(),
                    const SizedBox(height: 28),
                    _buildSectionLabel('Historical Data'),
                    const SizedBox(height: 12),
                    _buildHistoryChart(),
                    const SizedBox(height: 28),
                    _buildSectionLabel('System Info'),
                    const SizedBox(height: 12),
                    _buildSystemInfo(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildRefreshFab(),
    );
  }

  // ── App Bar ──────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: AppColors.surface.withOpacity(0.95),
      expandedHeight: 80,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.accentBlue.withOpacity(0.15),
                AppColors.accentCyan.withOpacity(0.05),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        titlePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.accentBlue, AppColors.accentCyan],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.electric_bolt,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Smart Inverter',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'Control Center',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const Spacer(),
            _LiveIndicator(isLoading: _isLoading),
          ],
        ),
      ),
    );
  }

  // ── Status Bar ───────────────────────────────────────────────────
  Widget _buildSystemStatusBar() {
    final isOverload = _data.status == 'Overload';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isOverload
            ? AppColors.accentRed.withOpacity(0.12)
            : AppColors.accentGreen.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOverload
              ? AppColors.accentRed.withOpacity(0.4)
              : AppColors.accentGreen.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) => Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isOverload ? AppColors.accentRed : AppColors.accentGreen,
                boxShadow: [
                  BoxShadow(
                    color: (isOverload
                            ? AppColors.accentRed
                            : AppColors.accentGreen)
                        .withOpacity(_pulseController.value * 0.8),
                    blurRadius: 8,
                    spreadRadius: 2,
                  )
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            isOverload ? '⚠  OVERLOAD DETECTED' : '✓  SYSTEM OPERATING NORMALLY',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isOverload ? AppColors.accentRed : AppColors.accentGreen,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          Text(
            '${_data.timestamp.hour.toString().padLeft(2, '0')}:${_data.timestamp.minute.toString().padLeft(2, '0')}:${_data.timestamp.second.toString().padLeft(2, '0')}',
            style: GoogleFonts.spaceMono(
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  // ── Battery Hero ─────────────────────────────────────────────────
  Widget _buildBatteryHero() {
    return GlassCard(
      child: Row(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: _data.battery / 100),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, value, __) => SizedBox(
              width: 120,
              height: 120,
              child: _BatteryGauge(progress: value),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Battery Level',
                    style: GoogleFonts.inter(
                        fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: _data.battery.toDouble()),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => Text(
                    '${v.toInt()}%',
                    style: GoogleFonts.inter(
                      fontSize: 42,
                      fontWeight: FontWeight.w800,
                      color: _batteryColor(_data.battery),
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _BatteryBar(level: _data.battery / 100),
                const SizedBox(height: 10),
                Text(
                  _batteryLabel(_data.battery),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: _batteryColor(_data.battery),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _batteryColor(int pct) {
    if (pct >= 60) return AppColors.accentGreen;
    if (pct >= 30) return AppColors.accentOrange;
    return AppColors.accentRed;
  }

  String _batteryLabel(int pct) {
    if (pct >= 80) return '● Excellent';
    if (pct >= 60) return '● Good';
    if (pct >= 30) return '● Moderate';
    return '● Critical — Charge Now';
  }

  // ── Metric Grid ──────────────────────────────────────────────────
  Widget _buildMetricGrid() {
    final metrics = [
      _MetricData(
        label: 'Battery Voltage',
        value: _data.voltage.toStringAsFixed(1),
        unit: 'V',
        icon: Icons.flash_on_rounded,
        color: AppColors.accentOrange,
        gradient: [const Color(0xFFF59E0B), const Color(0xFFD97706)],
      ),
      _MetricData(
        label: 'Solar Power',
        value: _data.power.toStringAsFixed(0),
        unit: 'W',
        icon: Icons.wb_sunny_rounded,
        color: AppColors.accentCyan,
        gradient: [const Color(0xFF06B6D4), const Color(0xFF0891B2)],
      ),
      _MetricData(
        label: 'Load Power',
        value: _data.loadPower.toStringAsFixed(0),
        unit: 'W',
        icon: Icons.power_rounded,
        color: AppColors.accentBlue,
        gradient: [const Color(0xFF3B82F6), const Color(0xFF2563EB)],
      ),
      _MetricData(
        label: 'Temperature',
        value: _data.temperature.toStringAsFixed(1),
        unit: '°C',
        icon: Icons.thermostat_rounded,
        color: AppColors.accentRed,
        gradient: [const Color(0xFFEF4444), const Color(0xFFDC2626)],
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.45,
      ),
      itemCount: metrics.length,
      itemBuilder: (_, i) => _MetricCard(data: metrics[i]),
    );
  }

  // ── Historical Chart ─────────────────────────────────────────────
  Widget _buildHistoryChart() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Metric Tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _fieldLabels.keys.map((field) {
                final isSelected = field == _historyField;
                final color = _fieldColors[field]!;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_fieldLabels[field]!,
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400)),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _historyField = field);
                        _fetchHistory();
                      }
                    },
                    selectedColor: color.withOpacity(0.2),
                    backgroundColor: AppColors.surface,
                    checkmarkColor: color,
                    labelStyle: TextStyle(
                        color: isSelected ? color : AppColors.textSecondary),
                    side: BorderSide(
                        color: isSelected ? color.withOpacity(0.5) : AppColors.border),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          // Time Range Tabs
          Row(
            children: ['1h', '6h', '24h'].map((range) {
              final isSelected = range == _historyRange;
              return GestureDetector(
                onTap: () {
                  setState(() => _historyRange = range);
                  _fetchHistory();
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.border : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    range.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? AppColors.textPrimary : AppColors.textMuted,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          // Chart Area
          SizedBox(
            height: 180,
            child: _historyLoading
                ? const Center(child: CircularProgressIndicator())
                : _historyPoints.isEmpty
                    ? Center(
                        child: Text('No data for this period',
                            style: GoogleFonts.inter(color: AppColors.textMuted)))
                    : _buildLineChart(),
          ),
        ],
      ),
    );
  }

  Widget _buildLineChart() {
    if (_historyPoints.isEmpty) return const SizedBox();

    final color = _fieldColors[_historyField]!;
    final unit = _fieldUnits[_historyField]!;

    double minY = _historyPoints.map((p) => p.value).reduce(math.min);
    double maxY = _historyPoints.map((p) => p.value).reduce(math.max);

    // Add padding to Y axis
    final yRange = maxY - minY;
    if (yRange == 0) {
      minY -= 10;
      maxY += 10;
    } else {
      minY -= yRange * 0.1;
      maxY += yRange * 0.1;
    }
    if (minY < 0 && _historyField != 'temperature') minY = 0;

    final spots = _historyPoints.map((p) => FlSpot(
      p.time.millisecondsSinceEpoch.toDouble(),
      p.value,
    )).toList();

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppColors.border.withOpacity(0.5),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, _) => Text(
                '${v.toInt()}',
                style: GoogleFonts.spaceMono(
                    fontSize: 9, color: AppColors.textMuted),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: _historyRange == '1h'
                  ? 10 * 60 * 1000 // 10 mins
                  : _historyRange == '6h'
                      ? 60 * 60 * 1000 // 1 hour
                      : 4 * 60 * 60 * 1000, // 4 hours
              getTitlesWidget: (v, _) {
                final date = DateTime.fromMillisecondsSinceEpoch(v.toInt());
                String t = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(t,
                      style: GoogleFonts.spaceMono(
                          fontSize: 9, color: AppColors.textMuted)),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minY: minY,
        maxY: maxY,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (touchedSpot) => AppColors.surface,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final date = DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
                final timeStr = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(1)} $unit\n',
                  GoogleFonts.inter(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                  children: [
                    TextSpan(
                      text: timeStr,
                      style: GoogleFonts.inter(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.normal,
                          fontSize: 10),
                    ),
                  ],
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  color.withOpacity(0.3),
                  color.withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── System Info ──────────────────────────────────────────────────
  Widget _buildSystemInfo() {
    final rows = [
      ('Device ID', 'SI-PRO-001'),
      ('Firmware', 'v3.2.1'),
      ('Connection', 'Local API'),
      ('Auto-Refresh', 'Every 10s'),
      ('Last Sync',
          '${_data.timestamp.hour.toString().padLeft(2, '0')}:${_data.timestamp.minute.toString().padLeft(2, '0')}'),
    ];

    return GlassCard(
      child: Column(
        children: rows.map((r) {
          final isLast = r == rows.last;
          return Column(
            children: [
              Row(
                children: [
                  Text(r.$1,
                      style: GoogleFonts.inter(
                          fontSize: 13, color: AppColors.textSecondary)),
                  const Spacer(),
                  Text(r.$2,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      )),
                ],
              ),
              if (!isLast)
                Divider(
                    height: 20,
                    color: AppColors.border.withOpacity(0.5)),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildRefreshFab() {
    return FloatingActionButton.extended(
      onPressed: _fetchData,
      backgroundColor: AppColors.accentBlue,
      foregroundColor: Colors.white,
      icon: _isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.refresh_rounded),
      label: Text(
        _isLoading ? 'Refreshing...' : 'Refresh',
        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
      ),
      elevation: 0,
    );
  }
}

// ─────────────────────────── Reusable Widgets ────────────────────────

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  const GlassCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 8)),
        ],
      ),
      child: child,
    );
  }
}

class _MetricData {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  final List<Color> gradient;
  const _MetricData({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
    required this.gradient,
  });
}

class _MetricCard extends StatelessWidget {
  final _MetricData data;
  const _MetricCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: data.gradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(data.icon, color: Colors.white, size: 18),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: data.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  data.unit,
                  style: GoogleFonts.spaceMono(
                      fontSize: 10, color: data.color),
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(
                    begin: 0,
                    end: double.tryParse(data.value) ?? 0),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => Text(
                  v.toStringAsFixed(data.unit == 'A' ? 2 : 0),
                  style: GoogleFonts.inter(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(data.label,
                  style: GoogleFonts.inter(
                      fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _BatteryBar extends StatelessWidget {
  final double level; // 0.0 – 1.0
  const _BatteryBar({required this.level});

  Color _color() {
    if (level >= 0.6) return AppColors.accentGreen;
    if (level >= 0.3) return AppColors.accentOrange;
    return AppColors.accentRed;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      return Stack(
        children: [
          Container(
            height: 8,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: level),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Container(
              height: 8,
              width: constraints.maxWidth * v,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [_color(), _color().withOpacity(0.7)]),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(color: _color().withOpacity(0.4), blurRadius: 6)
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _BatteryGauge extends StatelessWidget {
  final double progress; // 0.0 – 1.0
  const _BatteryGauge({required this.progress});

  @override
  Widget build(BuildContext context) {
    Color color;
    if (progress >= 0.6) {
      color = AppColors.accentGreen;
    } else if (progress >= 0.3) {
      color = AppColors.accentOrange;
    } else {
      color = AppColors.accentRed;
    }

    return CustomPaint(
      painter: _GaugePainter(progress: progress, color: color),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.battery_charging_full_rounded,
                color: color, size: 22),
            const SizedBox(height: 2),
            Text(
              '${(progress * 100).toInt()}%',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double progress;
  final Color color;
  _GaugePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    const startAngle = -math.pi * 0.75;
    const sweepFull = math.pi * 1.5;

    // Track
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepFull,
      false,
      Paint()
        ..color = AppColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );

    // Progress
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepFull * progress,
      false,
      Paint()
        ..shader = SweepGradient(
          startAngle: startAngle,
          endAngle: startAngle + sweepFull,
          colors: [color.withOpacity(0.4), color],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.progress != progress || old.color != color;
}

class _LiveIndicator extends StatefulWidget {
  final bool isLoading;
  const _LiveIndicator({required this.isLoading});

  @override
  State<_LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<_LiveIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.isLoading ? AppColors.accentOrange : AppColors.accentGreen,
              boxShadow: [
                BoxShadow(
                  color: (widget.isLoading
                          ? AppColors.accentOrange
                          : AppColors.accentGreen)
                      .withOpacity(_ctrl.value * 0.7),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            widget.isLoading ? 'Syncing' : 'Live',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: widget.isLoading
                  ? AppColors.accentOrange
                  : AppColors.accentGreen,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}