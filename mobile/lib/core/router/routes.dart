import '../auth/session.dart';

/// All route paths in one place.
abstract final class Routes {
  // Public
  static const splash = '/splash';
  static const welcome = '/welcome';
  static const login = '/login';
  static const forgotPassword = '/forgot-password';
  static const devLogin = '/dev-login'; // development only

  // Admin: account management only
  static const adminHome = '/admin';

  // Doctor shell tabs
  static const doctorDashboard = '/doctor/dashboard';
  static const doctorPatients = '/doctor/patients';
  static const doctorAppointments = '/doctor/appointments';
  static const doctorProfile = '/doctor/profile';
  static const doctorNotifications = '/doctor/notifications';
  static const doctorMessages = '/doctor/messages';

  // Patient shell tabs
  static const patientHome = '/patient/home';
  static const patientHistory = '/patient/history';
  static const patientCounselling = '/patient/counselling';
  static const patientProfile = '/patient/profile';
  static const patientNotifications = '/patient/notifications';
  static const patientMessages = '/patient/messages';

  // Doctor: per-patient screens
  static String doctorPatient(String id) => '$doctorPatients/$id';
  static String doctorPatientTimeline(String id) => '$doctorPatients/$id/timeline';
  static String doctorPatientUpload(String id) => '$doctorPatients/$id/upload';
  static String doctorAnalysisProgress(String pid, String aid) => '$doctorPatients/$pid/progress/$aid';
  static String doctorAnalysis(String pid, String aid) => '$doctorPatients/$pid/analyses/$aid';
  static String doctorExplainability(String pid, String aid) => '${doctorAnalysis(pid, aid)}/explainability';
  static String doctorReview(String pid, String aid) => '${doctorAnalysis(pid, aid)}/review';

  // Patient: secondary screens
  static const patientAppointments = '/patient/appointments';
  static const patientReports = '/patient/reports';
  static const patientUpload = '/patient/upload';
  static String patientResult(String id) => '/patient/results/$id';
  static String patientResultExplainability(String id) => '/patient/results/$id/explainability';

  // Profile settings pages (nested under each role's profile tab)
  static const settingsPersonal = 'personal';
  static const settingsHealth = 'health';
  static const settingsNotifications = 'notification-preferences';
  static const settingsSecurity = 'security';
  static const settingsHelp = 'help';
  static String profileSetting(UserRole role, String page) =>
      '${role == UserRole.doctor ? doctorProfile : patientProfile}/$page';

  static const public = {splash, welcome, login, forgotPassword, devLogin};

  static String homeFor(UserRole role) => switch (role) {
        UserRole.doctor => doctorDashboard,
        UserRole.patient => patientHome,
        UserRole.admin => adminHome,
      };
}

/// Decides where the user may go. This is a UI convenience only — the backend
/// will enforce real authorization on every request.
///
/// Returns a path to redirect to, or null to allow [location].
String? appRedirect({required Session? session, required String location, required bool demoEnabled}) {
  if (location == Routes.devLogin && !demoEnabled) return Routes.login;

  if (session == null) {
    return Routes.public.contains(location) ? null : Routes.login;
  }

  final home = Routes.homeFor(session.role);
  if (location == Routes.splash) return null; // the splash moves on by itself
  if (Routes.public.contains(location)) return home;
  final area = switch (session.role) {
    UserRole.doctor => '/doctor',
    UserRole.patient => '/patient',
    UserRole.admin => '/admin',
  };
  if (!location.startsWith(area)) return home;
  return null;
}
