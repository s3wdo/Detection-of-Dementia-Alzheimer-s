import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../../core/widgets/neuro_logo.dart';
import '../../../core/widgets/state_views.dart';
import '../../diagnosis/data/models/analysis.dart';
import '../../diagnosis/diagnosis_providers.dart';
import '../../diagnosis/widgets/result_widgets.dart';
import '../../patients/patients_providers.dart';
import '../services/report_pdf.dart';

/// AI Analysis Report (design section 16), laid out as a printable page.
/// AI-generated and doctor-reviewed information are separate, labelled sections.
/// The PDF itself will be produced by the backend (GET /analyses/{aid}/report.pdf).
class ReportScreen extends ConsumerWidget {
  const ReportScreen({super.key, required this.analysisId, required this.forPatient, this.patientId});

  final String analysisId;
  final bool forPatient;

  /// Needed for the doctor version (patient details); patients use their session.
  final String? patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (analysisId: analysisId, patientView: forPatient);
    final analysis = ref.watch(analysisProvider(args));
    final session = ref.watch(sessionControllerProvider);
    final patient = patientId == null ? null : ref.watch(patientProvider(patientId!)).value;
    final now = ref.watch(clockProvider)();
    final name = forPatient ? session?.fullName : patient?.fullName;
    final number = forPatient ? session?.subtitle.replaceFirst('Patient ID ', '') : patient?.mrn;
    final messages = forPatient ? Routes.patientMessages : '/doctor/messages/$patientId';

