import 'dart:convert';
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import 'main.dart'; // To access AppColors and kApiBase
import 'user_settings.dart';

class AIInsightsTab extends StatefulWidget {
  const AIInsightsTab({super.key});

  @override
  State<AIInsightsTab> createState() => _AIInsightsTabState();
}

class _AIInsightsTabState extends State<AIInsightsTab> {
  bool _isLoading = true;
  String _weatherInsight = "Loading...";
  String _weatherCondition = "";
  double _weatherTemp = 0.0;
  
  List<HistoryPoint> _solarPred = [];
  List<HistoryPoint> _loadPred  = [];
  List<HistoryPoint> _dailyHistory = [];
  
  // Data source tracking — prevents displaying hallucinated values
  String _solarDataSource = 'unknown';   // real_data | panel_specs | historical_peak | unavailable
  String? _solarWarning;
  String _loadDataSource  = 'unknown';
  String? _loadWarning;
  bool _panelSpecsSet = false;
  
  String _historyField = 'pv_input_w';

  @override
  void initState() {
    super.initState();
    _fetchAll();
  }

  Future<void> _fetchAll() async {
    setState(() => _isLoading = true);
    final city = Uri.encodeComponent(UserSettings.locationCity);
    
    // Read panel specs and baseline from UserSettings
    final panelWp    = UserSettings.panelWp;
    final panelCount = UserSettings.panelCount;
    final panelEff   = UserSettings.panelEfficiency;
    final panelTilt  = UserSettings.panelTiltDeg;
    final lat        = UserSettings.latitude;
    final baseline   = UserSettings.baselineLoad; // kWh/day
    // Convert daily kWh to average Watts for backend
    final baselineW  = baseline > 0 ? (baseline * 1000 / 24) : 0.0;

    setState(() {
      _panelSpecsSet = UserSettings.hasPanelSpecs;
    });
    
    try {
      // 1. Weather
      final wUri = Uri.parse('$kApiBase/weather?city=$city');
      http.get(wUri).then((r) {
        if (r.statusCode == 200) {
          final b = json.decode(r.body);
          if (mounted) setState(() {
            _weatherInsight   = b['insight'] ?? 'Unknown';
            _weatherCondition = b['condition'] ?? '';
            _weatherTemp      = (b['temp'] as num?)?.toDouble() ?? 0.0;
          });
        }
      });
      
      // 2. Solar Predict — send real panel specs to backend
      final sUri = Uri.parse(
        '$kApiBase/predict/solar?hours=24&city=$city'
        '&panel_wp=$panelWp&panel_count=$panelCount'
        '&panel_efficiency=$panelEff&panel_tilt_deg=$panelTilt'
        '&latitude=$lat',
      );
      http.get(sUri).then((r) {
        if (r.statusCode == 200) {
          final b = json.decode(r.body);
          final pts = b['points'] as List? ?? [];
          if (mounted) setState(() {
            _solarPred       = pts.map((p) => HistoryPoint(
              time: DateTime.parse(p['time']).toLocal(),
              value: (p['value'] as num).toDouble(),
            )).toList();
            _solarDataSource = b['data_source'] ?? 'unknown';
            _solarWarning    = b['warning'] as String?;
          });
        }
      });
      
      // 3. Load Predict — send user baseline as fallback
      final lUri = Uri.parse('$kApiBase/predict/load?hours=24&baseline_w=$baselineW');
      http.get(lUri).then((r) {
        if (r.statusCode == 200) {
          final b = json.decode(r.body);
          final pts = b['points'] as List? ?? [];
          if (mounted) setState(() {
            _loadPred       = pts.map((p) => HistoryPoint(
              time: DateTime.parse(p['time']).toLocal(),
              value: (p['value'] as num).toDouble(),
            )).toList();
            _loadDataSource = b['data_source'] ?? 'unknown';
            _loadWarning    = b['warning'] as String?;
          });
        }
      });

      // 4. Daily History (10 days)
      await _fetchDailyHistory();

    } catch (e) {
      debugPrint('AI Tab error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  Future<void> _fetchDailyHistory() async {
    try {
      final hUri = Uri.parse('$kApiBase/history?field=$_historyField&range=10d&daily=true');
      final r = await http.get(hUri);
      if (r.statusCode == 200) {
        final b = json.decode(r.body);
        final raw = (b['points'] as List).map((p) => HistoryPoint(
          time: DateTime.parse(p['time']).toLocal(),
          value: (p['value'] as num).toDouble(),
        )).toList();

        // Build a full 10-day grid, filling missing days with 0
        // This fixes the "3 bars bunched on left" problem
        final now   = DateTime.now();
        final Map<String, double> byDay = {
          for (var p in raw)
            '${p.time.year}-${p.time.month.toString().padLeft(2,'0')}-${p.time.day.toString().padLeft(2,'0')}': p.value
        };
        final padded = List.generate(10, (i) {
          final d = DateTime(now.year, now.month, now.day - (9 - i));
          final key = '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
          return HistoryPoint(time: d, value: byDay[key] ?? 0.0);
        });

        if (mounted) setState(() => _dailyHistory = padded);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _solarPred.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.solar));
    }

    return RefreshIndicator(
      onRefresh: _fetchAll,
      color: AppColors.solar,
      backgroundColor: AppColors.card,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          _buildWeatherBlock(),
          const SizedBox(height: 20),
          // Setup banner if panel specs not configured
          if (!_panelSpecsSet) _buildSetupBanner(),
          if (!_panelSpecsSet) const SizedBox(height: 16),
          _buildDataSourceBadge('AI Solar Forecast (24h)', _solarDataSource),
          const SizedBox(height: 8),
          if (_solarWarning != null) _buildWarningBanner(_solarWarning!),
          if (_solarWarning != null) const SizedBox(height: 8),
          _buildSolarChart(),
          const SizedBox(height: 24),
          _buildDataSourceBadge('Expected Load', _loadDataSource),
          const SizedBox(height: 8),
          if (_loadWarning != null) _buildWarningBanner(_loadWarning!),
          if (_loadWarning != null) const SizedBox(height: 8),
          _buildLoadSummary(),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildLabel('10-Day History'),
              const Spacer(),
              _buildHistoryToggle(),
            ],
          ),
          const SizedBox(height: 12),
          _buildDailyBarChart(),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) => Text(text, 
    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary));

  // ── Data source badge ──────────────────────────────────────────────
  Widget _buildDataSourceBadge(String title, String source) {
    final (icon, label, color) = switch (source) {
      'real_data'       => (Icons.sensors_rounded,        'Live Data',       AppColors.battery),
      'panel_specs'     => (Icons.solar_power_rounded,    'Panel Specs',     AppColors.solar),
      'historical_peak' => (Icons.history_rounded,        'Historical Peak', AppColors.voltage),
      'unavailable'     => (Icons.block_rounded,          'No Data',         AppColors.temp),
      _                 => (Icons.hourglass_empty_rounded, 'Loading...',      AppColors.textMuted),
    };
    return Row(children: [
      Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      const Spacer(),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    ]);
  }

  // ── Warning banner ────────────────────────────────────────────────
  Widget _buildWarningBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.temp.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.temp.withOpacity(0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline_rounded, size: 14, color: AppColors.temp),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message, style: GoogleFonts.inter(fontSize: 11, color: AppColors.temp, height: 1.4)),
        ),
      ]),
    );
  }

  // ── Setup nudge banner ────────────────────────────────────────────
  Widget _buildSetupBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.solar.withOpacity(0.08), AppColors.solar.withOpacity(0.03)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.solar.withOpacity(0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.solar_power_rounded, color: AppColors.solar, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Set Up Panel Specs for Accurate Predictions',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.solar)),
            const SizedBox(height: 2),
            Text('Go to Net-Zero → Settings → Panel Setup to enter your solar panel details.',
              style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildWeatherBlock() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.cardAlt, AppColors.card],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bg,
              shape: BoxShape.circle,
            ),
            child: Text(
              _weatherTemp > 35 ? '🔥' : (_weatherCondition.contains('Rain') ? '🌧️' : '☁️'),
              style: const TextStyle(fontSize: 24),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(UserSettings.locationCity, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(_weatherInsight, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.solar)),
                const SizedBox(height: 2),
                Text('${_weatherTemp.toStringAsFixed(1)}°C • $_weatherCondition', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSolarChart() {
    if (_solarPred.isEmpty) return const SizedBox(height: 160, child: Center(child: Text('No solar prediction data')));
    
    double maxY = _solarPred.map((p) => p.value).reduce(math.max);
    if (maxY == 0) maxY = 1000;
    
    final spots = _solarPred.map((p) => FlSpot(p.time.millisecondsSinceEpoch.toDouble(), p.value)).toList();
    
    return Container(
      height: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: LineChart(LineChartData(
        gridData: FlGridData(
          show: true, drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: AppColors.border.withOpacity(0.5), strokeWidth: 1, dashArray: [4, 4]),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true, reservedSize: 38,
            getTitlesWidget: (v, _) => Text('${v.toInt()}', style: GoogleFonts.spaceMono(fontSize: 9, color: AppColors.textMuted)),
          )),
          bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true, reservedSize: 22, interval: 4 * 60 * 60 * 1000.0,
            getTitlesWidget: (v, _) {
              final d = DateTime.fromMillisecondsSinceEpoch(v.toInt());
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('${d.hour.toString().padLeft(2,'0')}:00', style: GoogleFonts.spaceMono(fontSize: 9, color: AppColors.textMuted)),
              );
            },
          )),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minY: 0, maxY: maxY * 1.2,
        lineBarsData: [
          LineChartBarData(
            spots: spots, isCurved: true, curveSmoothness: 0.25,
            color: AppColors.solar, barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, gradient: LinearGradient(
              colors: [AppColors.solar.withOpacity(0.4), Colors.transparent],
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
            )),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.cardAlt,
            getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
              '${s.y.toStringAsFixed(1)} W',
              GoogleFonts.inter(color: AppColors.solar, fontWeight: FontWeight.bold, fontSize: 12)
            )).toList()
          )
        )
      )),
    );
  }
  
  Widget _buildLoadSummary() {
    if (_loadPred.isEmpty) return const SizedBox();
    
    // Calculate peak load and total estimated Wh for next 24h
    double peak = 0; DateTime peakTime = DateTime.now();
    double totalWh = 0;
    for (var p in _loadPred) {
      if (p.value > peak) { peak = p.value; peakTime = p.time; }
      totalWh += p.value; // average 1 hr = Wh
    }
    
    return Row(
      children: [
        Expanded(
          child: Container(
             padding: const EdgeInsets.all(16),
             decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 Text('Estimated Total', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
                 const SizedBox(height: 4),
                 Text('${(totalWh/1000).toStringAsFixed(1)} kWh', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.load)),
                 Text('Next 24 Hours', style: GoogleFonts.inter(fontSize: 10, color: AppColors.textMuted)),
               ],
             ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
             padding: const EdgeInsets.all(16),
             decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 Text('Expected Peak', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
                 const SizedBox(height: 4),
                 Text('${peak.toStringAsFixed(0)} W', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.temp)),
                 Text('At ${peakTime.hour.toString().padLeft(2,'0')}:00', style: GoogleFonts.inter(fontSize: 10, color: AppColors.textMuted)),
               ],
             ),
          ),
        )
      ],
    );
  }

  Widget _buildHistoryToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HistBtn('Solar', 'pv_input_w', _historyField == 'pv_input_w'),
          _HistBtn('Load', 'load_w', _historyField == 'load_w'),
        ],
      ),
    );
  }
  
  Widget _HistBtn(String title, String val, bool selected) {
    return GestureDetector(
      onTap: () {
        setState(() => _historyField = val);
        _fetchDailyHistory();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? (_historyField == 'pv_input_w' ? AppColors.solar.withOpacity(0.2) : AppColors.load.withOpacity(0.2)) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(title, style: GoogleFonts.inter(
          fontSize: 11, fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          color: selected ? (_historyField == 'pv_input_w' ? AppColors.solar : AppColors.load) : AppColors.textMuted,
        )),
      ),
    );
  }

  Widget _buildDailyBarChart() {
    if (_dailyHistory.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
        child: const Center(child: CircularProgressIndicator(color: AppColors.solar, strokeWidth: 2)),
      );
    }

    final color  = _historyField == 'pv_input_w' ? AppColors.solar : AppColors.load;
    double maxY  = _dailyHistory.map((p) => p.value).reduce(math.max);
    if (maxY < 10) maxY = 100;   // avoid flat chart when all values are 0

    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: BarChart(BarChartData(
        maxY: maxY * 1.25,
        groupsSpace: 6,
        gridData: FlGridData(
          show: true, drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppColors.border.withOpacity(0.4), strokeWidth: 1, dashArray: [4, 4]),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true, reservedSize: 36,
            interval: maxY / 3,
            getTitlesWidget: (v, _) => Text(
              v == 0 ? '0' : '${v.toInt()}',
              style: GoogleFonts.spaceMono(fontSize: 8, color: AppColors.textMuted),
            ),
          )),
          bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true, reservedSize: 24,
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= _dailyHistory.length) return const SizedBox();
              final d = _dailyHistory[i].time;
              final isToday = d.day == DateTime.now().day && d.month == DateTime.now().month;
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${d.day}/${d.month}',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                    color: isToday ? color : AppColors.textSecondary,
                  ),
                ),
              );
            },
          )),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        barGroups: List.generate(_dailyHistory.length, (i) {
          final pt      = _dailyHistory[i];
          final hasData = pt.value > 0;
          final isToday = pt.time.day == DateTime.now().day && pt.time.month == DateTime.now().month;
          return BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: hasData ? pt.value : (maxY * 0.015),   // tiny sliver for empty days
              width: 16,
              gradient: hasData
                  ? LinearGradient(
                      colors: isToday
                          ? [color, color.withOpacity(0.7)]
                          : [color.withOpacity(0.6), color.withOpacity(0.3)],
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    )
                  : null,
              color: hasData ? null : AppColors.border.withOpacity(0.3),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
            ),
          ]);
        }),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.cardAlt,
            getTooltipItem: (group, _, rod, __) {
              final pt      = _dailyHistory[group.x];
              final hasData = pt.value > 0;
              final label   = _historyField == 'pv_input_w' ? 'Solar' : 'Load';
              return BarTooltipItem(
                hasData ? '$label: ${rod.toY.toStringAsFixed(0)} W' : 'No data',
                GoogleFonts.inter(
                  color: hasData ? color : AppColors.textMuted,
                  fontWeight: FontWeight.bold, fontSize: 11,
                ),
              );
            },
          ),
        ),
      )),
    );
  }
}
