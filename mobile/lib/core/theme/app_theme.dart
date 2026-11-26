import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';

/// Material 3 theme built from the design tokens.
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    surface: AppColors.surface,
    error: AppColors.error,
  );

  OutlineInputBorder border(Color c, [double w = 1.5]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.input),
        borderSide: BorderSide(color: c, width: w),
      );

  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.button));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: AppTextStyles.fontFamily,
    scaffoldBackgroundColor: AppColors.background,
    textTheme: const TextTheme(
      headlineMedium: AppTextStyles.display,
      titleLarge: AppTextStyles.title,
      titleMedium: AppTextStyles.headline,
      bodyLarge: AppTextStyles.body,
      bodyMedium: AppTextStyles.bodySmall,
      labelLarge: AppTextStyles.label,
      bodySmall: AppTextStyles.caption,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.navy,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 72,
      titleSpacing: AppSpacing.screen,
      titleTextStyle: AppTextStyles.screenTitle,
      iconTheme: IconThemeData(color: AppColors.navy, size: 26),
      actionsIconTheme: IconThemeData(color: AppColors.navy, size: 26),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: AppTextStyles.button,
        shape: buttonShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryDark,
        backgroundColor: AppColors.surface,
        minimumSize: const Size.fromHeight(54),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: AppTextStyles.button,
        side: const BorderSide(color: AppColors.primary, width: 1.5),
        shape: buttonShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size(AppSpacing.minTouch, AppSpacing.minTouch),
        textStyle: AppTextStyles.label,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(AppSpacing.minTouch, AppSpacing.minTouch)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: AppTextStyles.body.copyWith(color: AppColors.muted),
      labelStyle: AppTextStyles.body.copyWith(color: AppColors.muted),
      border: border(AppColors.borderStrong),
      enabledBorder: border(AppColors.borderStrong),
      focusedBorder: border(AppColors.primary, 1.8),
      errorBorder: border(AppColors.error),
      focusedErrorBorder: border(AppColors.error, 1.8),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.navy,
      checkmarkColor: Colors.white,
      showCheckmark: false,
      labelStyle: AppTextStyles.label.copyWith(color: AppColors.ink),
      secondaryLabelStyle: AppTextStyles.label.copyWith(color: Colors.white),
      side: const BorderSide(color: AppColors.borderStrong, width: 1.3),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
        textStyle: const WidgetStatePropertyAll(AppTextStyles.label),
        foregroundColor:
            WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.navy : AppColors.muted),
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.surface : AppColors.surfaceAlt),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.surfaceAlt, width: 4)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.button))),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.navy,
      unselectedLabelColor: AppColors.muted,
      labelStyle: AppTextStyles.label,
      unselectedLabelStyle: AppTextStyles.label,
      indicatorColor: AppColors.primary,
      dividerColor: AppColors.border,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.primaryTint,
      height: 76,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => AppTextStyles.caption.copyWith(
            fontSize: 13,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.muted,
          )),
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.muted)),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.success : AppColors.borderStrong),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.primary,
      inactiveTrackColor: AppColors.surfaceAlt,
      thumbColor: AppColors.primary,
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: AppColors.primary, linearTrackColor: AppColors.surfaceAlt),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: AppTextStyles.title,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: AppColors.navy),
  );
}
