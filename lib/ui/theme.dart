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

/// The bundled monospace face every [Text] inherits.
const String kTerminalFont = 'JetBrainsMono';

class AppTheme {
  static ThemeData get dark => _build(Brightness.dark, TerminalColors.dark);
  static ThemeData get light => _build(Brightness.light, TerminalColors.light);

  static ThemeData _build(Brightness brightness, TerminalColors c) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      // Text on an accent (or ok-green) fill is the ground colour in both
      // themes: dark on dark-theme fills, near-white on light-theme ones.
      onPrimary: c.background,
      secondary: c.accent,
      onSecondary: c.background,
      tertiary: c.ok,
      onTertiary: c.background,
      error: brightness == Brightness.dark
          ? const Color(0xFFE5807A)
          : const Color(0xFFB3261E),
      onError: c.background,
      surface: c.background,
      onSurface: c.text,
      onSurfaceVariant: c.textDim,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.surfaceRaised,
      surfaceContainer: c.surfaceRaised,
      surfaceContainerHigh: c.surfaceRaised,
      surfaceContainerHighest: c.selection,
      outline: c.border,
      outlineVariant: c.border,
      inverseSurface: c.surfaceRaised,
      onInverseSurface: c.text,
      shadow: Colors.transparent,
      scrim: Colors.black,
      surfaceTint: Colors.transparent,
    );

    const square = RoundedRectangleBorder(borderRadius: BorderRadius.zero);
    final accentBox = RoundedRectangleBorder(
      borderRadius: BorderRadius.zero,
      side: BorderSide(color: c.accent),
    );
    final buttonText = WidgetStatePropertyAll(
      const TextStyle(fontFamily: kTerminalFont, fontSize: 13, height: 1.5),
    );
    final flatOverlay = WidgetStateProperty.resolveWith<Color?>(
      (states) => states.isEmpty ? null : c.hover,
    );

    TextStyle body(double size, {FontWeight? weight, Color? color}) =>
        TextStyle(
          fontFamily: kTerminalFont,
          fontSize: size,
          height: 1.5,
          fontWeight: weight,
          color: color ?? c.text,
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: kTerminalFont,
    );

    return base.copyWith(
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      dividerColor: c.border,
      hoverColor: c.hover,
      focusColor: c.hover,
      highlightColor: c.hover,
      splashColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      extensions: [c],
      textTheme: base.textTheme.copyWith(
        displayLarge: body(32, weight: FontWeight.w700),
        displayMedium: body(28, weight: FontWeight.w700),
        displaySmall: body(24, weight: FontWeight.w700),
        headlineLarge: body(22, weight: FontWeight.w700),
        headlineMedium: body(20, weight: FontWeight.w700),
        headlineSmall: body(16, weight: FontWeight.w700),
        titleLarge: body(16, weight: FontWeight.w700),
        titleMedium: body(14, weight: FontWeight.w500),
        titleSmall: body(13, weight: FontWeight.w500),
        bodyLarge: body(13),
        bodyMedium: body(13),
        bodySmall: body(12, color: c.textDim),
        labelLarge: body(13),
        labelMedium: body(12),
        labelSmall: body(11, color: c.textDim),
      ),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(square),
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? c.selection : c.accent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? c.textDim : c.background,
          ),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          textStyle: WidgetStatePropertyAll(
            buttonText.value.copyWith(fontWeight: FontWeight.w700),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(square),
          side: WidgetStatePropertyAll(BorderSide(color: c.borderStrong)),
          foregroundColor: WidgetStatePropertyAll(c.text),
          overlayColor: flatOverlay,
          textStyle: buttonText,
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(square),
          foregroundColor: WidgetStatePropertyAll(c.text2),
          overlayColor: flatOverlay,
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(square),
          overlayColor: flatOverlay,
        ),
      ),
      cardTheme: CardThemeData(
        color: c.background,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(side: BorderSide(color: c.border)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: accentBox,
        textStyle: body(13),
        labelTextStyle: WidgetStatePropertyAll(body(13)),
        menuPadding: const EdgeInsets.symmetric(vertical: 4),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(c.surfaceRaised),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(accentBox),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: accentBox,
        titleTextStyle: body(14, weight: FontWeight.w700),
        contentTextStyle: body(13),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: square,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceRaised,
        contentTextStyle: body(13),
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        shape: accentBox,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          border: Border.all(color: c.border),
        ),
        textStyle: body(12),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        labelStyle: body(13, color: c.textDim),
        floatingLabelStyle: body(13, color: c.accent),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: c.borderStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: c.borderStrong),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: c.accent),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accent,
        selectionColor: c.accent.withValues(alpha: 0.3),
        selectionHandleColor: c.accent,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(4),
        radius: Radius.zero,
        thumbColor: WidgetStatePropertyAll(c.borderStrong),
        crossAxisMargin: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.borderStrong,
        circularTrackColor: Colors.transparent,
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: c.accent,
        inactiveTrackColor: c.borderStrong,
        disabledActiveTrackColor: c.borderStrong,
        disabledInactiveTrackColor: c.borderStrong,
        trackShape: const BoxCharTrackShape(),
        thumbShape: SliderComponentShape.noThumb,
        overlayShape: SliderComponentShape.noOverlay,
        overlayColor: Colors.transparent,
        padding: EdgeInsets.zero,
        showValueIndicator: ShowValueIndicator.never,
      ),
    );
  }
}

