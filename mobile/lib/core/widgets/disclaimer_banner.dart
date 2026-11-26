import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Shown wherever an AI result appears.
class DisclaimerBanner extends StatelessWidget {
  const DisclaimerBanner({super.key, this.text = defaultText});

  static const defaultText =
      'AI-assisted result, not a medical diagnosis. It must be reviewed by a qualified healthcare professional.';

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.info_outline_rounded, size: 18, color: AppColors.muted),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: AppTextStyles.bodySmall)),
      ],
    );
  }
}
