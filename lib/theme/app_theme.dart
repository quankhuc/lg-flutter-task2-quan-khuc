// Centralizes Material 3 theme tokens. Emerald-600 seed color reads as
// "engineering tool, live signal." Lifted out of main.dart so theme tokens
// live in one file.

import 'package:flutter/material.dart';

import '../utils/connection_log.dart';

class AppTheme {
  /// Emerald-600 from Tailwind/shadcn. Reads as "engineering tool, live signal."
  static const Color seedColor = Color(0xFF059669);

  // -------- Log severity colors (shadcn-vue semantic mapping) --------
  //
  // shadcn does not ship info/warn/success tokens by default — only destructive
  // + neutrals. We map directly to Tailwind scales, pushed to shades that pass
  // WCAG AA (4.5:1) for normal monospace text.
  //
  // Light mode on white (4.5:1 required):
  //   debug  zinc-500   #71717A  5.76:1
  //   info   sky-600    #0284C7  4.84:1
  //   warn   amber-700  #B45309  4.84:1   ← amber-500 FAILS on white
  //   error  red-600    #DC2626  5.89:1   ← red-500  FAILS on white
  //
  // Dark mode on zinc-900 (all pass with >7:1):
  //   debug  zinc-400   #A1A1AA
  //   info   sky-400    #38BDF8
  //   warn   amber-400  #FBBF24
  //   error  red-400    #F87171
  //
  // Multi-modal per PatternFly/Red Hat/Carbon: color alone is not enough.
  // The severity WORD (INFO/WARN/ERROR) + its fixed left-column POSITION
  // supply the second and third accessibility channels.
  static const Color _debugLight = Color(0xFF71717A); // zinc-500
  static const Color _infoLight = Color(0xFF0284C7); //  sky-600
  static const Color _warnLight = Color(0xFFB45309); //  amber-700
  static const Color _errorLight = Color(0xFFDC2626); // red-600

  static const Color _debugDark = Color(0xFFA1A1AA); //  zinc-400
  static const Color _infoDark = Color(0xFF38BDF8); //   sky-400
  static const Color _warnDark = Color(0xFFFBBF24); //   amber-400
  static const Color _errorDark = Color(0xFFF87171); //  red-400

  /// Returns the severity color for the given brightness. Called per row in
  /// the log panel. Branchless switch keeps rebuilds cheap.
  static Color logColor(LogSeverity severity, Brightness brightness) {
    if (brightness == Brightness.dark) {
      return switch (severity) {
        LogSeverity.debug => _debugDark,
        LogSeverity.info => _infoDark,
        LogSeverity.warn => _warnDark,
        LogSeverity.error => _errorDark,
      };
    }
    return switch (severity) {
      LogSeverity.debug => _debugLight,
      LogSeverity.info => _infoLight,
      LogSeverity.warn => _warnLight,
      LogSeverity.error => _errorLight,
    };
  }

  static ColorScheme get lightScheme =>
      ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.light);

  static ColorScheme get darkScheme =>
      ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark);

  static ThemeData buildTheme(ColorScheme scheme) => ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: scheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: scheme.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            // .withValues replaces deprecated .withOpacity in Flutter 3.27+.
            side: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      );

  static ThemeData get light => buildTheme(lightScheme);
  static ThemeData get dark => buildTheme(darkScheme);
}
