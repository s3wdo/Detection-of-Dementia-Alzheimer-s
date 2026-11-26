import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../../diagnosis/data/models/analysis.dart';
import '../../diagnosis/diagnosis_providers.dart';

/// Patient's reports: one per released result.
class ReportsListScreen extends ConsumerWidget {
  const ReportsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientId = ref.watch(sessionControllerProvider)?.patientId;
    if (patientId == null) return const SizedBox.shrink();
    final args = (patientId: patientId, patientView: true);
    final results = ref.watch(analysesProvider(args));
    return Scaffold(
      appBar: AppBar(title: const Text('My Reports')),
      body: AsyncValueView<List<AnalysisSummary>>(
        value: results,
        onRetry: () => ref.invalidate(analysesProvider(args)),
        isEmpty: (l) => l.isEmpty,
        empty: const EmptyState(icon: Icons.description_outlined, title: 'No reports yet'),
        data: (list) => ListView(
          padding: const EdgeInsets.all(AppSpacing.screen),
          children: [
            RowGroup(children: [
              for (final a in list)
                ListRowTile(
                  icon: Icons.description_outlined,
                  title: 'MRI analysis report',
                  subtitle: '${Fmt.date(a.createdAt)} · ${(a.finalClass ?? a.predicted).label}',
                  onTap: () => context.push('/patient/reports/${a.id}'),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}
