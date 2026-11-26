import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosense/features/notifications/screens/notifications_screen.dart';
import 'package:neurosense/features/patients/screens/patient_list_screen.dart';
import 'package:neurosense/features/patients/screens/patient_profile_screen.dart';
import 'package:neurosense/features/profile/screens/profile_screen.dart';
import 'package:neurosense/features/profile/screens/settings_screens.dart';

import 'helpers.dart';

Future<void> _scrollTo(WidgetTester tester, Finder target, Type screen) => tester.scrollUntilVisible(
      target,
      250,
      scrollable: find.descendant(of: find.byType(screen), matching: find.byType(Scrollable)).first,
    );

/// Waits for the demo repositories' artificial delay, then for animations.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  group('doctor', () {
    testWidgets('dashboard leads with the patients awaiting review', (tester) async {
      await pumpApp(tester, demo: true);
      await enterDemo(tester, doctor: true);
      await _settle(tester);
      expect(find.text('8 patients · 4 appointments this week'), findsOneWidget);
      expect(find.text('AWAITING YOUR REVIEW'), findsOneWidget);
      expect(find.text('Robert Smith'), findsWidgets);
      expect(find.text('Aisha Rahman'), findsNothing); // already reviewed
      expect(find.text('View all'), findsWidgets);
    });

    testWidgets('"View all" in the review queue opens the patient list filtered to "Needs review"', (tester) async {
      await pumpApp(tester, demo: true);
      await enterDemo(tester, doctor: true);
      await _settle(tester);
      await tester.tap(find.byKey(const Key('reviewQueueAll')));
      await tester.pumpAndSettle();
      expect(find.byType(PatientListScreen), findsOneWidget);
      expect(find.text('Robert Smith'), findsOneWidget);
      expect(find.text('Aisha Rahman'), findsNothing); // already reviewed
    });

    testWidgets('search finds a patient by ID and shows an empty state otherwise', (tester) async {
      await pumpApp(tester, demo: true);
      await enterDemo(tester, doctor: true);
      await tapNav(tester, 'Patients');

      await tester.enterText(find.byKey(const Key('patientSearch')), 'P-1063');
      await _settle(tester);
      expect(find.text('Aisha Rahman'), findsOneWidget);
      expect(find.text('Robert Smith'), findsNothing);

      await tester.enterText(find.byKey(const Key('patientSearch')), 'nobody');
      await _settle(tester);
      expect(find.text('No patients found'), findsOneWidget);
    });

    testWidgets('patient profile shows the AI result and doctor-only notes', (tester) async {
      await pumpApp(tester, demo: true);
      await enterDemo(tester, doctor: true);
      await tapNav(tester, 'Patients');
      await tester.enterText(find.byKey(const Key('patientSearch')), 'Sarah');
      await _settle(tester);
      await tester.tap(find.text('Sarah Johnson'));
      await tester.pumpAndSettle();

      expect(find.byType(PatientProfileScreen), findsOneWidget);
      await _scrollTo(tester, find.text('AI MODEL OUTPUT'), PatientProfileScreen);
      expect(find.text('AI MODEL OUTPUT'), findsWidgets);
      await _scrollTo(tester, find.textContaining('word-finding difficulty'), PatientProfileScreen);
      expect(find.text('Visible to clinicians only'), findsOneWidget);
      expect(find.textContaining('word-finding difficulty'), findsOneWidget);
    });

    testWidgets('timeline source filter hides other sources', (tester) async {
      await pumpApp(tester, demo: true);
      await enterDemo(tester, doctor: true);
      routerOf(tester).go('/doctor/patients/p-1024/timeline');
      await tester.pumpAndSettle();
      expect(find.text('Doctor review'), findsWidgets);

      await tester.tap(find.widgetWithText(ChoiceChip, 'AI'));
      await tester.pumpAndSettle();
      expect(find.text('Doctor review'), findsNothing);
      expect(find.text('MRI analysis'), findsWidgets);
    });
  });

  group('patient', () {
    testWidgets('dashboard shows the released result, marked as AI output and doctor-reviewed', (tester) async {
      await pumpApp(tester, demo: true);
      await enterDemo(tester, doctor: false);
      expect(find.text('Early MCI'), findsOneWidget);
      // Patients never see the model's confidence score.
      expect(find.textContaining('Confidence', findRichText: true), findsNothing);
      expect(find.text('AI MODEL OUTPUT'), findsOneWidget);
      expect(find.text('REVIEWED BY DR. AHMED KHAN'), findsOneWidget);
      expect(find.textContaining('not a medical diagnosis'), findsOneWidget);
    });

    testWidgets('notifications: mark all as read', (tester) async {
      await pumpApp(tester, demo: true);
      await enterDemo(tester, doctor: false);
      await tester.tap(find.byTooltip('Notifications, 3 unread'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Mark all read'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Mark all read'), findsNothing);

      await tester.tap(find.text('Unread'));
      await tester.pumpAndSettle();
      expect(find.text("You're all caught up."), findsOneWidget);
    });

    testWidgets('profile settings open their pages', (tester) async {
      await pumpApp(tester, demo: true);
      await enterDemo(tester, doctor: false);
      await tapNav(tester, 'Profile');
      await _scrollTo(tester, find.text('Personal information'), ProfileScreen);
      await tester.tap(find.text('Personal information'));
      await tester.pumpAndSettle();
      expect(find.text('Daniel Johnson (son)'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
      await _scrollTo(tester, find.text('Security & privacy'), ProfileScreen);
      await tester.tap(find.text('Security & privacy'));
      await tester.pumpAndSettle();
      final academic = find.textContaining('not a certified medical device', findRichText: true);
      await _scrollTo(tester, academic, SecurityPrivacyScreen);
      expect(academic, findsOneWidget);
    });
  });
}
