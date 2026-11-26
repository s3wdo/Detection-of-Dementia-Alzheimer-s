import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/user_facing_error.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../../patients/patients_providers.dart';
import '../data/models/analysis_job.dart';
import '../diagnosis_providers.dart';
import '../widgets/result_widgets.dart';

/// Analyzing MRI (design section 08). Moves to the result when done; the doctor can
/// also leave and is notified when the analysis finishes.
class AnalysisProgressScreen extends ConsumerWidget {
  const AnalysisProgressScreen({super.key, required this.patientId, required this.analysisId});

  final String patientId;
  final String analysisId;

  void _leave(BuildContext context, WidgetRef ref) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('The analysis continues in the background. You will be notified when it is ready.'),
    ));
    context.go(Routes.doctorPatient(patientId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(analysisJobProvider(analysisId), (_, next) {
      if (next.value?.isDone ?? false) {
        refreshClinicalData(ref);
        // go() rebuilds the stack as list → profile → result, so Back returns to the profile.
        context.go(Routes.doctorAnalysis(patientId, analysisId));
      }
    });
    final job = ref.watch(analysisJobProvider(analysisId));
    final patient = ref.watch(patientProvider(patientId)).value;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: PageTitle('Analyzing MRI', subtitle: patient == null ? null : '${patient.fullName} · ${patient.mrn}'),
        actions: [
          IconButton(
            tooltip: 'Close and continue in background',
            onPressed: () => _leave(context, ref),
            icon: const Icon(Icons.close_rounded),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: job.when(
        loading: () => const LoadingState(message: 'Uploading…'),
        error: (e, _) => ErrorState(
          message: 'Analysis could not be completed. ${userMessage(e)}',
          onRetry: () => context.pop(),
        ),
        data: (j) {
          final index = AnalysisStep.visible.indexOf(j.step);
          return ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.xxl),
            children: [
              const SimulatedResultBanner(),
              const SizedBox(height: AppSpacing.xl),
              Center(child: _ProgressRing(progress: j.progress)),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration:
                      BoxDecoration(color: AppColors.navyCard, borderRadius: BorderRadius.circular(AppRadii.pill)),
                  child: Text(
                    '${(j.progress * 100).round()}%  ·  Step ${index < 0 ? AnalysisStep.visible.length : index + 1} of ${AnalysisStep.visible.length}',
                    style: AppTextStyles.mono.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppCard(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(children: [
                  for (final (i, step) in AnalysisStep.visible.indexed)
                    _StepRow(step: step, current: j.step, isLast: i == AnalysisStep.visible.length - 1),
                ]),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text('This may take a few moments.', style: AppTextStyles.body, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xs),
              const Text('You can leave this screen — you will be notified when the analysis is complete.',
                  style: AppTextStyles.caption, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                key: const Key('continueInBackground'),
                label: 'Continue in background',
                variant: AppButtonVariant.secondary,
                onPressed: () => _leave(context, ref),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).round();
    return Semantics(
      label: 'Analysis $pct percent complete',
      excludeSemantics: true,
      child: SizedBox(
        width: 190,
        height: 190,
        child: Stack(fit: StackFit.expand, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(end: progress),
            duration: const Duration(milliseconds: 500),
            builder: (_, v, __) => CircularProgressIndicator(
              value: v,
              strokeWidth: 10,
              backgroundColor: AppColors.surfaceAlt,
              color: AppColors.primary,
              strokeCap: StrokeCap.round,
            ),
          ),
          const Center(child: MriThumbnail(size: 130)),
        ]),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.current, required this.isLast});

  final AnalysisStep step;
  final AnalysisStep current;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final done = step.index < current.index;
    final active = step == current;
    final Widget node = done
        ? Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
          )
        : active
            ? Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 3),
                ),
                child: Center(
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  ),
                ),
              )
            : Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.borderStrong, width: 2),
                ),
              );
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Column(children: [
          node,
          if (!isLast) Expanded(child: Container(width: 2, color: done ? AppColors.success : AppColors.border)),
        ]),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg, top: 2),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                step.label,
                style: AppTextStyles.label.copyWith(
                  fontSize: 16,
                  color: active
                      ? AppColors.primary
                      : done
                          ? AppColors.ink
                          : AppColors.muted,
                ),
              ),
              const SizedBox(height: 2),
              Text(step.detail,
                  style:
                      AppTextStyles.mono.copyWith(fontSize: 12.5, fontWeight: FontWeight.w400, color: AppColors.muted)),
            ]),
          ),
        ),
      ]),
    );
  }
}
