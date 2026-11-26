import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosense/features/appointments/screens/appointment_details_screen.dart';
import 'package:neurosense/features/notifications/screens/notifications_screen.dart';

import '../helpers.dart';
import 'screen_sweep_test.dart' show doctorRoutes, patientRoutes;

/// Tab roots have no back button; every other screen must have one.
const _tabRoots = {
  '/doctor/dashboard',
  '/doctor/patients',
  '/doctor/appointments',
  '/doctor/profile',
  '/patient/home',
  '/patient/history',
  '/patient/counselling',
  '/patient/profile',
};

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

Finder get _back => find.byWidgetPredicate((w) => w is BackButton || (w is IconButton && w.tooltip == 'Back'));

void main() {
  for (final doctor in [true, false]) {
    final role = doctor ? 'doctor' : 'patient';
    testWidgets('$role: every screen opened from the app has a back button', (tester) async {
      await pumpApp(tester, demo: true);
      await enterDemo(tester, doctor: doctor);
      final missing = <String>[];
      // The progress screen deliberately has a close (X) button instead of Back.
      for (final r in (doctor ? doctorRoutes : patientRoutes)
          .where((r) => !_tabRoots.contains(r) && !r.contains('/progress/'))) {
        routerOf(tester).push(r);
        await _settle(tester);
        if (_back.hitTestable().evaluate().isEmpty) missing.add(r);
        routerOf(tester).go(doctor ? '/doctor/dashboard' : '/patient/home');
        await _settle(tester);
      }
      expect(missing, isEmpty, reason: 'No back button on: ${missing.join(', ')}');
    });
  }

  testWidgets('opening an appointment notification shows details with a back button to Notifications', (tester) async {
    await pumpApp(tester, demo: true);
    await enterDemo(tester, doctor: false);
    await tester.tap(find.byTooltip('Notifications, 3 unread'));
    await _settle(tester);
    await tester.tap(find.text('Appointment reminder'));
    await _settle(tester);
    expect(find.byType(AppointmentDetailsScreen), findsOneWidget);

    await tester.tap(_back.hitTestable().first);
    await _settle(tester);
    expect(find.byType(NotificationsScreen), findsOneWidget);
  });
}
