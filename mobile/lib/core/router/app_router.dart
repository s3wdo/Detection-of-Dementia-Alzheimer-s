import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/screens/admin_screen.dart';
import '../../features/appointments/screens/appointment_details_screen.dart';
import '../../features/appointments/screens/appointment_request_screen.dart';
import '../../features/appointments/screens/appointments_screen.dart';
import '../../features/auth/screens/dev_role_picker_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/welcome_screen.dart';
import '../../features/counselling/screens/counselling_chat_screen.dart';
import '../../features/counselling/screens/counselling_home_screen.dart';
import '../../features/counselling/screens/resource_detail_screen.dart';
import '../../features/counselling/screens/resources_screen.dart';
import '../../features/dashboard/screens/doctor_dashboard_screen.dart';
import '../../features/dashboard/screens/patient_dashboard_screen.dart';
import '../../features/diagnosis/screens/analysis_progress_screen.dart';
import '../../features/diagnosis/screens/comparison_screen.dart';
import '../../features/diagnosis/screens/diagnosis_result_screen.dart';
import '../../features/diagnosis/screens/mri_upload_screen.dart';
import '../../features/diagnosis/screens/patient_diagnosis_screen.dart';
import '../../features/diagnosis/screens/patient_history_screen.dart';
import '../../features/explainability/screens/explainability_screen.dart';
import '../../features/messages/screens/message_thread_screen.dart';
import '../../features/messages/screens/message_threads_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/patients/screens/patient_list_screen.dart';
import '../../features/patients/screens/patient_profile_screen.dart';
import '../../features/profile/screens/profile_detail_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/settings_screens.dart';
import '../../features/reports/screens/report_screen.dart';
import '../../features/reports/screens/reports_list_screen.dart';
import '../../features/reviews/screens/diagnosis_review_screen.dart';
import '../../features/timeline/screens/timeline_screen.dart';
import '../auth/session_controller.dart';
import '../config/app_config.dart';
import 'role_shells.dart';
import 'routes.dart';

GoRoute _route(String path, Widget Function(GoRouterState state) build, {List<RouteBase> routes = const []}) =>
    GoRoute(path: path, builder: (context, state) => build(state), routes: routes);

