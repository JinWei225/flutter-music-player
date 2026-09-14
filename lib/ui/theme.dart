import 'package:flutter/material.dart';

import '../platform/settings_store.dart';

/// Holds the light/dark choice and writes it through to storage.
class ThemeController extends ChangeNotifier {
  final SettingsStore _settings;
  bool _dark;

  ThemeController(this._settings) : _dark = _settings.darkMode;

  bool get isDark => _dark;
  ThemeMode get mode => _dark ? ThemeMode.dark : ThemeMode.light;

  Future<void> toggle() async {
    _dark = !_dark;
    notifyListeners();
    await _settings.setDarkMode(_dark);
  }
}

class AppTheme {
  static const _accent = Color(0xFFB07750);

  /// Extra surfaces the Material scheme has no direct slot for.
  static const darkSidebar = Color(0xFF0E0D11);
  static const lightSidebar = Color(0xFFF1EFF5);

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        scheme: const ColorScheme.dark(
          primary: _accent,
          onPrimary: Colors.white,
          secondary: _accent,
          surface: Color(0xFF151319),
          onSurface: Color(0xFFECEAF2),
          surfaceContainerHighest: Color(0xFF221F29),
          onSurfaceVariant: Color(0xFF9C97A8),
          outline: Color(0xFF322E3B),
        ),
        canvas: const Color(0xFF121016),
        sidebar: darkSidebar,
        hover: Colors.white.withValues(alpha: 0.05),
      );

  static ThemeData get light => _build(
        brightness: Brightness.light,
        scheme: const ColorScheme.light(
          primary: _accent,
          onPrimary: Colors.white,
          secondary: _accent,
          surface: Colors.white,
          onSurface: Color(0xFF1A1820),
          surfaceContainerHighest: Color(0xFFEDEAF2),
          onSurfaceVariant: Color(0xFF6B6678),
          outline: Color(0xFFDDD9E4),
        ),
        canvas: const Color(0xFFFBFAFC),
        sidebar: lightSidebar,
        hover: Colors.black.withValues(alpha: 0.04),
      );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required Color canvas,
    required Color sidebar,
    required Color hover,
  }) {
    final base = ThemeData(brightness: brightness, colorScheme: scheme);
    return base.copyWith(
      scaffoldBackgroundColor: canvas,
      dividerColor: scheme.outline,
      extensions: [AppSurfaces(sidebar: sidebar, hover: hover)],
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.outline,
        thumbColor: scheme.primary,
        trackHeight: 4,
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(color: scheme.onSurface, fontSize: 12),
      ),
    );
  }
}

/// Theme slots Material does not provide, kept type-safe via ThemeExtension.
class AppSurfaces extends ThemeExtension<AppSurfaces> {
  final Color sidebar;
  final Color hover;

  const AppSurfaces({required this.sidebar, required this.hover});

  static AppSurfaces of(BuildContext context) =>
      Theme.of(context).extension<AppSurfaces>()!;

  @override
  AppSurfaces copyWith({Color? sidebar, Color? hover}) => AppSurfaces(
        sidebar: sidebar ?? this.sidebar,
        hover: hover ?? this.hover,
      );

  @override
  AppSurfaces lerp(AppSurfaces? other, double t) {
    if (other == null) return this;
    return AppSurfaces(
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      hover: Color.lerp(hover, other.hover, t)!,
    );
  }
}

/// mm:ss, or h:mm:ss for anything over an hour.
String formatDuration(Duration? d) {
  if (d == null) return '--:--';
  final total = d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}
