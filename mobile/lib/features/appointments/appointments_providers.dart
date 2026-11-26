import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session_controller.dart';
import '../../core/data/repository_providers.dart';
import '../dashboard/dashboard_providers.dart';
import '../notifications/notifications_providers.dart';
import '../timeline/timeline_providers.dart';
import 'data/models/appointment.dart';

final doctorAppointmentsProvider = FutureProvider<List<Appointment>>(
  (ref) => ref.watch(appointmentsRepositoryProvider).listForDoctor(),
);

/// The signed-in patient's own appointments (id from the session).
final patientAppointmentsProvider = FutureProvider<List<Appointment>>((ref) {
  final patientId = ref.watch(sessionControllerProvider)?.patientId;
  if (patientId == null) throw StateError('No patient session');
  return ref.watch(appointmentsRepositoryProvider).listForPatient(patientId);
});

final appointmentProvider = FutureProvider.family<Appointment, String>(
  (ref, id) => ref.watch(appointmentsRepositoryProvider).get(id),
);

/// Refresh everything that shows appointments after a change.
void refreshAppointments(WidgetRef ref) {
  ref.invalidate(doctorAppointmentsProvider);
  ref.invalidate(patientAppointmentsProvider);
  ref.invalidate(appointmentProvider);
  ref.invalidate(doctorDashboardProvider);
  ref.invalidate(patientDashboardProvider);
  ref.invalidate(timelineProvider);
  ref.invalidate(notificationsProvider);
}
