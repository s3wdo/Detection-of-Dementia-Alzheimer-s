import 'models/timeline_event.dart';

/// Real version: GET /patients/{pid}/timeline.
abstract interface class TimelineRepository {
  /// Newest first. With [patientView], unreleased AI results and their reviews
  /// are left out — the patient only sees what the doctor has released.
  Future<List<TimelineEvent>> forPatient(String patientId, {required bool patientView});
}
