import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosense/core/auth/session.dart';
import 'package:neurosense/core/config/app_config.dart';
import 'package:neurosense/core/router/routes.dart';
import 'package:neurosense/features/admin/screens/admin_screen.dart';

import '../helpers.dart';
import 'fakes.dart';

const _adminUser = {
  'id': 'u-admin',
  'full_name': 'Demo Admin',
  'role': 'admin',
  'subtitle': 'Administrator',
  'patient_id': null,
  'display_id': 'A-1001',
};

Map<String, Object?> _row(String id, String role, String name, {String? doctor, int? patients}) => {
      'id': 'u-$id',
      'display_id': id,
      'role': role,
      'full_name': name,
      'email': '${id.toLowerCase()}@example.test',
      'is_active': true,
      'doctor_display_id': doctor,
      'doctor_name': doctor == null ? null : 'Dr. Ahmed Khan',
      'patient_count': patients,
    };

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  test('admins stay in the admin area; doctors and patients stay out of it', () {
    Session as(UserRole role) => Session(userId: 'u', fullName: 'N', role: role, subtitle: '');
    String? go(UserRole role, String to) => appRedirect(session: as(role), location: to, demoEnabled: false);

    expect(go(UserRole.admin, Routes.adminHome), isNull);
    expect(go(UserRole.admin, Routes.doctorDashboard), Routes.adminHome);
    expect(go(UserRole.admin, Routes.patientHome), Routes.adminHome);
    expect(go(UserRole.doctor, Routes.adminHome), Routes.doctorDashboard);
    expect(go(UserRole.patient, Routes.adminHome), Routes.patientHome);
    expect(go(UserRole.doctor, Routes.doctorPatients), isNull);
  });

  test('a typed server address becomes a full API address', () {
    expect(normalizeServerAddress('192.168.1.20'), 'http://192.168.1.20:8000/api/v1');
    expect(normalizeServerAddress(' http://10.0.0.5:9000/api/v1 '), 'http://10.0.0.5:9000/api/v1');
    expect(normalizeServerAddress('https://example.org'), 'https://example.org:443/api/v1');
    expect(normalizeServerAddress(''), isNull);
  });

  testWidgets('an admin signs in with an ID, sees every account and creates a doctor', (tester) async {
    final rows = [
      _row('A-1001', 'admin', 'Demo Admin'),
      _row('D-1001', 'doctor', 'Dr. Ahmed Khan', patients: 1),
      _row('P-1024', 'patient', 'Sarah Johnson', doctor: 'D-1001'),
    ];
    final server = FakeServer((c) => switch ((c.method, c.path)) {
          ('POST', '/auth/login') => (200, {'access_token': 'A', 'refresh_token': 'R', 'user': _adminUser}),
          ('GET', '/admin/users') => (200, rows),
          ('POST', '/admin/users') => (201, _row('D-1002', 'doctor', 'Dr. Layla Nasser', patients: 0)),
          _ => error(404, 'NOT_FOUND', 'This item was not found.'),
        });
    await pumpApp(tester, demo: false, server: server);

    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'A-1001');
    await tester.enterText(find.byType(TextField).at(1), 'pw');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await _settle(tester);

    expect(find.byType(AdminScreen), findsOneWidget);
    expect(find.text('DOCTORS (1)'), findsOneWidget);
    expect(find.text('Sarah Johnson'), findsOneWidget);
    expect(find.textContaining('Doctor D-1001'), findsOneWidget);

    await tester.tap(find.byKey(const Key('newAccount')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choice-doctor')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Dr. Layla Nasser');
    await tester.enterText(find.byType(TextField).at(1), 'layla@example.test');
    await tester.enterText(find.byType(TextField).at(2), 'a long password');
    final create = find.byKey(const Key('createAccount'));
    await tester.ensureVisible(create);
    await tester.pumpAndSettle();
    await tester.tap(create);
    await _settle(tester);

    expect(find.textContaining('ID D-1002'), findsOneWidget);
    final sent = server.calls.lastWhere((c) => c.path == '/admin/users' && c.method == 'POST').body as Map;
    expect(sent['role'], 'doctor');
    expect(sent.containsKey('doctor_display_id'), isFalse);

    await tester.tap(find.text('Done'));
    await _settle(tester);
    expect(find.byType(AdminScreen), findsOneWidget);
  });
}
