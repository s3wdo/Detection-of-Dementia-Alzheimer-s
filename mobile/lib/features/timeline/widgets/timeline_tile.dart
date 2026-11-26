import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/source_style.dart';
import '../data/models/timeline_event.dart';

IconData timelineIcon(TimelineKind kind) => switch (kind) {
      TimelineKind.mriAnalysis => Icons.filter_center_focus_rounded,
      TimelineKind.doctorReview => Icons.medical_services_outlined,
      TimelineKind.appointment => Icons.calendar_today_outlined,
      TimelineKind.message => Icons.mail_outline_rounded,
    };

/// One row of the vertical timeline: date, a small node on the line coloured by
/// source, then title, detail and time as plain text.
class TimelineTile extends StatelessWidget {
  const TimelineTile({super.key, required this.event, required this.isLast});

  final TimelineEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final style = sourceStyle(event.source);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 52,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(Fmt.shortDate(event.at),
                  style:
                      AppTextStyles.mono.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.muted)),
            ),
          ),
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(timelineIcon(event.kind), size: 18, color: style.color),
                ),
                if (!isLast)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                      child: Container(width: 1.5, color: AppColors.border),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(event.title, style: AppTextStyles.label.copyWith(fontSize: 16))),
                      const SizedBox(width: AppSpacing.sm),
                      SourceTag(event.source),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(event.detail, style: AppTextStyles.bodySmall),
                  Text(Fmt.time(event.at), style: AppTextStyles.caption),
                  if (event.pending) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const StatusBadge(StatusKind.pendingReview),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
