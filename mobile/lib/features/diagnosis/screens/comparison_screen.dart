import 'package:fl_chart/fl_chart.dart';
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
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../../patients/patients_providers.dart';
import '../data/models/analysis.dart';
import '../diagnosis_providers.dart';
import '../widgets/analysis_widgets.dart';
import '../widgets/result_widgets.dart';

/// Compare Analyses (design section 14): previous vs current, side by side.
/// Wording follows the plan: these are historical AI results, not proof of progression.
class ComparisonScreen extends ConsumerStatefulWidget {
  const ComparisonScreen.doctor({super.key, required String this.patientId}) : forPatient = false;
  const ComparisonScreen.patient({super.key})
      : patientId = null,
        forPatient = true;

  final String? patientId;
  final bool forPatient;

  @override
  ConsumerState<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends ConsumerState<ComparisonScreen> {
  String? _previousId;
  String? _currentId;

  @override
  Widget build(BuildContext context) {
    final patientId = widget.patientId ?? ref.watch(sessionControllerProvider)?.patientId;
    if (patientId == null) return const SizedBox.shrink();
    final args = (patientId: patientId, patientView: widget.forPatient);
    final analyses = ref.watch(analysesProvider(args));
    final name = widget.forPatient
        ? ref.watch(sessionControllerProvider)?.fullName
        : ref.watch(patientProvider(patientId)).value?.fullName;

    return Scaffold(
      appBar: AppBar(title: PageTitle('Compare Analyses', subtitle: name)),
      body: AsyncValueView<List<AnalysisSummary>>(
        value: analyses,
        onRetry: () => ref.invalidate(analysesProvider(args)),
        data: (list) {
          if (list.length < 2) {
            return const EmptyState(
              icon: Icons.compare_arrows_rounded,
              title: 'Not enough results to compare',
              message: 'Comparison needs at least two analyses.',
            );
          }
          final current = list.firstWhere((a) => a.id == _currentId, orElse: () => list[0]);
          final previous = list.firstWhere((a) => a.id == _previousId, orElse: () => list[1]);
          final models = {previous.modelName, current.modelName};
          return ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xxl),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration:
                      BoxDecoration(color: AppColors.aiTint, borderRadius: BorderRadius.circular(AppRadii.pill)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.filter_center_focus_rounded, size: 16, color: AppColors.ai),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('HISTORICAL AI RESULTS',
                          style: AppTextStyles.label.copyWith(color: AppColors.ai, fontSize: 13.5, letterSpacing: 1.1)),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(
                      child: _Column(
                        label: 'Previous',
                        showConfidence: !widget.forPatient,
                        selected: previous,
                        options: list,
                        onChanged: (id) => setState(() => _previousId = id),
                      ),
                    ),
                    const VerticalDivider(width: AppSpacing.xl),
                    Expanded(
                      child: _Column(
                        label: 'Current',
                        showConfidence: !widget.forPatient,
                        selected: current,
                        options: list,
                        onChanged: (id) => setState(() => _currentId = id),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('How to read this comparison', style: AppTextStyles.headline),
                  const SizedBox(height: AppSpacing.md),
                  const _ReadRow('Each result is an independent AI classification of a single MRI slice.'),
                  const _ReadRow('Differences can reflect slice position, image quality or model uncertainty.'),
                  const _ReadRow('Changes in AI predictions do not by themselves establish disease progression.',
                      strong: true),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    models.length == 1 ? 'Both analyses · ${models.first}' : 'Different models: ${models.join(' / ')}',
                    style:
                        AppTextStyles.mono.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.muted),
                  ),
                ]),
              ),
              if (!widget.forPatient) ...[
                const SizedBox(height: AppSpacing.xxl),
                const SectionHeader('Model confidence per analysis'),
                const SizedBox(height: AppSpacing.sm),
                AppCard(child: _ConfidenceChart(analyses: list.reversed.toList())),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Each point is how strongly the model favoured its predicted class for that scan. It is not a '
                  'measure of disease severity.',
                  style: AppTextStyles.caption,
                ),
              ] else ...[
                const SizedBox(height: AppSpacing.xl),
                AppButton(
                  label: 'Discuss with my doctor',
                  icon: Icons.chat_bubble_outline_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => context.push(Routes.patientMessages),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ReadRow extends StatelessWidget {
  const _ReadRow(this.text, {this.strong = false});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline_rounded, size: 20, color: AppColors.muted),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: strong
                  ? AppTextStyles.label.copyWith(fontSize: 15.5)
                  : AppTextStyles.body.copyWith(color: AppColors.ink, fontSize: 15.5),
            ),
          ),
        ]),
      );
}

/// One side of the comparison: date picker, image, AI class, confidence, status.
class _Column extends StatelessWidget {
  const _Column({
    required this.label,
    required this.showConfidence,
    required this.selected,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final bool showConfidence;
  final AnalysisSummary selected;
  final List<AnalysisSummary> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final a = selected;
    final overridden = a.status.isReviewed && a.finalClass != null && a.finalClass != a.predicted;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Overline(label, color: AppColors.navy),
      DropdownButton<String>(
        value: a.id,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        style: AppTextStyles.mono.copyWith(fontWeight: FontWeight.w400, color: AppColors.muted),
        items: [for (final o in options) DropdownMenuItem(value: o.id, child: Text(Fmt.date(o.createdAt)))],
        onChanged: (id) => id == null ? null : onChanged(id),
      ),
      const SizedBox(height: AppSpacing.xs),
      AspectRatio(aspectRatio: 1, child: FittedBox(child: AnalysisThumbnail(analysisId: a.id, size: 140))),
      const SizedBox(height: AppSpacing.md),
      Text(a.predicted.label, style: AppTextStyles.label.copyWith(fontSize: 16)),
      if (showConfidence) ...[
        const SizedBox(height: AppSpacing.xs),
        const Text('Model Confidence', style: AppTextStyles.caption),
        Text(Fmt.percent(a.confidence), style: AppTextStyles.mono.copyWith(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: a.confidence,
            minHeight: 7,
            backgroundColor: AppColors.surfaceAlt,
            color: const Color(0xFF6B7A99),
          ),
        ),
      ],
      if (overridden) ...[
        const SizedBox(height: AppSpacing.sm),
        Text("Doctor's final: ${a.finalClass!.label}", style: AppTextStyles.caption.copyWith(color: AppColors.doctor)),
      ],
      const Spacer(),
      const SizedBox(height: AppSpacing.sm),
      AnalysisStatusBadge(a),
    ]);
  }
}

class _ConfidenceChart extends StatelessWidget {
  const _ConfidenceChart({required this.analyses});

  /// Oldest first.
  final List<AnalysisSummary> analyses;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Chart of model confidence for ${analyses.length} analyses',
      child: SizedBox(
        height: 180,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: 1,
            gridData: const FlGridData(drawVerticalLine: false, horizontalInterval: 0.25),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 0.25,
                  reservedSize: 36,
                  getTitlesWidget: (v, _) => Text('${(v * 100).round()}%', style: AppTextStyles.caption),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 1,
                  getTitlesWidget: (v, _) {
                    final i = v.round();
                    if (i < 0 || i >= analyses.length || v != i.toDouble()) return const SizedBox.shrink();
                    return Text(Fmt.shortDate(analyses[i].createdAt), style: AppTextStyles.caption);
                  },
                ),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [for (var i = 0; i < analyses.length; i++) FlSpot(i.toDouble(), analyses[i].confidence)],
                color: AppColors.primary,
                barWidth: 2.5,
                dotData: const FlDotData(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