/// The terminal palette, read by name rather than hard-coded per widget.
/// Both themes carry one, so a widget never has to ask which mode it is in.
class TerminalColors extends ThemeExtension<TerminalColors> {
  /// Scaffold, panels and sidebar: one flat ground.
  final Color background;

  /// Mini player, menus, tooltips.
  final Color surfaceRaised;

  /// Selected nav item, menu highlight, the queue toggle's fill.
  final Color selection;
  final Color hover;

  /// Background of the row that is currently playing.
  final Color playingRow;

  /// Panel borders and dividers.
  final Color border;

  /// Outlined buttons and the empty part of progress/volume lines.
  final Color borderStrong;

  final Color text;
  final Color text2;
  final Color textDim;

  /// Track numbers only; decorative, so it may sit below contrast minimums.
  final Color textFaint;
  final Color accent;

  /// The playing marker and the PLAYING status badge.
  final Color ok;

  /// Key names in the status line.
  final Color key;

  /// Ground for a cover that has no art.
  final Color artPlaceholder;

  /// Rotating tints for album tiles without art.
  final List<Color> albumTints;

  const TerminalColors({
    required this.background,
    required this.surfaceRaised,
    required this.selection,
    required this.hover,
    required this.playingRow,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.text2,
    required this.textDim,
    required this.textFaint,
    required this.accent,
    required this.ok,
    required this.key,
    required this.artPlaceholder,
    required this.albumTints,
  });

  static const dark = TerminalColors(
    background: Color(0xFF0B0A0D),
    surfaceRaised: Color(0xFF121016),
    selection: Color(0xFF1C1A22),
    hover: Color(0xFF17151C),
    playingRow: Color(0xFF1E1A14),
    border: Color(0xFF2B2833),
    borderStrong: Color(0xFF3A3644),
    text: Color(0xFFE7E4EC),
    text2: Color(0xFFB9B4C4),
    textDim: Color(0xFF8E899B),
    textFaint: Color(0xFF5E5969),
    accent: Color(0xFFE0A458),
    ok: Color(0xFF9CCB86),
    key: Color(0xFF86BFD0),
    artPlaceholder: Color(0xFF2A2219),
    albumTints: [
      Color(0xFFD9919B),
      Color(0xFF86BFD0),
      Color(0xFFB39DDB),
      Color(0xFFE0A458),
      Color(0xFF9CCB86),
    ],
  );

  static const light = TerminalColors(
    background: Color(0xFFF7F5F0),
    surfaceRaised: Color(0xFFEFECE5),
    selection: Color(0xFFE6E1D6),
    hover: Color(0xFFEEEAE2),
    playingRow: Color(0xFFF3E6D2),
    border: Color(0xFFD9D4CC),
    borderStrong: Color(0xFFBDB6AA),
    text: Color(0xFF1A1820),
    text2: Color(0xFF3F3A48),
    textDim: Color(0xFF6B6678),
    textFaint: Color(0xFFA39D92),
    accent: Color(0xFF9A5F22),
    ok: Color(0xFF3F7A2E),
    key: Color(0xFF1F6E85),
    artPlaceholder: Color(0xFFE9DCC7),
    albumTints: [
      Color(0xFFA8505C),
      Color(0xFF1F6E85),
      Color(0xFF6B54A3),
      Color(0xFF9A5F22),
      Color(0xFF3F7A2E),
    ],
  );

