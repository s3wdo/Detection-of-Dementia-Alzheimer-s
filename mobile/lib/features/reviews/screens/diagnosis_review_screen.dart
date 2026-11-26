import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/data/repository_providers.dart';
import '../../../core/data/user_facing_error.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../../diagnosis/data/models/analysis.dart';
import '../../diagnosis/data/models/model_class.dart';
import '../../diagnosis/diagnosis_providers.dart';
import '../../diagnosis/widgets/analysis_widgets.dart';
import '../../diagnosis/widgets/result_widgets.dart';
import '../../patients/patients_providers.dart';
import '../data/models/review_draft.dart';

/// Review AI Analysis (design section 12): 1 · the AI output, 2 · the doctor's own
/// decision (confirm or override), notes, patient summary and release.
class DiagnosisReviewScreen extends ConsumerWidget {
  const DiagnosisReviewScreen({super.key, required this.patientId, required this.analysisId});

  final String patientId;
  final String analysisId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (analysisId: analysisId, patientView: false);
    final analysis = ref.watch(analysisProvider(args));
    return Scaffold(
      appBar: AppBar(
        title: const PageTitle('Review AI Analysis', subtitle: 'Final decision is recorded in the audit log'),
      ),
      body: AsyncValueView<AnalysisSummary>(
        value: analysis,
        onRetry: () => ref.invalidate(analysisProvider(args)),
        data: (a) => a.status.isReviewed
            ? const EmptyState(
                icon: Icons.check_circle_outline_rounded,
                title: 'Already reviewed',
                message: 'This analysis already has a doctor review.',
              )
            : _ReviewForm(analysis: a),
      ),
    );
  }
}

class _ReviewForm extends ConsumerStatefulWidget {
  const _ReviewForm({required this.analysis});

  final AnalysisSummary analysis;

