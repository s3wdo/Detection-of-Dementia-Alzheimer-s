import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosense/core/auth/api_auth_repository.dart';
import 'package:neurosense/core/router/routes.dart';
import 'package:neurosense/features/auth/screens/login_screen.dart';
import 'package:neurosense/features/auth/screens/welcome_screen.dart';
import 'package:neurosense/features/dashboard/screens/doctor_dashboard_screen.dart';
import 'package:neurosense/features/dashboard/screens/patient_dashboard_screen.dart';
import 'package:neurosense/features/patients/screens/patient_list_screen.dart';
import 'package:neurosense/features/profile/screens/profile_screen.dart';

import 'helpers.dart';

void main() {
  testWidgets('splash moves on to the welcome screen', (tester) async {
    await pumpApp(tester, demo: true);
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets('demo doctor lands on the doctor dashboard with the doctor tabs', (tester) async {
    await pumpApp(tester, demo: true);
    await enterDemo(tester, doctor: true);
    expect(find.byType(DoctorDashboardScreen), findsOneWidget);
    expect(find.textContaining('Dr. Ahmed'), findsWidgets);
    expect(navLabels(tester), ['Dashboard', 'Patients', 'Appointments', 'Profile']);
  });

  testWidgets('demo patient lands on the patient home with the patient tabs', (tester) async {
    await pumpApp(tester, demo: true);
    await enterDemo(tester, doctor: false);
    expect(find.byType(PatientDashboardScreen), findsOneWidget);
    expect(find.textContaining('Sarah'), findsWidgets);
    expect(navLabels(tester), ['Home', 'History', 'Counselling', 'Profile']);
  });

  testWidgets('switching tabs keeps each tab alive', (tester) async {
    await pumpApp(tester, demo: true);
    await enterDemo(tester, doctor: true);
    await tapNav(tester, 'Patients');
    expect(find.byType(PatientListScreen), findsOneWidget);

    await tapNav(tester, 'Dashboard');
    expect(find.byType(DoctorDashboardScreen), findsOneWidget);
    // The Patients tab is kept off-stage rather than destroyed.
    expect(find.byType(PatientListScreen, skipOffstage: false), findsOneWidget);
  });

  testWidgets("a doctor can't open patient screens", (tester) async {
    await pumpApp(tester, demo: true);
    await enterDemo(tester, doctor: true);
    routerOf(tester).go(Routes.patientHome);
    await tester.pumpAndSettle();
    expect(find.byType(DoctorDashboardScreen), findsOneWidget);
    expect(find.byType(PatientDashboardScreen), findsNothing);
  });

  testWidgets('log out returns to the login screen', (tester) async {
    await pumpApp(tester, demo: true);
    await enterDemo(tester, doctor: false);
    await tapNav(tester, 'Profile');
    // The button is below the fold; lazy lists only build what is on screen.
    await tester.scrollUntilVisible(
      find.byKey(const Key('logoutButton')),
      200,
      scrollable: find.descendant(of: find.byType(ProfileScreen), matching: find.byType(Scrollable)).first,
    );
    await tester.tap(find.byKey(const Key('logoutButton')));
    await tester.pumpAndSettle();
    // Confirm in the dialog (destructive actions use the red outlined button).
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Log out')));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  group('demo mode off', () {
    testWidgets('no demo login and no demo ribbon', (tester) async {
      await pumpApp(tester, demo: false);
      expect(find.text('DEMO DATA'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('openDemoLogin')), findsNothing);

      routerOf(tester).go(Routes.devLogin);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('email sign-in says the server cannot be reached instead of faking it', (tester) async {
      await pumpApp(tester, demo: false);
      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'someone@example.com');
      await tester.enterText(find.byType(TextField).at(1), 'secret');
      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await tester.pumpAndSettle();
      expect(find.text(ApiAuthRepository.unreachable), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });
  });
}