  static TerminalColors of(BuildContext context) =>
      Theme.of(context).extension<TerminalColors>()!;

  @override
  TerminalColors copyWith({
    Color? background,
    Color? surfaceRaised,
    Color? selection,
    Color? hover,
    Color? playingRow,
    Color? border,
    Color? borderStrong,
    Color? text,
    Color? text2,
    Color? textDim,
    Color? textFaint,
    Color? accent,
    Color? ok,
    Color? key,
    Color? artPlaceholder,
    List<Color>? albumTints,
  }) => TerminalColors(
    background: background ?? this.background,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    selection: selection ?? this.selection,
    hover: hover ?? this.hover,
    playingRow: playingRow ?? this.playingRow,
    border: border ?? this.border,
    borderStrong: borderStrong ?? this.borderStrong,
    text: text ?? this.text,
    text2: text2 ?? this.text2,
    textDim: textDim ?? this.textDim,
    textFaint: textFaint ?? this.textFaint,
    accent: accent ?? this.accent,
    ok: ok ?? this.ok,
    key: key ?? this.key,
    artPlaceholder: artPlaceholder ?? this.artPlaceholder,
    albumTints: albumTints ?? this.albumTints,
  );

  @override
  TerminalColors lerp(TerminalColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return TerminalColors(
      background: l(background, other.background),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      selection: l(selection, other.selection),
      hover: l(hover, other.hover),
      playingRow: l(playingRow, other.playingRow),
      border: l(border, other.border),
      borderStrong: l(borderStrong, other.borderStrong),
      text: l(text, other.text),
      text2: l(text2, other.text2),
      textDim: l(textDim, other.textDim),
      textFaint: l(textFaint, other.textFaint),
      accent: l(accent, other.accent),
      ok: l(ok, other.ok),
      key: l(key, other.key),
      artPlaceholder: l(artPlaceholder, other.artPlaceholder),
      albumTints: [
        for (var i = 0; i < albumTints.length; i++)
          l(albumTints[i], other.albumTints[i]),
      ],
    );
  }
}

/// Paints a slider's track the way the mockups draw it in box characters:
/// the played part as a heavy `━` line in the active colour, the rest as a
/// light `─` line in the inactive one. Square ends, no thumb.
class BoxCharTrackShape extends SliderTrackShape {
  const BoxCharTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final height = sliderTheme.trackHeight ?? 3;
    final top = offset.dy + (parentBox.size.height - height) / 2;
    return Rect.fromLTWH(offset.dx, top, parentBox.size.width, height);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
    );
    paintBoxCharLine(
      context.canvas,
      rect,
      fraction: rect.width == 0 ? 0 : (thumbCenter.dx - rect.left) / rect.width,
      done: (isEnabled
          ? sliderTheme.activeTrackColor
          : sliderTheme.disabledActiveTrackColor)!,
      rest: (isEnabled
          ? sliderTheme.inactiveTrackColor
          : sliderTheme.disabledInactiveTrackColor)!,
    );
  }
}

/// Draws a `━━━━───` progress line across [rect], filled to [fraction]. The
/// heavy part takes the rect's full height; the light part a third of it.
void paintBoxCharLine(
  Canvas canvas,
  Rect rect, {
  required double fraction,
  required Color done,
  required Color rest,
}) {
  final f = fraction.clamp(0.0, 1.0);
  final split = rect.left + rect.width * f;
  final thin = (rect.height / 3).clamp(1.0, rect.height);
  canvas.drawRect(
    Rect.fromLTRB(split, rect.center.dy - thin / 2, rect.right,
        rect.center.dy + thin / 2),
    Paint()..color = rest,
  );
  canvas.drawRect(
    Rect.fromLTRB(rect.left, rect.top, split, rect.bottom),
    Paint()..color = done,
  );
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
