import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/repository_providers.dart';
import '../../../core/data/user_facing_error.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/disclaimer_banner.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../../patients/patients_providers.dart';
import '../data/models/analysis.dart';
import '../diagnosis_providers.dart';
import '../widgets/analysis_widgets.dart';
import '../../reports/services/report_pdf.dart';
import '../widgets/result_widgets.dart';

/// Analysis result for the doctor, laid out as a review workspace: whose scan,
/// what the model predicted and how confident it was, the review state, and
/// one primary next step.
class DiagnosisResultScreen extends ConsumerWidget {
  const DiagnosisResultScreen({super.key, required this.patientId, required this.analysisId});

  final String patientId;
  final String analysisId;

  Future<void> _release(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Release to patient?',
      message: 'The patient will see the final classification and your summary. Clinical notes stay private.',
      confirmLabel: 'Release',
    );
    if (!ok) return;
    try {
      await ref.read(reviewsRepositoryProvider).releaseToPatient(analysisId);
      refreshClinicalData(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Result released to the patient.')));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(userMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (analysisId: analysisId, patientView: false);
    final analysis = ref.watch(analysisProvider(args));
    final patient = ref.watch(patientProvider(patientId)).value;
    final report = '${Routes.doctorAnalysis(patientId, analysisId)}/report';

    return Scaffold(
      appBar: AppBar(title: const Text('Analysis Result')),
      body: AsyncValueView<AnalysisSummary>(
        value: analysis,
        onRetry: () => ref.invalidate(analysisProvider(args)),
        data: (a) {
          final reviewed = a.status.isReviewed;
          final Widget primary = !reviewed
              ? AppButton(
                  key: const Key('reviewButton'),
                  label: 'Doctor Review',
                  icon: Icons.rate_review_outlined,
                  onPressed: () => context.push(Routes.doctorReview(patientId, analysisId)),
                )
              : !a.released
                  ? AppButton(
                      key: const Key('releaseButton'),
                      label: 'Release to patient',
                      icon: Icons.visibility_outlined,
                      variant: AppButtonVariant.success,
                      onPressed: () => _release(context, ref),
                    )
                  : AppButton(
                      label: 'View report',
                      icon: Icons.description_outlined,
                      onPressed: () => context.push(report),
                    );
          return ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xxl),
            children: [
              if (a.simulated) ...[const SimulatedResultBanner(), const SizedBox(height: AppSpacing.xl)],
              const Overline('Patient'),
              const SizedBox(height: AppSpacing.xs),
              Text(patient?.fullName ?? '…', style: AppTextStyles.headline.copyWith(fontSize: 20)),
              if (patient != null)
                Text(patient.mrn, style: AppTextStyles.mono.copyWith(color: AppColors.muted, fontWeight: FontWeight.w400)),
              const SizedBox(height: AppSpacing.lg),
              const Overline('Analysis'),
              const SizedBox(height: AppSpacing.xs),
              Text('MRI analysed ${Fmt.dateTime(a.createdAt)}', style: AppTextStyles.body.copyWith(color: AppColors.ink)),
              const SizedBox(height: AppSpacing.xl),
              const Divider(),
              const SizedBox(height: AppSpacing.xl),
              AiResultSection(analysis: a),
              const SizedBox(height: AppSpacing.xl),
              const Divider(),
              const SizedBox(height: AppSpacing.xl),
              Row(children: [
                const Expanded(child: Overline('Doctor review')),
                Flexible(child: AnalysisStatusBadge(a)),
              ]),
              const SizedBox(height: AppSpacing.md),
              if (reviewed)
                DoctorReviewSection(analysis: a, forPatient: false)
              else
                Text(
                  a.status == ReviewStatus.pendingReview
                      ? 'Model confidence is below 0.80. Review this result carefully before any decision.'
                      : 'Waiting for your confirmation or override.',
                  style: AppTextStyles.bodySmall,
                ),
              const SizedBox(height: AppSpacing.xl),
              const DisclaimerBanner(
                text: 'This is an AI-assisted classification and should be reviewed by a qualified healthcare '
                    'professional.',
              ),
              const SizedBox(height: AppSpacing.xl),
              primary,
              const SizedBox(height: AppSpacing.lg),
              RowGroup(children: [
                ListRowTile(
                  icon: Icons.layers_outlined,
                  title: 'Explainability',
                  subtitle: "What influenced the model's output",
                  onTap: () => context.push(Routes.doctorExplainability(patientId, analysisId)),
                ),
                ListRowTile(
                  icon: Icons.compare_arrows_rounded,
                  title: 'Compare analyses',
                  onTap: () => context.push('/doctor/patients/$patientId/compare'),
                ),
                if (reviewed && !a.released)
                  ListRowTile(
                    icon: Icons.description_outlined,
                    title: 'Report',
                    onTap: () => context.push(report),
                  ),
                if (reviewed)
                  ListRowTile(
                    icon: Icons.download_rounded,
                    title: 'Download PDF',
                    onTap: () => downloadReportPdf(context, ref, analysisId),
                  ),
                ListRowTile(
                  icon: Icons.mail_outline_rounded,
                  title: 'Message patient',
                  onTap: () => context.push('/doctor/messages/$patientId'),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }
}
