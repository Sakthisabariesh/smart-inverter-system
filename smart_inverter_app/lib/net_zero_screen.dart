import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'main.dart';
import 'user_settings.dart';

class NetZeroScreen extends StatefulWidget {
  const NetZeroScreen({super.key});
  @override
  State<NetZeroScreen> createState() => _NetZeroScreenState();
}

class _NetZeroScreenState extends State<NetZeroScreen>
    with SingleTickerProviderStateMixin {
  final _rateCt   = TextEditingController();
  final _co2Ct    = TextEditingController();
  final _costCt   = TextEditingController();
  final _baseCt   = TextEditingController();
  final _locCt    = TextEditingController();
  // Panel spec controllers
  final _panelWpCt    = TextEditingController();
  final _panelCntCt   = TextEditingController();
  final _panelEffCt   = TextEditingController();
  final _panelTiltCt  = TextEditingController();
  final _latCt        = TextEditingController();
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _rateCt.text  = UserSettings.elecRate.toString();
    _co2Ct.text   = UserSettings.co2Factor.toString();
    _costCt.text  = UserSettings.systemCost > 0 ? UserSettings.systemCost.toString() : '';
    _baseCt.text  = UserSettings.baselineLoad > 0 ? UserSettings.baselineLoad.toString() : '';
    _locCt.text   = UserSettings.locationCity;
    // Panel specs (show blank if 0 = not set yet)
    _panelWpCt.text   = UserSettings.panelWp > 0   ? UserSettings.panelWp.toString()   : '';
    _panelCntCt.text  = UserSettings.panelCount > 0 ? UserSettings.panelCount.toString() : '';
    _panelEffCt.text  = UserSettings.panelEfficiency > 0 ? UserSettings.panelEfficiency.toString() : '';
    _panelTiltCt.text = UserSettings.panelTiltDeg.toString();
    _latCt.text       = UserSettings.latitude.toString();
  }

  @override
  void dispose() {
    _rateCt.dispose(); _co2Ct.dispose();
    _costCt.dispose(); _baseCt.dispose(); _locCt.dispose();
    _panelWpCt.dispose(); _panelCntCt.dispose();
    _panelEffCt.dispose(); _panelTiltCt.dispose(); _latCt.dispose();
    _tabs.dispose();
    super.dispose();
  }

  // ── computed values ───────────────────────────────────────────────
  double get _rate     => double.tryParse(_rateCt.text)  ?? 8.5;
  double get _co2      => double.tryParse(_co2Ct.text)   ?? 0.82;
  double get _cost     => double.tryParse(_costCt.text)  ?? 150000;
  double get _baseline => double.tryParse(_baseCt.text)  ?? 15.0;

  double get _dailySavings  => _baseline * _rate;
  double get _yearlySavings => _dailySavings * 365;
  double get _yearlyCo2     => _baseline * _co2 * 365;
  double get _roiYears      => _cost / (_yearlySavings > 0 ? _yearlySavings : 1);
  double get _roiPercent    => (_yearlySavings / _cost) * 100;

  void _save() {
    setState(() {
      UserSettings.elecRate     = _rate;
      UserSettings.co2Factor    = _co2;
      UserSettings.systemCost   = _cost;
      UserSettings.baselineLoad = _baseline;
      UserSettings.locationCity = _locCt.text.trim();
      // Panel specs — only save if non-zero
      final wp  = double.tryParse(_panelWpCt.text)  ?? 0.0;
      final cnt = int.tryParse(_panelCntCt.text)    ?? 0;
      final eff = double.tryParse(_panelEffCt.text) ?? 0.0;
      final tilt= double.tryParse(_panelTiltCt.text)?? 15.0;
      final lat = double.tryParse(_latCt.text)      ?? 10.79;
      UserSettings.panelWp         = wp;
      UserSettings.panelCount      = cnt;
      UserSettings.panelEfficiency = eff;
      UserSettings.panelTiltDeg    = tilt;
      UserSettings.latitude        = lat;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Settings updated', style: GoogleFonts.inter()),
      backgroundColor: AppColors.battery,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        titleSpacing: 16,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('Net-Zero Analysis',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          Text('Energy, Savings & CO₂',
            style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary)),
        ]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: TabBar(
              controller: _tabs,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  colors: [AppColors.solar, AppColors.voltage],
                  begin: Alignment.centerLeft, end: Alignment.centerRight,
                ),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
              unselectedLabelStyle: GoogleFonts.inter(fontSize: 12),
              labelColor: Colors.black,
              unselectedLabelColor: AppColors.textSecondary,
              tabs: const [Tab(text: 'Dashboard'), Tab(text: 'Settings')],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildDashboard(),
          _buildSettings(),
        ],
      ),
    );
  }

  // ── Dashboard Tab ─────────────────────────────────────────────────
  Widget _buildDashboard() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildKpiRow(),
        const SizedBox(height: 20),
        _sectionTitle('Savings Forecast'),
        const SizedBox(height: 12),
        _buildSavingsChart(),
        const SizedBox(height: 20),
        _sectionTitle('CO₂ Reduction'),
        const SizedBox(height: 12),
        _buildCo2Card(),
        const SizedBox(height: 20),
        _sectionTitle('ROI Breakdown'),
        const SizedBox(height: 12),
        _buildROICard(),
        const SizedBox(height: 20),
        _sectionTitle('Baseline vs. Solar'),
        const SizedBox(height: 12),
        _buildBaselineChart(),
      ]),
    );
  }

  // ── KPI Row ───────────────────────────────────────────────────────
  Widget _buildKpiRow() {
    return Row(children: [
      Expanded(child: _KpiCard(
        icon: Icons.savings_rounded, color: AppColors.savings,
        label: 'Daily Savings', value: '₹${_dailySavings.toStringAsFixed(0)}')),
      const SizedBox(width: 10),
      Expanded(child: _KpiCard(
        icon: Icons.cloud_off_rounded, color: AppColors.co2,
        label: 'CO₂ / Year', value: '${(_yearlyCo2 / 1000).toStringAsFixed(2)} t')),
      const SizedBox(width: 10),
      Expanded(child: _KpiCard(
        icon: Icons.calendar_today_rounded, color: AppColors.netZero,
        label: 'ROI Period', value: '${_roiYears.toStringAsFixed(1)} yr')),
    ]);
  }

  // ── Monthly savings bar chart ─────────────────────────────────────
  Widget _buildSavingsChart() {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    // Solar variation factor per month (more sun in summer months in India)
    final factors = [0.7, 0.75, 0.85, 0.95, 1.0, 1.0, 0.9, 0.88, 0.92, 0.88, 0.78, 0.70];
    final maxVal = _dailySavings * 30 * 1.05;

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Monthly Savings (₹)',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.savings.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('₹${_yearlySavings.toStringAsFixed(0)} / yr',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.savings)),
          ),
        ]),
        const SizedBox(height: 20),
        SizedBox(height: 160, child: BarChart(
          BarChartData(
            maxY: maxVal,
            gridData: FlGridData(
              show: true, drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(
                color: AppColors.border.withOpacity(0.5), strokeWidth: 1, dashArray: [4, 4]),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true, reservedSize: 20,
                getTitlesWidget: (v, _) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(months[v.toInt()].substring(0, 1),
                    style: GoogleFonts.inter(fontSize: 10, color: AppColors.textMuted)),
                ),
              )),
            ),
            barGroups: List.generate(12, (i) {
              final h = _dailySavings * 30 * factors[i];
              return BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: h, width: 14,
                  gradient: LinearGradient(
                    colors: [AppColors.savings.withOpacity(0.6), AppColors.savings],
                    begin: Alignment.bottomCenter, end: Alignment.topCenter),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                ),
              ]);
            }),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => AppColors.cardAlt,
                getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                  '${months[group.x]}\n₹${rod.toY.toStringAsFixed(0)}',
                  GoogleFonts.inter(color: AppColors.savings, fontWeight: FontWeight.w600, fontSize: 12)),
              ),
            ),
          ),
        )),
      ]),
    );
  }

  // ── CO2 Card ──────────────────────────────────────────────────────
  Widget _buildCo2Card() {
    final trees = (_yearlyCo2 / 21).round(); // avg tree absorbs ~21kg CO2/year
    final progress = math.min(_baseline / 20.0, 1.0);
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.co2.withOpacity(0.15),
              border: Border.all(color: AppColors.co2.withOpacity(0.4)),
            ),
            child: const Icon(Icons.eco_rounded, color: AppColors.co2, size: 22),
          ),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${(_yearlyCo2 / 1000).toStringAsFixed(2)} tonnes',
              style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1)),
            Text('CO₂ avoided per year', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
          ]),
          const Spacer(),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('🌳 $trees', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.battery)),
            Text('trees equiv.', style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary)),
          ]),
        ]),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(children: [
            Container(height: 12, color: AppColors.border),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => FractionallySizedBox(
                widthFactor: v,
                child: Container(height: 12,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.co2, AppColors.battery],
                      begin: Alignment.centerLeft, end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  )),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Text('Based on ${_baseline.toStringAsFixed(1)} kWh/day baseline usage',
          style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
      ]),
    );
  }

  // ── ROI Card ──────────────────────────────────────────────────────
  Widget _buildROICard() {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _RoiStat('Annual Return', '${_roiPercent.toStringAsFixed(1)}%', AppColors.savings),
          const SizedBox(width: 10),
          _RoiStat('Payback Period', '${_roiYears.toStringAsFixed(1)} yrs', AppColors.solar),
          const SizedBox(width: 10),
          _RoiStat('System Cost', '₹${(_cost / 1000).toStringAsFixed(0)}K', AppColors.co2),
        ]),
        const SizedBox(height: 20),
        // Yearly savings / cost gauge
        Row(children: [
          Text('Payback Progress', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
          const Spacer(),
          Text('Year 1 of ${_roiYears.toStringAsFixed(1)}',
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(children: [
            Container(height: 12, color: AppColors.border),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: math.min(1 / math.max(_roiYears, 1), 1.0)),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => FractionallySizedBox(
                widthFactor: v,
                child: Container(height: 12,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.solar, AppColors.savings],
                      begin: Alignment.centerLeft, end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  )),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── Baseline vs Solar bar pair ───────────────────────────────────
  Widget _buildBaselineChart() {
    final months = ['J','F','M','A','M','J','J','A','S','O','N','D'];
    final factors = [0.7, 0.75, 0.85, 0.95, 1.0, 1.0, 0.9, 0.88, 0.92, 0.88, 0.78, 0.70];
    final maxVal  = math.max(_baseline, _baseline * 1.2);

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _Dot2(AppColors.border, 'Baseline'),
          const SizedBox(width: 16),
          _Dot2(AppColors.solar, 'Solar Gen'),
        ]),
        const SizedBox(height: 16),
        SizedBox(height: 140, child: BarChart(
          BarChartData(
            maxY: maxVal * 1.15,
            gridData: FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true, reservedSize: 20,
                getTitlesWidget: (v, _) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(months[v.toInt()],
                    style: GoogleFonts.inter(fontSize: 10, color: AppColors.textMuted)),
                ),
              )),
            ),
            groupsSpace: 6,
            barGroups: List.generate(12, (i) => BarChartGroupData(x: i, barsSpace: 3, barRods: [
              BarChartRodData(toY: _baseline, width: 8,
              color: AppColors.border.withOpacity(0.8),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
              BarChartRodData(toY: _baseline * factors[i], width: 8,
                gradient: LinearGradient(
                  colors: [AppColors.solar.withOpacity(0.6), AppColors.solar],
                  begin: Alignment.bottomCenter, end: Alignment.topCenter),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
            ])),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => AppColors.cardAlt,
                getTooltipItem: (group, _, rod, rodIdx) => BarTooltipItem(
                  rodIdx == 0 ? 'Base: ${_baseline.toStringAsFixed(1)} kWh' : 'Solar: ${rod.toY.toStringAsFixed(1)} kWh',
                  GoogleFonts.inter(color: rodIdx == 0 ? AppColors.textSecondary : AppColors.solar,
                    fontWeight: FontWeight.w600, fontSize: 12)),
              ),
            ),
          ),
        )),
      ]),
    );
  }

  // ── Settings Tab ──────────────────────────────────────────────────
  Widget _buildSettings() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ──────────────────── PANEL SETUP ────────────────────
        _sectionTitle('☀️ Panel Setup'),
        const SizedBox(height: 6),
        Text('Enter your actual solar panel specifications. Used by the AI to produce accurate, physics-based predictions instead of estimates.',
          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary, height: 1.5)),
        const SizedBox(height: 14),
        _settingsField('Panel Rated Power', _panelWpCt, 'Wp / panel',
          Icons.solar_power_rounded, AppColors.solar, 'e.g. 400'),
        const SizedBox(height: 12),
        _settingsField('Number of Panels', _panelCntCt, 'panels',
          Icons.grid_view_rounded, AppColors.solar, 'e.g. 5', isInt: true),
        const SizedBox(height: 12),
        _settingsField('Panel Efficiency', _panelEffCt, '%',
          Icons.bolt_rounded, AppColors.voltage, 'e.g. 20.5'),
        const SizedBox(height: 12),
        _settingsField('Panel Tilt Angle', _panelTiltCt, '° from horizontal',
          Icons.rotate_right_rounded, AppColors.battery, 'e.g. 15'),
        const SizedBox(height: 12),
        _settingsField('Location Latitude', _latCt, '°N',
          Icons.location_on_rounded, AppColors.co2, 'e.g. 10.79 (Trichy)'),

        // Computed system capacity preview
        if ((double.tryParse(_panelWpCt.text) ?? 0) > 0 &&
            (int.tryParse(_panelCntCt.text) ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.solar.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.solar.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded, color: AppColors.solar, size: 16),
                const SizedBox(width: 8),
                Text(
                  'System capacity: ${((double.tryParse(_panelWpCt.text) ?? 0) * (int.tryParse(_panelCntCt.text) ?? 0)).toStringAsFixed(0)} Wp rated',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.solar),
                ),
              ]),
            ),
          ),

        const SizedBox(height: 28),
        const Divider(color: AppColors.border),
        const SizedBox(height: 20),

        // ─────────────────── CALCULATION PARAMETERS ────────────────
        _sectionTitle('Calculation Parameters'),
        const SizedBox(height: 6),
        Text('Used to compute savings, CO₂ impact, and ROI. Enter your actual values.',
          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary, height: 1.5)),
        const SizedBox(height: 20),
        _settingsField('Electricity Rate', _rateCt, '₹/kWh', Icons.currency_rupee_rounded,
          AppColors.solar, 'e.g. 8.50 (check your bill)'),
        const SizedBox(height: 14),
        _settingsField('Location City', _locCt, '', Icons.location_city_rounded,
          AppColors.voltage, 'e.g. Trichy', isText: true),
        const SizedBox(height: 14),
        _settingsField('Grid CO₂ Emission Factor', _co2Ct, 'kg CO₂/kWh', Icons.cloud_rounded,
          AppColors.co2, 'Indian grid avg: 0.82'),
        const SizedBox(height: 14),
        _settingsField('System Installation Cost', _costCt, '₹', Icons.account_balance_wallet_rounded,
          AppColors.savings, 'Enter your actual system cost'),
        const SizedBox(height: 14),
        _settingsField('Baseline Daily Energy', _baseCt, 'kWh/day', Icons.insights_rounded,
          AppColors.load, 'Your daily usage before solar'),
        const SizedBox(height: 24),

        // Preview card
        _buildLivePreview(),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.solar,
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text('Save & Apply', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ]),
    );
  }

  Widget _buildLivePreview() {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.preview_rounded, color: AppColors.solar, size: 18),
          const SizedBox(width: 8),
          Text('Live Preview', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ]),
        const SizedBox(height: 14),
        _previewRow('Daily Savings', '₹${_dailySavings.toStringAsFixed(2)}', AppColors.savings),
        const Divider(height: 20, color: AppColors.border),
        _previewRow('Annual Savings', '₹${_yearlySavings.toStringAsFixed(0)}', AppColors.savings),
        const Divider(height: 20, color: AppColors.border),
        _previewRow('CO₂ Avoided / Year', '${_yearlyCo2.toStringAsFixed(1)} kg', AppColors.co2),
        const Divider(height: 20, color: AppColors.border),
        _previewRow('Payback Period', '${_roiYears.toStringAsFixed(1)} years', AppColors.solar),
      ]),
    );
  }

  Widget _previewRow(String label, String value, Color c) => Row(children: [
    Text(label, style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
    const Spacer(),
    Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: c)),
  ]);

  Widget _settingsField(String label, TextEditingController ctrl, String suffix,
      IconData icon, Color color, String hint, {bool isText = false, bool isInt = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        keyboardType: isText
            ? TextInputType.text
            : isInt
                ? TextInputType.number
                : const TextInputType.numberWithOptions(decimal: true),
        style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 15),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: hint, hintStyle: GoogleFonts.inter(color: AppColors.textMuted),
          prefixIcon: Icon(icon, color: color, size: 20),
          suffixText: suffix,
          suffixStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12),
          filled: true,
          fillColor: AppColors.card,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: color, width: 1.5)),
        ),
      ),
    ]);
  }

  Widget _sectionTitle(String title) => Text(title,
    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary));
}

// ─────────────────────────── Helpers ────────────────────────────────
class _KpiCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, value;
  const _KpiCard({required this.icon, required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(height: 8),
      Text(value, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800,
        color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 2),
      Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary)),
    ]),
  );
}

class _RoiStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _RoiStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary)),
      ]),
    ),
  );
}

class _Dot2 extends StatelessWidget {
  final Color color;
  final String label;
  const _Dot2(this.color, this.label);

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
    const SizedBox(width: 6),
    Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
  ]);
}
