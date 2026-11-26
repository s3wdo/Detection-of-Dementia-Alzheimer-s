import 'package:flutter/material.dart';

import '../models/info_source.dart';
import '../theme/app_colors.dart';

/// Colours and label for each information source, so timelines, activity
/// lists and badges all mark AI / doctor / admin information the same way.
({Color color, Color tint, String label}) sourceStyle(InfoSource source) => switch (source) {
      InfoSource.ai => (color: AppColors.ai, tint: AppColors.aiTint, label: 'AI'),
      InfoSource.doctor => (color: AppColors.doctor, tint: AppColors.doctorTint, label: 'Doctor'),
      InfoSource.admin => (color: AppColors.admin, tint: AppColors.adminTint, label: 'Admin'),
    };

/// Small uppercase source label used on timeline rows ("AI", "DOCTOR", "ADMIN").
class SourceTag extends StatelessWidget {
  const SourceTag(this.source, {super.key});

  final InfoSource source;

  @override
  Widget build(BuildContext context) {
    final s = sourceStyle(source);
    return Text(
      s.label.toUpperCase(),
      style: TextStyle(color: s.color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8),
    );
  }
}
