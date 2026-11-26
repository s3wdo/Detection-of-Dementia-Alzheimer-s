import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosense/core/data/not_connected.dart';
import 'package:neurosense/core/data/repository_providers.dart';
import 'package:neurosense/core/data/user_facing_error.dart';
import 'package:neurosense/core/network/api_error.dart';
import 'package:neurosense/core/widgets/state_views.dart';
import 'package:neurosense/dev/fixtures/fixture_repositories.dart';
import 'package:neurosense/features/notifications/data/models/app_notification.dart';
import 'package:neurosense/features/notifications/data/notifications_repository.dart';
import 'package:neurosense/features/patients/data/models/doctor_note.dart';
import 'package:neurosense/features/patients/data/models/patient.dart';
import 'package:neurosense/features/patients/data/patients_repository.dart';
import 'package:neurosense/features/patients/widgets/patient_row.dart';

import '../helpers.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// Fails until [healthy] is set, like a server that comes back.
class _FlakyPatients implements PatientsRepository {
  _FlakyPatients(this._real);
  final PatientsRepository _real;
  bool healthy = false;

  @override
  Future<List<Patient>> listAssigned(PatientQuery query) async {
    if (!healthy) throw const ApiError(code: 'NETWORK', message: 'Connection lost. Please retry.');
    return _real.listAssigned(query);
  }

  @override
  Future<Patient> getPatient(String patientId) => _real.getPatient(patientId);

  @override
  Future<List<DoctorNote>> notes(String patientId) => _real.notes(patientId);

  @override
  Future<DoctorNote> addNote(String patientId, {required String body, required String author}) =>
      _real.addNote(patientId, body: body, author: author);

  @override
  Future<Patient> updateContact(String patientId, {required String phone, required String emergencyContact}) =>
      _real.updateContact(patientId, phone: phone, emergencyContact: emergencyContact);
}

class _NoNotifications implements NotificationsRepository {
  @override
  Future<List<AppNotification>> listFor(String userId) async => const [];
  @override
  Future<void> markRead(String notificationId) async {}
  @override
  Future<void> markAllRead(String userId) async {}
}

void main() {
  group('error messages shown to users', () {
    test('known errors keep their message, unknown errors become generic', () {
      expect(userMessage(const NotConnectedException()), "The NeuroSense server isn't connected yet.");
      expect(userMessage(const ApiError(code: 'TIMEOUT', message: 'The server took too long.')),
          'The server took too long.');
      expect(userMessage(ArgumentError('Write a message first.')), 'Write a message first.');
      expect(userMessage(StateError('internal detail')), 'Something went wrong. Please try again.');
      expect(userMessage(Exception('SELECT * FROM patients')), isNot(contains('SELECT')));
    });
  });

  testWidgets('patient list shows an error with Retry, and recovers', (tester) async {
    late _FlakyPatients flaky;
    await pumpApp(tester, demo: true, overrides: [
      patientsRepositoryProvider.overrideWith((ref) {
        flaky = _FlakyPatients(FixturePatientsRepository(ref.watch(fixtureStoreProvider)));
        return flaky;
      }),
    ]);
    await enterDemo(tester, doctor: true);
    routerOf(tester).go('/doctor/patients');
    await _settle(tester);

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Connection lost. Please retry.'), findsOneWidget);

    flaky.healthy = true;
    await tester.tap(find.text('Try again'));
    await _settle(tester);
    expect(find.byType(ErrorState), findsNothing);
    expect(find.byType(PatientRow), findsWidgets);
  });

  testWidgets('notifications show an empty state', (tester) async {
    await pumpApp(tester, demo: true, overrides: [
      notificationsRepositoryProvider.overrideWithValue(_NoNotifications()),
    ]);
    await enterDemo(tester, doctor: false);
    routerOf(tester).go('/patient/notifications');
    await _settle(tester);
    expect(find.byType(EmptyState), findsOneWidget);
  });

  testWidgets('a loading spinner shows while data is on its way', (tester) async {
    await pumpApp(tester, demo: true);
    await enterDemo(tester, doctor: true);
    routerOf(tester).go('/doctor/messages');
    await tester.pump(); // fixture latency (250 ms) has not passed yet
    expect(find.byType(LoadingState), findsOneWidget);
    await _settle(tester);
    expect(find.byType(LoadingState), findsNothing);
  });

  testWidgets('without demo data, signed-out users see a clear "cannot reach the server" login message', (tester) async {
    await pumpApp(tester, demo: false);
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'doctor@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't reach the NeuroSense server"), findsWidgets);
  });
}
