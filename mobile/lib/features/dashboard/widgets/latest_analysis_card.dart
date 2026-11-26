import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/badges.dart';
import '../../diagnosis/data/models/analysis.dart';

/// The patient's latest released result: the one card on the patient home.
/// Only ever receives a result the doctor has reviewed and released.
class LatestAnalysisCard extends StatelessWidget {
  const LatestAnalysisCard({super.key, required this.analysis, required this.onView});

  final AnalysisSummary? analysis;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    if (a == null) {
      return const Text(
        'No reviewed results yet. Your results appear here after your doctor has reviewed them.',
        style: AppTextStyles.bodySmall,
      );
    }
    final overridden = a.status == ReviewStatus.overridden;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(alignment: Alignment.centerLeft, child: SourceBadge(InfoSource.ai)),
          Text('MRI analysis · ${Fmt.date(a.createdAt)}', style: AppTextStyles.caption),
          const SizedBox(height: AppSpacing.sm),
          Text(a.predicted.label, style: AppTextStyles.title),
          const SizedBox(height: AppSpacing.md),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: SourceBadge(InfoSource.doctor, doctorName: a.reviewedBy ?? 'your doctor'),
          ),
          if (overridden) ...[
            const SizedBox(height: AppSpacing.xs),
            Text("Doctor's final classification: ${a.finalClass!.label}", style: AppTextStyles.label),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppButton(label: 'View result', onPressed: onView),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'AI-assisted result, not a medical diagnosis. It has been reviewed by a qualified healthcare professional.',
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }
}
