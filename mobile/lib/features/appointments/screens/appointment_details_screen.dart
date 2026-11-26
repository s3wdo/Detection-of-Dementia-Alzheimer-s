import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../appointment_actions.dart';
import '../appointments_providers.dart';
import '../data/models/appointment.dart';
import '../widgets/appointment_card.dart';

/// Appointment details. Doctors can confirm, reschedule or cancel;
/// patients can cancel their own upcoming appointments.
class AppointmentDetailsScreen extends ConsumerStatefulWidget {
  const AppointmentDetailsScreen({super.key, required this.appointmentId, required this.forDoctor});

  final String appointmentId;
  final bool forDoctor;

  @override
  ConsumerState<AppointmentDetailsScreen> createState() => _AppointmentDetailsScreenState();
}

class _AppointmentDetailsScreenState extends ConsumerState<AppointmentDetailsScreen> {
  bool _busy = false;

  Future<void> _do(Future<bool> Function() action) async {
    setState(() => _busy = true);
    await action();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final appt = ref.watch(appointmentProvider(widget.appointmentId));
    final now = ref.watch(clockProvider)();
    return Scaffold(
      appBar: AppBar(title: const Text('Appointment')),
      body: AsyncValueView<Appointment>(
        value: appt,
        onRetry: () => ref.invalidate(appointmentProvider(widget.appointmentId)),
        data: (a) {
          final open = a.isUpcoming(now);
          return ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xxl),
            children: [
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.title, style: AppTextStyles.title),
                  const SizedBox(height: AppSpacing.sm),
                  StatusBadge(appointmentStatusKind(a.status)),
                  const SizedBox(height: AppSpacing.md),
                  InfoRow(label: 'Date', value: Fmt.weekday(a.startsAt)),
                  InfoRow(label: 'Time', value: '${Fmt.time(a.startsAt)} · ${a.durationMinutes} min'),
                  InfoRow(
                      label: widget.forDoctor ? 'Patient' : 'Doctor',
                      value: widget.forDoctor ? a.patientName : a.doctorName),
                  if (a.location != null) InfoRow(label: 'Location', value: a.location!),
                ]),
              ),
              const SizedBox(height: AppSpacing.xxl),
              if (open && widget.forDoctor && a.status == AppointmentStatus.requested) ...[
                AppButton(
                  key: const Key('confirmAppointment'),
                  label: 'Confirm',
                  icon: Icons.check_rounded,
                  loading: _busy,
                  variant: AppButtonVariant.success,
                  onPressed: () => _do(() => AppointmentActions.confirm(context, ref, a)),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (open && widget.forDoctor) ...[
                AppButton(
                  label: 'Reschedule',
                  icon: Icons.edit_calendar_outlined,
                  variant: AppButtonVariant.secondary,
                  onPressed: _busy ? null : () => _do(() => AppointmentActions.reschedule(context, ref, a)),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (open)
                AppButton(
                  key: const Key('cancelAppointment'),
                  label: 'Cancel appointment',
                  icon: Icons.close_rounded,
                  variant: AppButtonVariant.danger,
                  onPressed: _busy ? null : () => _do(() => AppointmentActions.cancel(context, ref, a)),
                ),
              if (!open) const Text('This appointment can no longer be changed.', style: AppTextStyles.caption),
            ],
          );
        },
      ),
    );
  }
}
