import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/disclaimer_banner.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../data/models/analysis.dart';
import '../diagnosis_providers.dart';
import '../widgets/result_widgets.dart';

/// A released result, as the patient sees it: the doctor's decision first,
/// then the AI output that informed it, clearly labelled.
class PatientDiagnosisScreen extends ConsumerWidget {
  const PatientDiagnosisScreen({super.key, required this.analysisId});

  final String analysisId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (analysisId: analysisId, patientView: true);
    final analysis = ref.watch(analysisProvider(args));
    return Scaffold(
      appBar: AppBar(
        title:
            PageTitle('My MRI Result', subtitle: analysis.value == null ? null : Fmt.date(analysis.value!.createdAt)),
      ),
      body: AsyncValueView<AnalysisSummary>(
        value: analysis,
        onRetry: () => ref.invalidate(analysisProvider(args)),
        data: (a) => ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xxl),
          children: [
            if (a.simulated) ...[const SimulatedResultBanner(), const SizedBox(height: AppSpacing.lg)],
            DoctorReviewSection(analysis: a, forPatient: true),
            const SizedBox(height: AppSpacing.xl),
            const Divider(),
            const SizedBox(height: AppSpacing.xl),
            AiResultSection(analysis: a, showBars: false, showConfidence: false),
            const SizedBox(height: AppSpacing.lg),
            const DisclaimerBanner(
              text: 'This analysis was produced with the help of an AI model and reviewed by your doctor. '
                  'It is not a diagnosis on its own. Talk to your doctor about what it means for you.',
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'View report',
              icon: Icons.description_outlined,
              onPressed: () => context.push('/patient/reports/$analysisId'),
            ),
            const SizedBox(height: AppSpacing.lg),
            RowGroup(children: [
              ListRowTile(
                icon: Icons.layers_outlined,
                title: 'About the explainability map',
                onTap: () => context.push(Routes.patientResultExplainability(analysisId)),
              ),
              ListRowTile(
                icon: Icons.menu_book_outlined,
                title: 'Understand this result',
                subtitle: 'Educational answers, not medical advice',
                onTap: () => context
                    .push('/patient/counselling/chat?ask=${Uri.encodeComponent('What does my latest MRI result mean?')}'),
              ),
              ListRowTile(
                icon: Icons.mail_outline_rounded,
                title: 'Message my doctor',
                onTap: () => context.push(Routes.patientMessages),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
