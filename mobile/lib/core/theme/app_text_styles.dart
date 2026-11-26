import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Type scale: IBM Plex Sans for all UI text, IBM Plex Mono for MRNs, IDs and
/// model metrics. Source Serif 4 stays bundled for the brand wordmark only.
abstract final class AppTextStyles {
  static const fontFamily = 'IBMPlexSans';
  static const serif = 'SourceSerif4';
  static const monoFamily = 'IBMPlexMono';

  /// Greeting and the most important value on a screen.
  static const display =
      TextStyle(fontFamily: fontFamily, fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.navy, height: 1.2, letterSpacing: -0.4);

  /// Key values, e.g. a predicted class or a person's name.
  static const title =
      TextStyle(fontFamily: fontFamily, fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.navy, height: 1.25, letterSpacing: -0.2);

  /// Screen titles in the app bar.
  static const screenTitle =
      TextStyle(fontFamily: fontFamily, fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.navy, height: 1.2, letterSpacing: -0.2);

  /// Section and card headings.
  static const headline =
      TextStyle(fontFamily: fontFamily, fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.ink, height: 1.3);
  static const body =
      TextStyle(fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.body, height: 1.5);
  static const bodySmall =
      TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.body, height: 1.45);
  static const label =
      TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink);
  static const caption =
      TextStyle(fontFamily: fontFamily, fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.muted, height: 1.4);

  /// Small spaced capitals, e.g. "ALL MODEL CLASSES".
  static const overline = TextStyle(
      fontFamily: fontFamily, fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted, letterSpacing: 1.3);
  static const button = TextStyle(fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w700);

  /// Numbers, percentages, IDs and file names.
  static const mono =
      TextStyle(fontFamily: monoFamily, fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.ink);
}
