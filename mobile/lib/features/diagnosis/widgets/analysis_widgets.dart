import 'package:flutter/material.dart';

import '../../../core/widgets/badges.dart';
import '../data/models/analysis.dart';

/// Review-state badge for an analysis.
class AnalysisStatusBadge extends StatelessWidget {
  const AnalysisStatusBadge(this.analysis, {super.key});

  final AnalysisSummary analysis;

  @override
  Widget build(BuildContext context) => StatusBadge(switch (analysis.status) {
        ReviewStatus.awaitingConfirmation => StatusKind.awaitingConfirmation,
        ReviewStatus.pendingReview => StatusKind.pendingReview,
        ReviewStatus.confirmed || ReviewStatus.overridden => StatusKind.reviewed,
      });
}
