import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Amber notice marking development-only features (demo login, fictional data).
class DevModeBanner extends StatelessWidget {
  const DevModeBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.devTint,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        border: Border.all(color: const Color(0xFFF0D48A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.construction_rounded, size: 18, color: AppColors.dev),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DEVELOPMENT ONLY',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.dev, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                const SizedBox(height: 2),
                Text(message, style: AppTextStyles.caption.copyWith(color: AppColors.body)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
