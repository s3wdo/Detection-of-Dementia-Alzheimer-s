import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// primary = blue, success = green (final clinical confirmations), secondary = outlined.
enum AppButtonVariant { primary, success, secondary, text, danger }

/// The single button used across the app. Shows a spinner and ignores taps
/// while [loading] is true.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final callback = loading ? null : onPressed;
    final fg = switch (variant) {
      AppButtonVariant.primary || AppButtonVariant.success => Colors.white,
      AppButtonVariant.danger => AppColors.error,
      AppButtonVariant.secondary => AppColors.ink,
      AppButtonVariant.text => AppColors.primary,
    };
    final child = loading
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: fg, semanticsLabel: 'Loading'),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: AppSpacing.sm)],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );

    final button = switch (variant) {
      AppButtonVariant.primary => FilledButton(onPressed: callback, child: child),
      AppButtonVariant.success => FilledButton(
          onPressed: callback,
          style: FilledButton.styleFrom(backgroundColor: AppColors.success),
          child: child,
        ),
      AppButtonVariant.secondary => OutlinedButton(onPressed: callback, child: child),
      AppButtonVariant.danger => OutlinedButton(
          onPressed: callback,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: const BorderSide(color: AppColors.errorBorder, width: 1.4),
          ),
          child: child,
        ),
      AppButtonVariant.text => TextButton(onPressed: callback, child: child),
    };
    return expand && variant != AppButtonVariant.text ? SizedBox(width: double.infinity, child: button) : button;
  }
}
