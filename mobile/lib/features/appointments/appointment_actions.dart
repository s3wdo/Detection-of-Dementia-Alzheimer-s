import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/repository_providers.dart';
import '../../core/data/user_facing_error.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_dialogs.dart';
import 'appointments_providers.dart';
import 'data/models/appointment.dart';

/// Confirm / reschedule / cancel, shared by the appointment list cards and the
/// details screen. Each shows a snackbar with the outcome and refreshes the data.
abstract final class AppointmentActions {
  static Future<bool> _run(BuildContext context, WidgetRef ref, Future<void> Function() action, String done) async {
    try {
      await action();
      refreshAppointments(ref);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      return true;
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(userMessage(e))));
      return false;
    }
  }

  static Future<bool> confirm(BuildContext context, WidgetRef ref, Appointment a) => _run(
        context,
        ref,
        () => ref.read(appointmentsRepositoryProvider).setStatus(a.id, AppointmentStatus.confirmed),
        'Appointment confirmed.',
      );

  static Future<bool> cancel(BuildContext context, WidgetRef ref, Appointment a) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Cancel appointment?',
      message: '${a.title} on ${Fmt.dateTime(a.startsAt)} will be cancelled.',
      confirmLabel: 'Cancel appointment',
      destructive: true,
    );
    if (!ok || !context.mounted) return false;
    return _run(
      context,
      ref,
      () => ref.read(appointmentsRepositoryProvider).setStatus(a.id, AppointmentStatus.cancelled),
      'Appointment cancelled.',
    );
  }

  static Future<bool> reschedule(BuildContext context, WidgetRef ref, Appointment a) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: a.startsAt.isAfter(now) ? a.startsAt : now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 180)),
    );
    if (date == null || !context.mounted) return false;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(a.startsAt));
    if (time == null || !context.mounted) return false;
    final when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    return _run(context, ref, () => ref.read(appointmentsRepositoryProvider).reschedule(a.id, when),
        'Appointment rescheduled.');
  }
}
