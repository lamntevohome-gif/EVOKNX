import 'package:flutter/material.dart';

/// EVOKNX colour tokens (same values as the web editor).
@immutable
class EvoColors extends ThemeExtension<EvoColors> {
  final Color paper, panel, ink, muted, line, lineStrong, accent, accentInk, accentSoft, led, danger, dangerSoft, warn;
  const EvoColors({
    required this.paper,
    required this.panel,
    required this.ink,
    required this.muted,
    required this.line,
    required this.lineStrong,
    required this.accent,
    required this.accentInk,
    required this.accentSoft,
    required this.led,
    required this.danger,
    required this.dangerSoft,
    required this.warn,
  });

  static const light = EvoColors(
    paper: Color(0xFFF2F4F3),
    panel: Color(0xFFFFFFFF),
    ink: Color(0xFF1B2320),
    muted: Color(0xFF66716C),
    line: Color(0xFFDEE3E0),
    lineStrong: Color(0xFFC3CBC7),
    accent: Color(0xFF1E7F57),
    accentInk: Color(0xFF17654A),
    accentSoft: Color(0xFFE2F1E9),
    led: Color(0xFFEE9B2A),
    danger: Color(0xFFC2412D),
    dangerSoft: Color(0xFFFBE9E5),
    warn: Color(0xFFA86A12),
  );

  static const dark = EvoColors(
    paper: Color(0xFF141819),
    panel: Color(0xFF1C2123),
    ink: Color(0xFFE7ECE9),
    muted: Color(0xFF9AA59F),
    line: Color(0xFF2E3537),
    lineStrong: Color(0xFF434C4F),
    accent: Color(0xFF3DAA7A),
    accentInk: Color(0xFF5CC497),
    accentSoft: Color(0xFF1D3328),
    led: Color(0xFFF2AA45),
    danger: Color(0xFFE7735E),
    dangerSoft: Color(0xFF3A201B),
    warn: Color(0xFFE0A84F),
  );

  @override
  EvoColors copyWith() => this;

  @override
  EvoColors lerp(ThemeExtension<EvoColors>? other, double t) => (other is EvoColors && t > 0.5) ? other : this;
}

extension EvoTheme on BuildContext {
  EvoColors get evo => Theme.of(this).extension<EvoColors>() ?? EvoColors.light;
}

ThemeData buildTheme(Brightness b) {
  final c = b == Brightness.dark ? EvoColors.dark : EvoColors.light;
  final base = ThemeData(
    useMaterial3: true,
    brightness: b,
    fontFamily: 'Segoe UI',
    colorScheme: ColorScheme.fromSeed(seedColor: c.accent, brightness: b, primary: c.accent, surface: c.panel),
    scaffoldBackgroundColor: c.paper,
    dividerColor: c.line,
    visualDensity: VisualDensity.compact,
    extensions: [c],
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: c.line),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: c.panel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.accent, width: 1.4),
      ),
      hintStyle: TextStyle(color: c.muted, fontSize: 13.5),
      labelStyle: TextStyle(color: c.muted, fontSize: 13),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : null),
      side: BorderSide(color: c.lineStrong, width: 1.4),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      textStyle: TextStyle(color: c.paper, fontSize: 12.5),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.ink,
      contentTextStyle: TextStyle(color: c.paper, fontSize: 13.5),
      width: 520,
    ),
  );
}
