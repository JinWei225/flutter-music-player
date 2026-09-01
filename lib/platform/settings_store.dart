import 'package:shared_preferences/shared_preferences.dart';

/// Small persistence layer for the handful of things that must survive a
/// restart. Backed by shared_preferences, so it works unchanged on every
/// platform the app is later built for.
class SettingsStore {
  static const _volumeKey = 'player.volume';
  static const _darkModeKey = 'ui.darkMode';

  final SharedPreferences _prefs;

  SettingsStore(this._prefs);

  static Future<SettingsStore> open() async =>
      SettingsStore(await SharedPreferences.getInstance());

  /// Playback volume, 0.0-1.0. Defaults to a comfortable 70% on first run.
  double get volume {
    final v = _prefs.getDouble(_volumeKey);
    if (v == null) return 0.7;
    return v.clamp(0.0, 1.0);
  }

  Future<void> setVolume(double value) =>
      _prefs.setDouble(_volumeKey, value.clamp(0.0, 1.0));

  bool get darkMode => _prefs.getBool(_darkModeKey) ?? true;

  Future<void> setDarkMode(bool value) => _prefs.setBool(_darkModeKey, value);

  // Repeat mode is deliberately NOT persisted: the app always starts on
  // repeat-list, per the app's default-playback behaviour.
}
