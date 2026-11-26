import '../../../appointments/data/models/appointment.dart';
import '../../../diagnosis/data/models/analysis.dart';
import '../../../timeline/data/models/timeline_event.dart';

/// Matches GET /doctor/dashboard.
class DoctorDashboard {
  const DoctorDashboard({
    required this.patientCount,
    required this.pendingReviews,
    required this.recentAnalyses,
    required this.upcomingAppointments,
    required this.recentActivity,
  });

  final int patientCount;

  /// AI results still waiting for a doctor's decision.
  final int pendingReviews;

  /// Analyses run in the last 7 days.
  final int recentAnalyses;

  /// Appointments in the next 7 days.
  final int upcomingAppointments;
  final List<TimelineEvent> recentActivity;
}

/// Matches GET /patient/dashboard. Only released results are included.
class PatientDashboard {
  const PatientDashboard({this.latestReleased, this.nextAppointment, required this.recentActivity});

  final AnalysisSummary? latestReleased;
  final Appointment? nextAppointment;
  final List<TimelineEvent> recentActivity;
}