  @override
  ConsumerState<_ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends ConsumerState<_ReviewForm> {
  ReviewDecision _decision = ReviewDecision.confirm;
  ModelClass? _finalClass;
  final _reason = TextEditingController();
  final _notes = TextEditingController();
  final _summary = TextEditingController();
  bool _release = false;
  bool _saving = false;
  Map<String, String> _errors = const {};

  @override
  void dispose() {
    _reason.dispose();
    _notes.dispose();
    _summary.dispose();
    super.dispose();
  }

  ReviewDraft get _draft => ReviewDraft(
        analysisId: widget.analysis.id,
        decision: _decision,
        predicted: widget.analysis.predicted,
        finalClass: _finalClass,
        overrideReason: _reason.text,
        clinicalNotes: _notes.text,
        patientSummary: _summary.text,
        releaseToPatient: _release,
      );

  Future<void> _submit() async {
    final draft = _draft;
    final errors = draft.validate();
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;

    final ok = await showConfirmDialog(
      context,
      title: 'Submit review?',
      message: [
        'Final classification: ${draft.effectiveFinalClass.label}.',
        _release ? 'The result will be released to the patient.' : 'The result will not be shown to the patient yet.',
        'Your decision is recorded with your name and the time.',
      ].join('\n'),
      confirmLabel: 'Submit',
    );
    if (!ok || !mounted) return;

    setState(() => _saving = true);
    try {
      final doctor = ref.read(sessionControllerProvider)?.fullName ?? 'Doctor';
      await ref.read(reviewsRepositoryProvider).submitReview(draft, doctorName: doctor);
      refreshClinicalData(ref);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Review saved.')));
      context.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(userMessage(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.analysis;
    final patient = ref.watch(patientProvider(a.patientId)).value;
    final doctor = ref.watch(sessionControllerProvider)?.fullName ?? '';
    final value = AppTextStyles.label.copyWith(fontSize: 16);
    Widget cell(String label, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppTextStyles.caption.copyWith(fontSize: 14)),
          child,
        ]);

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xxl),
      children: [
        if (a.simulated) ...[const SimulatedResultBanner(), const SizedBox(height: AppSpacing.lg)],
        const Overline('1 · AI output', color: AppColors.ai),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          color: const Color(0xFFFBFAFF),
          borderColor: const Color(0xFFDCD6F5),
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
              const SourceBadge(InfoSource.ai),
              AnalysisStatusBadge(a),
            ]),
            const SizedBox(height: AppSpacing.lg),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: cell('Patient', Text(patient?.fullName ?? '…', style: value))),
              Expanded(child: cell('MRI', Text(Fmt.date(a.createdAt), style: value))),
            ]),
            const SizedBox(height: AppSpacing.md),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: cell('AI Prediction', Text(a.predicted.label, style: value))),
              Expanded(
                child: cell(
                    'Confidence', Text(Fmt.percent(a.confidence), style: AppTextStyles.mono.copyWith(fontSize: 16))),
              ),
            ]),
            const SizedBox(height: AppSpacing.md),
            Text(
              '${a.modelName} · ${a.modelVersion}${a.simulated ? ' (placeholder)' : ''}',
              style: AppTextStyles.mono.copyWith(fontSize: 12.5, fontWeight: FontWeight.w400, color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => context.push(Routes.doctorExplainability(a.patientId, a.id)),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Open full explainability'),
            ),
          ]),
        ),
        const SizedBox(height: AppSpacing.xxl),
        const Overline('2 · Your reviewed decision', color: AppColors.doctor),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          borderColor: const Color(0xFFBFE3D6),
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Not a "reviewed" badge: nothing is reviewed until the doctor submits.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  const Text('Doctor Decision', style: AppTextStyles.headline),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration:
                        BoxDecoration(color: AppColors.doctorTint, borderRadius: BorderRadius.circular(AppRadii.pill)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.medical_services_outlined, size: 16, color: AppColors.doctor),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text('Your decision · $doctor',
                            style: AppTextStyles.label.copyWith(color: AppColors.doctor, fontSize: 13.5)),
                      ),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: _DecisionCard(
                    key: const Key('decisionConfirm'),
                    icon: Icons.check_circle_outline_rounded,
                    title: 'Confirm AI Result',
                    subtitle: 'Final = AI prediction',
                    selected: _decision == ReviewDecision.confirm,
                    onTap: () => setState(() => _decision = ReviewDecision.confirm),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _DecisionCard(
                    key: const Key('decisionOverride'),
                    icon: Icons.edit_outlined,
                    title: 'Override Result',
                    subtitle: 'Set a different class',
                    selected: _decision == ReviewDecision.override,
                    onTap: () => setState(() => _decision = ReviewDecision.override),
                  ),
                ),
              ]),
              if (_decision == ReviewDecision.override) ...[
                const SizedBox(height: AppSpacing.lg),
                _label('Final Classification', 'Required', AppColors.error),
                DropdownButtonFormField<ModelClass>(
                  key: const Key('finalClass'),
                  initialValue: _finalClass,
                  isExpanded: true,
                  decoration: InputDecoration(hintText: 'Choose a class', errorText: _errors['finalClass']),
                  items: [
                    for (final c in ModelClass.values)
                      if (c != a.predicted) DropdownMenuItem(value: c, child: Text(c.label)),
                  ],
                  onChanged: (c) => setState(() => _finalClass = c),
                ),
                const SizedBox(height: AppSpacing.lg),
                _label('Reason for Override', 'Required', AppColors.error),
                _field(_reason, 'overrideReason', hint: 'Why does your assessment differ from the AI result?'),
              ],
              const SizedBox(height: AppSpacing.lg),
              _label('Clinical Notes', 'Clinicians only', AppColors.muted, icon: Icons.lock_outline_rounded),
              _field(_notes, 'clinicalNotes', hint: 'Visible to clinicians only'),
              const SizedBox(height: AppSpacing.lg),
              _label('Patient Summary', 'Shown to patient', AppColors.doctor, icon: Icons.visibility_outlined),
              _field(_summary, 'patientSummary', hint: 'Plain language. Shown if you release the result.'),
              const SizedBox(height: AppSpacing.lg),
              Material(
                color: AppColors.surfaceAlt,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.tile)),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.sm, AppSpacing.xs),
                  child: SwitchListTile(
                    key: const Key('releaseSwitch'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Release result to patient', style: AppTextStyles.label),
                    subtitle: const Text('Patient sees the final classification and summary — never clinical notes.',
                        style: AppTextStyles.caption),
                    value: _release,
                    onChanged: (v) => setState(() => _release = v),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          key: const Key('submitReview'),
          label: 'Submit Review',
          icon: Icons.check_rounded,
          variant: AppButtonVariant.success,
          loading: _saving,
          onPressed: _submit,
        ),
        const SizedBox(height: AppSpacing.md),
        const Text(
          'Submitting records your name, time and decision. The AI output is kept unchanged alongside it.',
          style: AppTextStyles.caption,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _label(String text, String hint, Color hintColor, {IconData? icon}) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(children: [
          Expanded(child: Text(text, style: AppTextStyles.label.copyWith(fontSize: 16))),
          if (icon != null) ...[Icon(icon, size: 16, color: hintColor), const SizedBox(width: 4)],
          Flexible(child: Text(hint, style: AppTextStyles.caption.copyWith(color: hintColor, fontSize: 14))),
        ]),
      );

  Widget _field(TextEditingController c, String key, {String? hint}) => TextField(
        key: Key('field_$key'),
        controller: c,
        minLines: 3,
        maxLines: 6,
        decoration: InputDecoration(hintText: hint, errorText: _errors[key], errorMaxLines: 3),
      );
}

/// One of the two large Confirm / Override choices.
class _DecisionCard extends StatelessWidget {
  const _DecisionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.doctor : AppColors.ink;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.doctorTint : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(color: selected ? AppColors.doctor : AppColors.borderStrong, width: selected ? 2.2 : 1.4),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: AppSpacing.md),
              Text(title, style: AppTextStyles.label.copyWith(fontSize: 16, color: color)),
              const SizedBox(height: 2),
              Text(subtitle, style: AppTextStyles.caption.copyWith(fontSize: 13.5)),
            ]),
          ),
        ),
      ),
    );
  }
}
