import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/badges.dart';
import '../data/models/appointment.dart';

StatusKind appointmentStatusKind(AppointmentStatus s) => switch (s) {
      AppointmentStatus.confirmed => StatusKind.confirmed,
      AppointmentStatus.requested => StatusKind.requested,
      AppointmentStatus.cancelled => StatusKind.cancelled,
      AppointmentStatus.completed => StatusKind.reviewed,
    };

/// One appointment in a list: date, who / what / when, status, optional actions.
class AppointmentCard extends StatelessWidget {
  const AppointmentCard({
    super.key,
    required this.appointment,
    required this.forDoctor,
    required this.onTap,
    this.actions = const [],
  });

  final Appointment appointment;
  final bool forDoctor;
  final VoidCallback onTap;

  /// Buttons shown under the row (View / Cancel, Confirm / Reschedule / Cancel).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            DateTile(date: a.startsAt),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(forDoctor ? a.patientName : a.doctorName, style: AppTextStyles.label.copyWith(fontSize: 16)),
                Text(a.title, style: AppTextStyles.bodySmall.copyWith(color: AppColors.ink)),
                Text(
                    '${Fmt.time(a.startsAt)} · ${a.durationMinutes} min${a.location == null ? '' : ' · ${a.location}'}',
                    style: AppTextStyles.caption),
                const SizedBox(height: AppSpacing.sm),
                StatusBadge(appointmentStatusKind(a.status)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ]),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 52 + AppSpacing.lg - AppSpacing.md),
              child: Wrap(spacing: AppSpacing.xs, children: actions),
            ),
        ]),
      ),
    );
  }
}

/// Month / day / weekday stacked as plain text, used at the start of appointment rows.
class DateTile extends StatelessWidget {
  const DateTile({super.key, required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      child: Column(children: [
        Text(DateFormat('MMM').format(date).toUpperCase(),
            style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
        Text(DateFormat('dd').format(date), style: AppTextStyles.title.copyWith(fontSize: 24, height: 1.15)),
        Text(DateFormat('EEE').format(date), style: AppTextStyles.caption),
      ]),
    );
  }
}