/// Settings pages under each role's Profile tab.
List<RouteBase> _profileSettings({required bool doctor}) => [
      _route(Routes.settingsPersonal, (_) => const ProfileDetailScreen.personal()),
      _route(Routes.settingsHealth,
          (_) => ProfileDetailScreen.health(title: doctor ? 'Professional Information' : 'Medical Information')),
      _route(Routes.settingsNotifications, (_) => const NotificationPrefsScreen()),
      _route(Routes.settingsSecurity, (_) => const SecurityPrivacyScreen()),
      _route(Routes.settingsHelp, (_) => const HelpSupportScreen()),
    ];

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run the redirect whenever the session changes (sign in / sign out).
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionControllerProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => appRedirect(
      session: ref.read(sessionControllerProvider),
      location: state.matchedLocation,
      demoEnabled: ref.read(appConfigProvider).useFixtures,
    ),
    routes: [
      _route(Routes.splash, (_) => const SplashScreen()),
      _route(Routes.welcome, (_) => const WelcomeScreen()),
      _route(Routes.login, (_) => const LoginScreen()),
      _route(Routes.adminHome, (_) => const AdminScreen()),
      _route(Routes.forgotPassword, (_) => const ForgotPasswordScreen()),
      _route(Routes.devLogin, (_) => const DevRolePickerScreen()),

      // ---------------- Doctor ----------------
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => DoctorShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [_route(Routes.doctorDashboard, (_) => const DoctorDashboardScreen())]),
          StatefulShellBranch(routes: [
            _route(Routes.doctorPatients, (_) => const PatientListScreen(), routes: [
              _route(':pid', (s) => PatientProfileScreen(patientId: s.pathParameters['pid']!), routes: [
                _route('timeline', (s) => TimelineScreen.doctor(patientId: s.pathParameters['pid']!)),
                _route('compare', (s) => ComparisonScreen.doctor(patientId: s.pathParameters['pid']!)),
                _route('upload', (s) => MriUploadScreen(patientId: s.pathParameters['pid']!)),
                _route(
                    'progress/:aid',
                    (s) => AnalysisProgressScreen(
                          patientId: s.pathParameters['pid']!,
                          analysisId: s.pathParameters['aid']!,
                        )),
                _route(
                    'analyses/:aid',
                    (s) => DiagnosisResultScreen(
                          patientId: s.pathParameters['pid']!,
                          analysisId: s.pathParameters['aid']!,
                        ),
                    routes: [
                      _route('explainability',
                          (s) => ExplainabilityScreen(analysisId: s.pathParameters['aid']!, forPatient: false)),
                      _route(
                          'review',
                          (s) => DiagnosisReviewScreen(
                                patientId: s.pathParameters['pid']!,
                                analysisId: s.pathParameters['aid']!,
                              )),
                      _route(
                          'report',
                          (s) => ReportScreen(
                                analysisId: s.pathParameters['aid']!,
                                patientId: s.pathParameters['pid']!,
                                forPatient: false,
                              )),
                    ]),
              ]),
            ]),
          ]),
          StatefulShellBranch(routes: [
            _route(Routes.doctorAppointments, (_) => const AppointmentsScreen(forDoctor: true), routes: [
              _route(
                  ':apid', (s) => AppointmentDetailsScreen(appointmentId: s.pathParameters['apid']!, forDoctor: true)),
            ]),
          ]),
          StatefulShellBranch(routes: [
            _route(Routes.doctorProfile, (_) => const ProfileScreen(), routes: _profileSettings(doctor: true)),
          ]),
        ],
      ),
      _route(Routes.doctorNotifications, (_) => const NotificationsScreen()),
      _route(Routes.doctorMessages, (_) => const MessageThreadsScreen(), routes: [
        _route(':pid', (s) => MessageThreadScreen.doctor(patientId: s.pathParameters['pid']!)),
      ]),

      // ---------------- Patient ----------------
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => PatientShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [_route(Routes.patientHome, (_) => const PatientDashboardScreen())]),
          StatefulShellBranch(routes: [_route(Routes.patientHistory, (_) => const PatientHistoryScreen())]),
          StatefulShellBranch(routes: [
            _route(Routes.patientCounselling, (_) => const CounsellingHomeScreen(), routes: [
              _route('chat', (s) => CounsellingChatScreen(initialQuestion: s.uri.queryParameters['ask'])),
              _route('resources', (_) => const ResourcesScreen(), routes: [
                _route(':slug', (s) => ResourceDetailScreen(slug: s.pathParameters['slug']!)),
              ]),
            ]),
          ]),
          StatefulShellBranch(routes: [
            _route(Routes.patientProfile, (_) => const ProfileScreen(), routes: _profileSettings(doctor: false)),
          ]),
        ],
      ),
      _route(Routes.patientNotifications, (_) => const NotificationsScreen()),
      _route(Routes.patientMessages, (_) => const MessageThreadScreen.patient()),
      _route(Routes.patientUpload, (_) => const MriUploadScreen.patient()),
      _route(Routes.patientAppointments, (_) => const AppointmentsScreen(forDoctor: false), routes: [
        _route('new', (_) => const AppointmentRequestScreen()),
        _route(':apid', (s) => AppointmentDetailsScreen(appointmentId: s.pathParameters['apid']!, forDoctor: false)),
      ]),
      _route(Routes.patientReports, (_) => const ReportsListScreen(), routes: [
        _route(':aid', (s) => ReportScreen(analysisId: s.pathParameters['aid']!, forPatient: true)),
      ]),
      _route('/patient/compare', (_) => const ComparisonScreen.patient()),
      _route('/patient/results/:aid', (s) => PatientDiagnosisScreen(analysisId: s.pathParameters['aid']!), routes: [
        _route('explainability', (s) => ExplainabilityScreen(analysisId: s.pathParameters['aid']!, forPatient: true)),
      ]),
    ],
    debugLogDiagnostics: kDebugMode,
  );
});
