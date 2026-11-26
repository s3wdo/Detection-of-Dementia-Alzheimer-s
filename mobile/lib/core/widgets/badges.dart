import 'package:flutter/material.dart';

import '../models/info_source.dart';
import '../theme/app_colors.dart';

export '../models/info_source.dart';
import '../theme/app_spacing.dart';

/// Compact state pill used by [StatusBadge].
class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.fg, required this.bg, this.icon});

  final String text;
  final Color fg;
  final Color bg;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadii.pill)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 5)],
            Flexible(
              child: Text(
                text,
                style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quiet label naming where information comes from: an icon and spaced capitals
/// in the source colour, no fill. AI output and doctor decisions stay distinct.
class SourceBadge extends StatelessWidget {
  const SourceBadge(this.source, {super.key, this.doctorName});

  final InfoSource source;

  /// Shown as "Reviewed by `name`" for [InfoSource.doctor].
  final String? doctorName;

  @override
  Widget build(BuildContext context) {
    final (text, color, icon) = switch (source) {
      InfoSource.ai => ('AI model output', AppColors.ai, Icons.filter_center_focus_rounded),
      InfoSource.doctor => (
          doctorName == null ? 'Doctor reviewed' : 'Reviewed by $doctorName',
          AppColors.doctor,
          Icons.medical_services_outlined
        ),
      InfoSource.admin => ('Administrative', AppColors.admin, Icons.event_note_outlined),
    };
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text.toUpperCase(),
            style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 1.0),
          ),
        ),
      ]),
    );
  }
}

enum StatusKind { reviewed, awaitingConfirmation, pendingReview, released, confirmed, requested, cancelled }

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.kind, {super.key});

  final StatusKind kind;

  static String labelFor(StatusKind kind) => switch (kind) {
        StatusKind.reviewed => 'Reviewed',
        StatusKind.awaitingConfirmation => 'Awaiting confirmation',
        StatusKind.pendingReview => 'Pending review',
        StatusKind.released => 'Released to patient',
        StatusKind.confirmed => 'Confirmed',
        StatusKind.requested => 'Requested',
        StatusKind.cancelled => 'Cancelled',
      };

  @override
  Widget build(BuildContext context) {
    final text = labelFor(kind);
    return switch (kind) {
      StatusKind.reviewed ||
      StatusKind.confirmed =>
        _Pill(text: text, fg: AppColors.success, bg: AppColors.successTint, icon: Icons.check_rounded),
      StatusKind.awaitingConfirmation ||
      StatusKind.pendingReview =>
        _Pill(text: text, fg: AppColors.pending, bg: AppColors.pendingTint, icon: Icons.schedule_rounded),
      StatusKind.released =>
        _Pill(text: text, fg: AppColors.primary, bg: AppColors.primaryTint, icon: Icons.visibility_outlined),
      StatusKind.requested =>
        _Pill(text: text, fg: AppColors.primary, bg: AppColors.primaryTint, icon: Icons.schedule_rounded),
      StatusKind.cancelled =>
        _Pill(text: text, fg: AppColors.admin, bg: AppColors.adminTint, icon: Icons.close_rounded),
    };
  }
}
