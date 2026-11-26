import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../../timeline/screens/timeline_screen.dart';
import '../data/models/analysis.dart';
import '../diagnosis_providers.dart';

/// Patient History tab: released results and the timeline.
class PatientHistoryScreen extends ConsumerWidget {
  const PatientHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientId = ref.watch(sessionControllerProvider)?.patientId;
    if (patientId == null) return const SizedBox.shrink();
    final args = (patientId: patientId, patientView: true);
    final results = ref.watch(analysesProvider(args));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My History'),
          bottom: const PillTabBar(labels: ['Results', 'Timeline']),
        ),
        body: TabBarView(children: [
          AsyncValueView<List<AnalysisSummary>>(
            value: results,
            onRetry: () => ref.invalidate(analysesProvider(args)),
            isEmpty: (l) => l.isEmpty,
            empty: const EmptyState(
              icon: Icons.document_scanner_outlined,
              title: 'No reviewed results yet',
              message: 'Results appear here after your doctor has reviewed and released them.',
            ),
            data: (list) => ListView(
              padding: const EdgeInsets.all(AppSpacing.screen),
              children: [
                RowGroup(children: [
                  for (final a in list)
                    GroupRow(
                      onTap: () => context.push(Routes.patientResult(a.id)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(Fmt.date(a.createdAt),
                                style:
                                    AppTextStyles.mono.copyWith(color: AppColors.muted, fontWeight: FontWeight.w400)),
                            const SizedBox(height: 2),
                            Text((a.finalClass ?? a.predicted).label,
                                style: AppTextStyles.headline.copyWith(fontSize: 19)),
                            const SizedBox(height: AppSpacing.sm),
                            SourceBadge(InfoSource.doctor, doctorName: a.reviewedBy),
                          ]),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                      ]),
                    ),
                ]),
                const SizedBox(height: AppSpacing.lg),
                if (list.length >= 2)
                  AppButton(
                    label: 'Compare results',
                    icon: Icons.compare_arrows_rounded,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => context.push('/patient/compare'),
                  ),
                const SizedBox(height: AppSpacing.md),
                const InfoNote(
                    'Historical AI results. Differences between analyses need to be interpreted by your doctor.'),
                const SizedBox(height: AppSpacing.sm),
                AppButton(
                  label: 'My reports',
                  icon: Icons.description_outlined,
                  variant: AppButtonVariant.text,
                  onPressed: () => context.push(Routes.patientReports),
                ),
              ],
            ),
          ),
          const TimelineBody(patientId: null, patientView: true),
        ]),
      ),
    );
  }
}
