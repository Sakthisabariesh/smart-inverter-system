import 'package:shared_preferences/shared_preferences.dart';

class UserSettings {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ── Energy & Finance ────────────────────────────────────────────────
  static double get elecRate => _prefs.getDouble('elecRate') ?? 8.5;
  static set elecRate(double v) => _prefs.setDouble('elecRate', v);

  static double get co2Factor => _prefs.getDouble('co2Factor') ?? 0.82;
  static set co2Factor(double v) => _prefs.setDouble('co2Factor', v);

  static double get systemCost => _prefs.getDouble('systemCost') ?? 0.0;
  static set systemCost(double v) => _prefs.setDouble('systemCost', v);

  static double get baselineLoad => _prefs.getDouble('baselineLoad') ?? 0.0;
  static set baselineLoad(double v) => _prefs.setDouble('baselineLoad', v);

  // ── Location ────────────────────────────────────────────────────────
  static String get locationCity => _prefs.getString('locationCity') ?? 'Trichy';
  static set locationCity(String v) => _prefs.setString('locationCity', v);

  static double get latitude => _prefs.getDouble('latitude') ?? 10.79;
  static set latitude(double v) => _prefs.setDouble('latitude', v);

  static double get longitude => _prefs.getDouble('longitude') ?? 78.70;
  static set longitude(double v) => _prefs.setDouble('longitude', v);

  // ── Solar Panel Specifications ──────────────────────────────────────
  /// Rated power of ONE panel in Watts (e.g. 400)
  static double get panelWp => _prefs.getDouble('panelWp') ?? 0.0;
  static set panelWp(double v) => _prefs.setDouble('panelWp', v);

  /// Number of panels installed
  static int get panelCount => _prefs.getInt('panelCount') ?? 0;
  static set panelCount(int v) => _prefs.setInt('panelCount', v);

  /// Panel efficiency as a percentage (e.g. 20.0)
  static double get panelEfficiency => _prefs.getDouble('panelEfficiency') ?? 0.0;
  static set panelEfficiency(double v) => _prefs.setDouble('panelEfficiency', v);

  /// Panel tilt angle from horizontal in degrees (e.g. 15)
  static double get panelTiltDeg => _prefs.getDouble('panelTiltDeg') ?? 15.0;
  static set panelTiltDeg(double v) => _prefs.setDouble('panelTiltDeg', v);

  /// Total system rated capacity in watts (computed)
  static double get systemWp => panelWp * panelCount;

  /// Whether the user has configured their panel specs
  static bool get hasPanelSpecs => panelWp > 0 && panelCount > 0 && panelEfficiency > 0;

  /// Whether the user has configured baseline load
  static bool get hasBaselineLoad => baselineLoad > 0;
}
