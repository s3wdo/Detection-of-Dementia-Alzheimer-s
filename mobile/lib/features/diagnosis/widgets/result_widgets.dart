import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../data/models/analysis.dart';
import '../data/models/model_class.dart';
import '../diagnosis_providers.dart';

/// Slim amber notice shown on every result produced without the real AI model.
class SimulatedResultBanner extends StatelessWidget {
  const SimulatedResultBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
      decoration: const BoxDecoration(
        color: AppColors.devTint,
        border: Border(left: BorderSide(color: AppColors.dev, width: 3)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              'SIMULATED RESULT — the AI model is not connected yet. These values are demo data, '
              'not a real model output.',
              style: TextStyle(fontSize: 12, color: AppColors.body, height: 1.35, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// One bar per model class (design screen 6 shows the predicted class; the
/// plan asks for all four so the doctor sees the full model output).
class ProbabilityBars extends StatelessWidget {
  const ProbabilityBars({super.key, required this.probabilities, required this.predicted});

  final Map<ModelClass, double> probabilities;
  final ModelClass predicted;

  @override
  Widget build(BuildContext context) {
    if (probabilities.isEmpty) {
      return const Text('Class scores are not available for this analysis.', style: AppTextStyles.caption);
    }
    return Column(
      children: [
        for (final c in ModelClass.values)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Semantics(
              label: '${c.label}: ${Fmt.percent(probabilities[c] ?? 0)}',
              excludeSemantics: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      c.label,
                      style: c == predicted
                          ? AppTextStyles.label.copyWith(fontSize: 16)
                          : AppTextStyles.body.copyWith(color: AppColors.body),
                    ),
                  ),
                  Text(Fmt.percent(probabilities[c] ?? 0),
                      style: AppTextStyles.mono
                          .copyWith(fontSize: 15, fontWeight: c == predicted ? FontWeight.w600 : FontWeight.w400)),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: probabilities[c] ?? 0,
                    minHeight: 9,
                    backgroundColor: AppColors.surfaceAlt,
                    color: c == predicted ? AppColors.primary : const Color(0xFF8D96A6),
                  ),
                ),
              ]),
            ),
          ),
      ],
    );
  }
}

/// The AI part of a result, laid out as a section (no card): source label,
/// predicted class, model confidence, all class scores and the model version.
/// The patient's copy sets [showConfidence] and [showBars] to false.
class AiResultSection extends StatelessWidget {
  const AiResultSection({super.key, required this.analysis, this.showBars = true, this.showConfidence = true});

  final AnalysisSummary analysis;
  final bool showBars;
  final bool showConfidence;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SourceBadge(InfoSource.ai),
        const SizedBox(height: AppSpacing.md),
        const Text('Predicted class', style: AppTextStyles.caption),
        Text(a.predicted.label, style: AppTextStyles.title),
        if (showConfidence) ...[
          const SizedBox(height: AppSpacing.md),
          const Text('Model confidence', style: AppTextStyles.caption),
          Text(Fmt.percent(a.confidence),
              style: AppTextStyles.mono.copyWith(fontSize: 22, fontWeight: FontWeight.w600, height: 1.3)),
          const Text('Softmax score, not a calibrated medical probability.', style: AppTextStyles.caption),
        ],
        if (showBars) ...[
          const SizedBox(height: AppSpacing.lg),
          const Overline('All model classes'),
          const SizedBox(height: AppSpacing.md),
          ProbabilityBars(probabilities: a.probabilities, predicted: a.predicted),
        ] else
          const SizedBox(height: AppSpacing.md),
        // Full MRI scan: the scores above are an average over several slices.
        if (showConfidence && a.volume != null) ...[
          Text(
            key: const Key('volumeSummary'),
            'Full MRI scan · scores averaged over ${a.volume!.slicesUsed} slices '
            '(${a.volume!.slicesKept} of ${a.volume!.slicesTotal} accepted by the brain detector, '
            'top ${a.volume!.slicesKept - a.volume!.slicesUsed} left out). Image shown: axial slice ${a.volume!.sliceIndex + 1}.',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        // The patient's copy leaves out the model name and version; the report still has them.
        if (showConfidence)
          Text(
            '${a.modelName} · ${a.modelVersion}${a.simulated ? ' (placeholder)' : ''} · ${Fmt.dateTime(a.createdAt)}',
            style: AppTextStyles.mono.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.muted),
          )
        else
          Text('Analysed ${Fmt.dateTime(a.createdAt)}${a.simulated ? ' (placeholder)' : ''}',
              style: AppTextStyles.caption),
      ],
    );
  }
}

