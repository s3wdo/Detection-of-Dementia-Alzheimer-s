import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session_controller.dart';
import '../../core/data/repository_providers.dart';
import '../diagnosis/data/models/upload_models.dart';
import 'data/models/dashboards.dart';

final doctorDashboardProvider = FutureProvider<DoctorDashboard>(
  (ref) => ref.watch(dashboardRepositoryProvider).doctorDashboard(),
);

/// The signed-in patient's own dashboard. The patient id comes from the
/// session (token), never from user input.
final patientDashboardProvider = FutureProvider<PatientDashboard>((ref) {
  final patientId = ref.watch(sessionControllerProvider)?.patientId;
  if (patientId == null) throw StateError('No patient session');
  return ref.watch(dashboardRepositoryProvider).patientDashboard(patientId);
});

/// Everything waiting for the doctor, oldest first: analyses to review and
/// analyses that failed. Rebuilt whenever the dashboard is refreshed.
final reviewQueueProvider = FutureProvider<List<ReviewQueueItem>>((ref) async {
  await ref.watch(doctorDashboardProvider.future);
  return ref.watch(dashboardRepositoryProvider).reviewQueue();
});
