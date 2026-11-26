import 'package:flutter_test/flutter_test.dart';
import 'package:neurosense/core/router/routes.dart';
import 'package:neurosense/dev/fixtures/demo_users.dart';

void main() {
  group('appRedirect', () {
    test('signed-out users can open public screens only', () {
      expect(appRedirect(session: null, location: Routes.welcome, demoEnabled: true), isNull);
      expect(appRedirect(session: null, location: Routes.doctorDashboard, demoEnabled: true), Routes.login);
      expect(appRedirect(session: null, location: Routes.patientHome, demoEnabled: true), Routes.login);
    });

    test('demo login route is blocked when demo mode is off', () {
      expect(appRedirect(session: null, location: Routes.devLogin, demoEnabled: false), Routes.login);
      expect(appRedirect(session: null, location: Routes.devLogin, demoEnabled: true), isNull);
    });

    test('signed-in users are sent from public screens to their own home', () {
      expect(appRedirect(session: demoDoctor, location: Routes.login, demoEnabled: true), Routes.doctorDashboard);
      expect(appRedirect(session: demoPatient, location: Routes.welcome, demoEnabled: true), Routes.patientHome);
    });

    test('a role cannot open the other role\'s screens', () {
      expect(appRedirect(session: demoDoctor, location: Routes.patientHome, demoEnabled: true), Routes.doctorDashboard);
      expect(appRedirect(session: demoPatient, location: Routes.doctorPatients, demoEnabled: true), Routes.patientHome);
      expect(appRedirect(session: demoDoctor, location: Routes.doctorPatients, demoEnabled: true), isNull);
    });
  });
}
