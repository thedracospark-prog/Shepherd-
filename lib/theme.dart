import 'package:flutter/material.dart';

/// RuView-inspired observatory theme: near-black background, floating
/// glass panels, monospace technical type, glowing accents.
/// Dark only — there is intentionally no light theme.

class SentryColors {
  static const background = Color(0xFF060809); // near-black
  static const surface = Color(0xFF0B0F14); // floating panel
  static const surface2 = Color(0xFF121822); // inputs, wells
  static const border = Color(0xFF1E2A36); // hairline panel borders

  static const green = Color(0xFF4ADE80); // ok / present / clear
  static const red = Color(0xFFF87171); // alert values
  static const amber = Color(0xFFFBBF24); // warning / detected
  static const orange = Color(0xFFFB923C); // accent
  static const blue = Color(0xFF60A5FA); // signal values / links
  static const cyan = Color(0xFF22D3EE); // legacy accent (kept for compat)
  static const purple = Color(0xFFA78BFA); // scan actions
  static const muted = Color(0xFF8A94A6); // secondary labels

  static const onDark = Color(0xFFE8EEF4); // primary text
}

/// Monospace technical typography, RuView style.
class SentryType {
  static const String mono = 'JetBrainsMono';

  /// Letterspaced section header, e.g. "VITAL SIGNS".
  static TextStyle section([double size = 11]) => TextStyle(
        fontFamily: mono,
        fontSize: size,
        letterSpacing: 2.4,
        color: SentryColors.muted,
        fontWeight: FontWeight.w500,
      );

  /// Big numeric readout, e.g. "121".
  static TextStyle readout(double size, Color color) => TextStyle(
        fontFamily: mono,
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0.5,
      );

  static TextStyle rowLabel() => const TextStyle(
        fontFamily: mono,
        fontSize: 12,
        color: SentryColors.muted,
        letterSpacing: 0.8,
      );

  static TextStyle rowValue(Color color) => TextStyle(
        fontFamily: mono,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: color,
      );

  static TextStyle chip(Color color) => TextStyle(
        fontFamily: mono,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.6,
        color: color,
      );
}

/// Floating dark panel with a hairline border, RuView style.
class SentryPanel extends StatelessWidget {
  const SentryPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.glow,
  });

  final Widget child;
  final EdgeInsets padding;

  /// Optional accent glow: tints the border and casts a soft outer
  /// shadow. Used for alert states (amber DETECTED, green CLEAR).
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SentryColors.surface,
        border: Border.all(color: glow ?? SentryColors.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: glow == null
            ? null
            : [
                BoxShadow(
                  color: glow!.withAlpha(50),
                  blurRadius: 28,
                  spreadRadius: 1,
                ),
              ],
      ),
      padding: padding,
      child: child,
    );
  }
}

/// Outlined pill chip, e.g. "INBOUND", "SIZE M".
class SentryChip extends StatelessWidget {
  const SentryChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        border: Border.all(color: color.withAlpha(160)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
          ],
          Text(label, style: SentryType.chip(color)),
        ],
      ),
    );
  }
}

/// Small floating + / − / 1:1 zoom controls for the 3D views.
class SentryZoomControls extends StatelessWidget {
  const SentryZoomControls({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SentryColors.surface.withAlpha(220),
        border: Border.all(color: SentryColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn('+', onZoomIn),
          _btn('−', onZoomOut),
          _btn('1:1', onReset),
        ],
      ),
    );
  }

  Widget _btn(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(label, style: SentryType.chip(SentryColors.onDark)),
      ),
    );
  }
}

ThemeData buildDarkTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    colorScheme: const ColorScheme.dark(
      primary: SentryColors.blue,
      secondary: SentryColors.amber,
      surface: SentryColors.surface,
      error: SentryColors.red,
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onSurface: SentryColors.onDark,
    ),
    scaffoldBackgroundColor: SentryColors.background,
    cardColor: SentryColors.surface,
    dividerColor: SentryColors.border,
    appBarTheme: AppBarTheme(
      backgroundColor: SentryColors.background,
      foregroundColor: SentryColors.onDark,
      elevation: 0,
      titleTextStyle: SentryType.section(15).copyWith(
        color: SentryColors.onDark,
        letterSpacing: 4,
        fontWeight: FontWeight.w700,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF080B0E),
      selectedItemColor: SentryColors.green,
      unselectedItemColor: SentryColors.muted,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? SentryColors.green : SentryColors.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? SentryColors.green.withAlpha(90)
            : SentryColors.surface2,
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: SentryColors.blue,
      inactiveTrackColor: SentryColors.surface2,
      thumbColor: SentryColors.blue,
      overlayColor: SentryColors.blue.withAlpha(40),
      valueIndicatorColor: SentryColors.surface2,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SentryColors.surface2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: SentryColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: SentryColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: SentryColors.blue),
      ),
      labelStyle: const TextStyle(
          color: SentryColors.muted, fontFamily: SentryType.mono, fontSize: 12),
      hintStyle: const TextStyle(
          color: SentryColors.muted, fontFamily: SentryType.mono, fontSize: 12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: SentryColors.green,
        foregroundColor: Colors.black,
        textStyle: const TextStyle(
          fontFamily: SentryType.mono,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          fontSize: 13,
        ),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        padding:
            const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: SentryColors.blue,
        textStyle: const TextStyle(
          fontFamily: SentryType.mono,
          fontSize: 12,
          letterSpacing: 1.2,
        ),
      ),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: SentryColors.onDark,
      displayColor: SentryColors.onDark,
    ),
  );
}
