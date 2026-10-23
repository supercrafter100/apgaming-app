import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colors taken from the web platform so the app feels like the same product.
abstract final class HubColors {
  static const background = Color(0xFF020618);
  static const surface = Color(0xFF0A0F25);
  static const surfaceRaised = Color(0xFF0F1633);
  static const red = Color(0xFFD42422);
  static const border = Color(0x1AFFFFFF);
  static const textSecondary = Color(0xFF9CA3AF);
  static const textMuted = Color(0xFF6B7280);

  static const blue = Color(0xFF93C5FD);
  static const green = Color(0xFF86EFAC);
  static const yellow = Color(0xFFFDE047);
  static const orange = Color(0xFFFDBA74);
  static const danger = Color(0xFFFCA5A5);
}

ThemeData buildHubTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: HubColors.red, brightness: Brightness.dark).copyWith(
    primary: HubColors.red,
    onPrimary: Colors.white,
    secondary: HubColors.red,
    surface: HubColors.background,
    onSurface: Colors.white,
    onSurfaceVariant: HubColors.textSecondary,
    surfaceContainerLowest: HubColors.background,
    surfaceContainerLow: HubColors.surface,
    surfaceContainer: HubColors.surface,
    surfaceContainerHigh: HubColors.surfaceRaised,
    surfaceContainerHighest: HubColors.surfaceRaised,
    outline: const Color(0x33FFFFFF),
    outlineVariant: HubColors.border,
    error: HubColors.danger,
  );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: Brightness.dark);
  final textTheme = GoogleFonts.interTextTheme(base.textTheme)
      .apply(bodyColor: Colors.white, displayColor: Colors.white);

  final roundedBorder = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));

  // Native navigation feel: iOS-style slide (with swipe back) on iOS, Android 14 style on Android.
  // Desktop only exists for quick previews, so it mimics iOS.
  const pageTransitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
    },
  );
  final isIos = defaultTargetPlatform == TargetPlatform.iOS;

  return base.copyWith(
    pageTransitionsTheme: pageTransitions,
    // iOS has no ink ripples; pressed states come from Pressable instead.
    splashFactory: isIos ? NoSplash.splashFactory : base.splashFactory,
    highlightColor: isIos ? Colors.transparent : base.highlightColor,
    scaffoldBackgroundColor: HubColors.background,
    textTheme: textTheme.copyWith(
      headlineMedium: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: HubColors.background,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: HubColors.surface,
      indicatorColor: HubColors.red,
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) =>
            IconThemeData(color: states.contains(WidgetState.selected) ? Colors.white : HubColors.textSecondary),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => textTheme.labelMedium?.copyWith(
          color: states.contains(WidgetState.selected) ? Colors.white : HubColors.textSecondary,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: HubColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: HubColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: roundedBorder,
        textStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: roundedBorder,
        foregroundColor: Colors.white,
        side: const BorderSide(color: HubColors.border),
        textStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: HubColors.red,
      foregroundColor: Colors.white,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: HubColors.surface,
        foregroundColor: HubColors.textSecondary,
        selectedBackgroundColor: HubColors.red,
        selectedForegroundColor: Colors.white,
        side: const BorderSide(color: HubColors.border),
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: HubColors.surface,
      selectedColor: HubColors.red,
      side: const BorderSide(color: HubColors.border),
      labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      secondaryLabelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, color: Colors.white),
      checkmarkColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: HubColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: HubColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: HubColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: HubColors.red, width: 1.5),
      ),
      labelStyle: const TextStyle(color: HubColors.textSecondary),
      hintStyle: const TextStyle(color: HubColors.textMuted),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: HubColors.surface,
      modalBarrierColor: Color(0x99000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        side: BorderSide(color: HubColors.border),
      ),
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: Color(0x4DFFFFFF),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: HubColors.surfaceRaised, surfaceTintColor: Colors.transparent),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: HubColors.surfaceRaised,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: HubColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: HubColors.border, space: 1),
    listTileTheme: const ListTileThemeData(iconColor: HubColors.textSecondary),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: HubColors.red, linearTrackColor: Color(0x0DFFFFFF)),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : HubColors.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? HubColors.red : HubColors.surfaceRaised,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? HubColors.red : Colors.transparent,
      ),
      side: const BorderSide(color: HubColors.textMuted, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
  );
}