/// Small square for an MRI image. Shows the real image when there is one;
/// otherwise a neutral brain icon (never a fake scan).
class MriThumbnail extends StatelessWidget {
  const MriThumbnail({super.key, this.size = 72, this.image});

  final double size;
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: image == null ? 'MRI image not available' : 'MRI image',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF0B0D10),
          borderRadius: BorderRadius.circular(14),
          image: image == null ? null : DecorationImage(image: image!, fit: BoxFit.cover),
        ),
        child: image == null ? Icon(Icons.psychology_outlined, color: const Color(0xFF8D96A6), size: size * 0.5) : null,
      ),
    );
  }
}

/// The stored MRI image of [analysisId] as a thumbnail. Shows the placeholder
/// while loading, or when the server no longer keeps the image.
class AnalysisThumbnail extends ConsumerWidget {
  const AnalysisThumbnail({super.key, required this.analysisId, this.size = 72});

  final String analysisId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(analysisImageProvider(analysisId)).value;
    return MriThumbnail(size: size, image: bytes == null ? null : MemoryImage(bytes));
  }
}

/// "Model Confidence 91.4%" with the number in mono, as in the design.
class ConfidenceText extends StatelessWidget {
  const ConfidenceText(this.confidence, {super.key, this.suffix});

  final double confidence;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(style: AppTextStyles.bodySmall.copyWith(fontSize: 15), children: [
        const TextSpan(text: 'Model Confidence '),
        TextSpan(
          text: Fmt.percent(confidence),
          style: AppTextStyles.mono.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        if (suffix != null) TextSpan(text: suffix),
      ]),
    );
  }
}

/// The doctor's decision, kept visually separate from the AI output by a green
/// rule and the doctor source label. Patients see the patient summary; doctors
/// also see clinical notes and the override reason.
class DoctorReviewSection extends StatelessWidget {
  const DoctorReviewSection({super.key, required this.analysis, required this.forPatient});

  final AnalysisSummary analysis;
  final bool forPatient;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    final overridden = a.status == ReviewStatus.overridden;
    return Container(
      padding: const EdgeInsets.only(left: AppSpacing.lg),
      decoration: const BoxDecoration(border: Border(left: BorderSide(color: AppColors.doctor, width: 3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SourceBadge(InfoSource.doctor, doctorName: a.reviewedBy),
          const SizedBox(height: AppSpacing.md),
          Text(forPatient ? "Your doctor's classification" : 'Final classification', style: AppTextStyles.caption),
          Text((a.finalClass ?? a.predicted).label, style: AppTextStyles.title),
          const SizedBox(height: 2),
          Text(
            overridden ? 'The doctor changed the AI classification.' : 'The doctor confirmed the AI classification.',
            style: AppTextStyles.bodySmall,
          ),
          if (a.reviewedAt != null) Text('Reviewed ${Fmt.dateTime(a.reviewedAt!)}', style: AppTextStyles.caption),
          if (!forPatient && overridden && a.overrideReason != null) ...[
            const SizedBox(height: AppSpacing.md),
            const Text('Reason for override', style: AppTextStyles.caption),
            Text(a.overrideReason!, style: AppTextStyles.bodySmall),
          ],
          if (!forPatient && a.clinicalNotes != null) ...[
            const SizedBox(height: AppSpacing.md),
            const Row(children: [
              Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.admin),
              SizedBox(width: 4),
              Text('Clinical notes · clinicians only', style: AppTextStyles.caption),
            ]),
            Text(a.clinicalNotes!, style: AppTextStyles.bodySmall),
          ],
          if (a.patientSummary != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(forPatient ? 'Message from your doctor' : 'Summary for the patient', style: AppTextStyles.caption),
            Text(a.patientSummary!, style: AppTextStyles.body),
          ],
          if (!forPatient) ...[
            const SizedBox(height: AppSpacing.md),
            a.released
                ? const StatusBadge(StatusKind.released)
                : const Text('Not yet released to the patient.', style: AppTextStyles.caption),
          ],
        ],
      ),
    );
  }
}
