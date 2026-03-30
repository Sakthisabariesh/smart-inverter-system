import 'package:shared_preferences/shared_preferences.dart';

class UserSettings {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static double get elecRate => _prefs.getDouble('elecRate') ?? 8.5;
  static set elecRate(double value) => _prefs.setDouble('elecRate', value);

  static double get co2Factor => _prefs.getDouble('co2Factor') ?? 0.82;
  static set co2Factor(double value) => _prefs.setDouble('co2Factor', value);

  static double get systemCost => _prefs.getDouble('systemCost') ?? 150000.0;
  static set systemCost(double value) => _prefs.setDouble('systemCost', value);

  static double get baselineLoad => _prefs.getDouble('baselineLoad') ?? 15.0;
  static set baselineLoad(double value) => _prefs.setDouble('baselineLoad', value);
}
