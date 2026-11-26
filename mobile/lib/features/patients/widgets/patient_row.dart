import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../diagnosis/widgets/analysis_widgets.dart';
import '../data/models/patient.dart';

/// One patient in the doctor's list: name, MRN, latest AI result and its review state.
class PatientRow extends StatelessWidget {
  const PatientRow({super.key, required this.patient, required this.now, required this.onTap});

  final Patient patient;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final latest = patient.latestAnalysis;
    final quiet = AppTextStyles.caption.copyWith(fontSize: 14);
    return GroupRow(
      onTap: onTap,
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppAvatar(name: patient.fullName, size: 40),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(patient.fullName, style: AppTextStyles.label.copyWith(fontSize: 16)),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: patient.mrn, style: AppTextStyles.mono.copyWith(fontSize: 13, color: AppColors.muted)),
                      TextSpan(
                        text: latest == null
                            ? ' · ${Fmt.age(patient.dateOfBirth, now)} yrs · ${patient.sex.label}'
                            : ' · ${Fmt.date(latest.createdAt)}',
                      ),
                    ]),
                    style: quiet,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    latest == null
                        ? 'No analyses yet'
                        : 'AI: ${latest.predicted.label} · ${Fmt.percent(latest.confidence)}',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.ink),
                  ),
                  if (latest != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    AnalysisStatusBadge(latest),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
      ),
    );
  }
}
