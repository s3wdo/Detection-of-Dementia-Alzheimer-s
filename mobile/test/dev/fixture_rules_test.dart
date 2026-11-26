import 'package:flutter_test/flutter_test.dart';
import 'package:neurosense/core/models/info_source.dart';
import 'package:neurosense/core/utils/formatters.dart';
import 'package:neurosense/dev/fixtures/fixture_repositories.dart';
import 'package:neurosense/dev/fixtures/fixture_store.dart';
import 'package:neurosense/features/patients/data/models/patient.dart';

void main() {
  final now = DateTime(2026, 10, 2, 9);
  late FixtureStore store;
  setUp(() => store = FixtureStore.generate(now));

  group('patient visibility rules (same as the backend will enforce)', () {
    test('patients only get released analyses, without clinical notes', () async {
      final repo = FixtureAnalysesRepository(store);
      final doctorView = await repo.listForPatient('p-1024', patientView: false);
      final patientView = await repo.listForPatient('p-1024', patientView: true);

      expect(doctorView, hasLength(3));
      expect(patientView, hasLength(2));
      expect(patientView.every((a) => a.released), isTrue);
      expect(patientView.any((a) => a.id == 'a-1024-1'), isFalse); // unreleased, pending
      expect(patientView.every((a) => a.clinicalNotes == null), isTrue);
      expect(doctorView.first.clinicalNotes, isNotNull);
    });

    test('patient timeline leaves out unreleased AI results', () async {
      final repo = FixtureTimelineRepository(store);
      final doctor = await repo.forPatient('p-1024', patientView: false);
      final patient = await repo.forPatient('p-1024', patientView: true);

      expect(doctor.any((e) => e.id == 'a-1024-1-ai'), isTrue);
      expect(patient.any((e) => e.id == 'a-1024-1-ai'), isFalse);
      expect(patient.any((e) => e.detail.contains('released to patient')), isFalse);
      expect(patient.where((e) => e.source == InfoSource.ai), hasLength(2));
    });

    test('patient dashboard shows the latest released result only', () async {
      final d = await FixtureDashboardRepository(store).patientDashboard('p-1024');
      expect(d.latestReleased!.id, 'a-1024-3');
      expect(d.latestReleased!.clinicalNotes, isNull);
      expect(d.nextAppointment!.title, 'Neurology consultation');
    });
  });

  test('doctor dashboard numbers come from the data', () async {
    final d = await FixtureDashboardRepository(store).doctorDashboard();
    expect(d.patientCount, 8);
    expect(d.pendingReviews, 5);
    expect(d.recentAnalyses, 4);
    expect(d.upcomingAppointments, 4);
    expect(d.recentActivity, hasLength(5));
  });

  group('patient search and filters', () {
    test('filters', () async {
      final repo = FixturePatientsRepository(store);
      final review = await repo.listAssigned((text: '', filter: PatientFilter.needsReview));
      expect(review.map((p) => p.fullName),
          unorderedEquals(['Robert Smith', 'Emily Davis', 'Omar Haddad', 'James Carter']));
      final none = await repo.listAssigned((text: '', filter: PatientFilter.noAnalyses));
      expect(none.single.fullName, 'Michael Chen');
    });

    test('search matches name or patient ID, case-insensitively', () async {
      final repo = FixturePatientsRepository(store);
      expect((await repo.listAssigned((text: 'p-1063', filter: PatientFilter.all))).single.fullName, 'Aisha Rahman');
      expect((await repo.listAssigned((text: 'SARAH', filter: PatientFilter.all))).single.mrn, 'P-1024');
      expect(await repo.listAssigned((text: 'zzz', filter: PatientFilter.all)), isEmpty);
    });
  });

  test('formatters', () {
    expect(Fmt.percent(0.914), '91.4%');
    expect(Fmt.age(DateTime(1958, 3, 12), now), 68);
    expect(Fmt.relative(now.subtract(const Duration(hours: 3)), now), '3 h ago');
  });
}
