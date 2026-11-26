import '../../diagnosis/data/models/upload_models.dart';
import 'models/dashboards.dart';

/// API: GET /doctor/dashboard, GET /doctor/review-queue, GET /patient/dashboard.
abstract interface class DashboardRepository {
  Future<DoctorDashboard> doctorDashboard();

  /// Everything waiting for the doctor, oldest first: analyses to review and
  /// analyses that failed.
  Future<List<ReviewQueueItem>> reviewQueue();

  Future<PatientDashboard> patientDashboard(String patientId);
}
