import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dev/fixtures/fixture_repositories.dart';
import '../../dev/fixtures/fixture_store.dart';
import '../../dev/fixtures/fixture_support_repositories.dart';
import '../../features/appointments/data/appointments_repository.dart';
import '../../features/counselling/data/counselling_repository.dart';
import '../../features/dashboard/data/dashboard_repository.dart';
import '../../features/diagnosis/data/analyses_repository.dart';
import '../../features/diagnosis/services/image_downscaler.dart';
import '../../features/messages/data/messages_repository.dart';
import '../../features/notifications/data/notifications_repository.dart';
import '../../features/patients/data/patients_repository.dart';
import '../../features/profile/data/profile_repository.dart';
import '../../features/reviews/data/reviews_repository.dart';
import '../../features/timeline/data/timeline_repository.dart';
import '../auth/session_controller.dart';
import '../config/app_config.dart';
import '../network/api_client.dart';
import '../network/api_clinical_repositories.dart';
import '../network/api_support_repositories.dart';
import '../utils/clock.dart';

// The one place that decides where data comes from.
// USE_FIXTURES=true → fictional demo repositories (lib/dev/), for demos and tests.
// Otherwise → the NeuroSense server at API_BASE_URL.

final fixtureStoreProvider = Provider<FixtureStore>((ref) => FixtureStore.generate(ref.watch(clockProvider)()));

T _pick<T>(Ref ref, T Function(FixtureStore store) fixture, T Function(ApiClient api) api) =>
    ref.watch(appConfigProvider).useFixtures ? fixture(ref.watch(fixtureStoreProvider)) : api(ref.watch(apiClientProvider));

final patientsRepositoryProvider =
    Provider<PatientsRepository>((ref) => _pick(ref, FixturePatientsRepository.new, ApiPatientsRepository.new));
final analysesRepositoryProvider = Provider<AnalysesRepository>((ref) => _pick(
      ref,
      FixtureAnalysesRepository.new,
      (api) => ApiAnalysesRepository(api, prepareImage: downscaleForUpload),
    ));
final timelineRepositoryProvider =
    Provider<TimelineRepository>((ref) => _pick(ref, FixtureTimelineRepository.new, ApiTimelineRepository.new));
final dashboardRepositoryProvider =
    Provider<DashboardRepository>((ref) => _pick(ref, FixtureDashboardRepository.new, ApiDashboardRepository.new));
final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) => _pick(
      ref,
      FixtureNotificationsRepository.new,
      (api) => ApiNotificationsRepository(api, role: () => ref.read(sessionControllerProvider)?.role),
    ));
final profileRepositoryProvider =
    Provider<ProfileRepository>((ref) => _pick(ref, FixtureProfileRepository.new, ApiProfileRepository.new));
final reviewsRepositoryProvider =
    Provider<ReviewsRepository>((ref) => _pick(ref, FixtureReviewsRepository.new, ApiReviewsRepository.new));
final appointmentsRepositoryProvider = Provider<AppointmentsRepository>(
    (ref) => _pick(ref, FixtureAppointmentsRepository.new, ApiAppointmentsRepository.new));
final messagesRepositoryProvider =
    Provider<MessagesRepository>((ref) => _pick(ref, FixtureMessagesRepository.new, ApiMessagesRepository.new));

/// Counselling runs inside the app in both modes (predefined answers and
/// safety rules; no language model). With the server, "my result" answers read
/// the patient's released result from the API.
final counsellingRepositoryProvider = Provider<CounsellingRepository>((ref) {
  final store = ref.watch(fixtureStoreProvider);
  if (ref.watch(appConfigProvider).useFixtures) return FixtureCounsellingRepository(store);
  final analyses = ref.watch(analysesRepositoryProvider);
  return FixtureCounsellingRepository(
    store,
    releasedResults: (patientId) => analyses.listForPatient(patientId, patientView: true),
  );
});