    return Scaffold(
      backgroundColor: AppColors.surfaceAlt,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceAlt,
        title: PageTitle('Report', subtitle: forPatient ? 'Your copy' : 'Doctor version'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More actions',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (v) => v == 'pdf' ? downloadReportPdf(context, ref, analysisId) : context.push(v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'pdf', child: Text('Download PDF')),
              PopupMenuItem(value: messages, child: Text(forPatient ? 'Ask my doctor about it' : 'Message patient')),
            ],
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: AsyncValueView<AnalysisSummary>(
        value: analysis,
        onRetry: () => ref.invalidate(analysisProvider(args)),
        data: (a) {
          if (!a.status.isReviewed) {
            return const EmptyState(
              icon: Icons.description_outlined,
              title: 'No report yet',
              message: 'A report is available after the doctor has reviewed the result.',
            );
          }
          final overridden = a.status == ReviewStatus.overridden;
          return ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xxl),
            children: [
              if (a.simulated) ...[const SimulatedResultBanner(), const SizedBox(height: AppSpacing.md)],
              Container(
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    NeuroLogo(size: 40),
                    SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('NeuroSense', style: AppTextStyles.title),
                        Text('AI-Assisted MRI Analysis Report', style: AppTextStyles.bodySmall),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: AppSpacing.lg),
                  Container(height: 2, color: AppColors.navy),
                  const SizedBox(height: AppSpacing.lg),
                  _Grid(cells: [
                    ('Patient', name ?? '—', false),
                    ('Patient ID', number ?? '—', true),
                    ('Analysis Date', Fmt.date(a.createdAt), false),
                    ('Report ID', 'NSR-${a.id.toUpperCase()}', true),
                  ]),
                  const SizedBox(height: AppSpacing.lg),
                  const _Band(
                    icon: Icons.filter_center_focus_rounded,
                    title: 'AI-GENERATED INFORMATION',
                    color: AppColors.ai,
                    tint: AppColors.aiTint,
                  ),
                  const _Heading('MRI Information'),
                  Text('Axial brain MRI slice (JPG/PNG) · uploaded ${Fmt.dateTime(a.createdAt)}',
                      style: AppTextStyles.body.copyWith(color: AppColors.ink)),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const _Heading('AI Model Prediction'),
                        Text(a.predicted.label, style: AppTextStyles.title),
                        if (!forPatient) ...[
                          const _Heading('Model Confidence'),
                          Text(Fmt.percent(a.confidence),
                              style: AppTextStyles.mono.copyWith(fontSize: 20, fontWeight: FontWeight.w600)),
                          const Text('Softmax score, not a calibrated probability', style: AppTextStyles.caption),
                        ],
                      ]),
                    ),
                    Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.lg),
                        child: AnalysisThumbnail(analysisId: a.id, size: 96)),
                  ]),
                  if (!forPatient) ...[
                    const SizedBox(height: AppSpacing.md),
                    ProbabilityBars(probabilities: a.probabilities, predicted: a.predicted),
                  ],
                  const _Heading('Model'),
                  Text('${a.modelName} ${a.modelVersion}${a.simulated ? ' (placeholder)' : ''}',
                      style: AppTextStyles.mono.copyWith(fontWeight: FontWeight.w400)),
                  const _Heading('Explainability'),
                  Text(
                    'Grad-CAM heatmap for the predicted class, when the server made one (see Explainability). '
                    'Highlighted regions show where the model focused, not medically proven causes.',
                    style: AppTextStyles.body.copyWith(color: AppColors.ink),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const _Band(
                    icon: Icons.medical_services_outlined,
                    title: 'DOCTOR-REVIEWED INFORMATION',
                    color: AppColors.doctor,
                    tint: AppColors.doctorTint,
                  ),
                  const _Heading('Doctor Review'),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: overridden ? 'AI result overridden' : 'Confirmed AI result',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: ' · ${a.reviewedBy ?? '—'}'
                            '${a.reviewedAt == null ? '' : ' · ${Fmt.dateTime(a.reviewedAt!)}'}',
                      ),
                    ]),
                    style: AppTextStyles.body.copyWith(color: AppColors.ink),
                  ),
                  const _Heading('Final Classification'),
                  Text((a.finalClass ?? a.predicted).label, style: AppTextStyles.label.copyWith(fontSize: 16)),
                  if (!forPatient && a.overrideReason != null) ...[
                    const _Heading('Reason for Override'),
                    Text(a.overrideReason!, style: AppTextStyles.body.copyWith(color: AppColors.ink)),
                  ],
                  if (!forPatient && a.clinicalNotes != null) ...[
                    const _Heading('Clinical notes'),
                    Text(a.clinicalNotes!, style: AppTextStyles.body.copyWith(color: AppColors.ink)),
                  ],
                  if (a.patientSummary != null) ...[
                    const _Heading('Patient summary'),
                    Text(a.patientSummary!, style: AppTextStyles.body.copyWith(color: AppColors.ink)),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration:
                        BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadii.tile)),
                    child: Text.rich(
                      const TextSpan(children: [
                        TextSpan(text: 'Disclaimer. ', style: TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(
                          text: 'This report contains an AI-assisted classification produced by an academic research '
                              'system that is not a certified medical device. AI predictions are not standalone '
                              'clinical diagnoses and must be interpreted by a qualified healthcare professional.',
                        ),
                      ]),
                      style: AppTextStyles.bodySmall.copyWith(fontSize: 14.5),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(children: [
                    Expanded(
                      child: Text('Generated ${Fmt.dateTime(now)}',
                          style: AppTextStyles.mono
                              .copyWith(fontSize: 12.5, fontWeight: FontWeight.w400, color: AppColors.muted)),
                    ),
                    Text('Page 1 of 1',
                        style: AppTextStyles.mono
                            .copyWith(fontSize: 12.5, fontWeight: FontWeight.w400, color: AppColors.muted)),
                  ]),
                ]),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(children: [
                Expanded(
                    child:
                        Builder(
                      builder: (button) => AppButton(
                        key: const Key('downloadPdf'),
                        label: 'Download PDF',
                        icon: Icons.download_rounded,
                        onPressed: () => downloadReportPdf(button, ref, analysisId),
                      ),
                    )),
                const SizedBox(width: AppSpacing.md),
                Tooltip(
                  message: forPatient ? 'Send to my doctor' : 'Send to patient',
                  child: Material(
                    color: AppColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.button),
                      side: const BorderSide(color: AppColors.borderStrong, width: 1.4),
                    ),
                    child: InkWell(
                      customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.button)),
                      onTap: () => context.push(messages),
                      child: const SizedBox(width: 56, height: 54, child: Icon(Icons.send_outlined)),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: AppSpacing.md),
              Text(
                forPatient
                    ? 'This copy contains the information your doctor has released to you.'
                    : 'The patient version omits doctor-only notes.',
                style: AppTextStyles.caption,
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xs),
        child: Text(text, style: AppTextStyles.label.copyWith(color: AppColors.muted)),
      );
}

class _Grid extends StatelessWidget {
  const _Grid({required this.cells});

  /// (label, value, mono)
  final List<(String, String, bool)> cells;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => Wrap(
        runSpacing: AppSpacing.md,
        children: [
          for (final (label, value, mono) in cells)
            SizedBox(
              width: c.maxWidth > 280 ? c.maxWidth / 2 : c.maxWidth,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: AppTextStyles.caption.copyWith(fontSize: 14)),
                Text(value,
                    style: mono
                        ? AppTextStyles.mono.copyWith(fontSize: 15, fontWeight: FontWeight.w600)
                        : AppTextStyles.label.copyWith(fontSize: 16)),
              ]),
            ),
        ],
      ),
    );
  }
}

class _Band extends StatelessWidget {
  const _Band({required this.icon, required this.title, required this.color, required this.tint});

  final IconData icon;
  final String title;
  final Color color;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(AppRadii.tile)),
      child: Semantics(
        header: true,
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(title,
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13.5, letterSpacing: 1.1)),
          ),
        ]),
      ),
    );
  }
}
