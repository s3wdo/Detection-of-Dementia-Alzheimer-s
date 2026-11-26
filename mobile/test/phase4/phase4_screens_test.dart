import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosense/core/data/repository_providers.dart';
import 'package:neurosense/dev/fixtures/fixture_support_repositories.dart';
import 'package:neurosense/features/appointments/screens/appointment_details_screen.dart';
import 'package:neurosense/features/counselling/screens/counselling_chat_screen.dart';
import 'package:neurosense/features/counselling/screens/counselling_home_screen.dart';
import 'package:neurosense/features/messages/screens/message_thread_screen.dart';
import 'package:neurosense/features/diagnosis/screens/comparison_screen.dart';
import 'package:neurosense/features/reports/screens/report_screen.dart';

import '../helpers.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder target, Type screen) => tester.scrollUntilVisible(
      target,
      250,
      scrollable: find.descendant(of: find.byType(screen), matching: find.byType(Scrollable)).first,
    );

void main() {
  testWidgets('doctor report separates AI-generated and doctor-reviewed information', (tester) async {
    await pumpApp(tester, demo: true);
    await enterDemo(tester, doctor: true);
    routerOf(tester).go('/doctor/patients/p-1024/analyses/a-1024-3/report');
    await _settle(tester);
    expect(find.text('AI-GENERATED INFORMATION'), findsOneWidget);
    await _scrollTo(tester, find.text('DOCTOR-REVIEWED INFORMATION'), ReportScreen);
    await _scrollTo(tester, find.text('Clinical notes'), ReportScreen);
    expect(find.text('Clinical notes'), findsOneWidget);
  });

  testWidgets('patient report has no clinical notes', (tester) async {
    await pumpApp(tester, demo: true);
    await enterDemo(tester, doctor: false);
    routerOf(tester).go('/patient/reports/a-1024-3');
    await _settle(tester);
    await _scrollTo(tester, find.text('Patient summary'), ReportScreen);
    expect(find.text('Clinical notes'), findsNothing);
    expect(find.textContaining('word-finding'), findsNothing);
  });

  testWidgets('patient comparison warns that changes do not prove progression', (tester) async {
    await pumpApp(tester, demo: true);
    await enterDemo(tester, doctor: false);
    routerOf(tester).go('/patient/compare');
    await _settle(tester);
    await _scrollTo(
        tester, find.textContaining('do not by themselves establish disease progression'), ComparisonScreen);
    expect(find.textContaining('do not by themselves establish disease progression'), findsOneWidget);
    expect(find.text('Model confidence per analysis'), findsNothing); // chart is doctor-only
  });

  testWidgets('counselling chat answers safely and refers medication questions', (tester) async {
    await pumpApp(tester, demo: true, overrides: [
      counsellingRepositoryProvider.overrideWith(
        (ref) => FixtureCounsellingRepository(ref.watch(fixtureStoreProvider), replyDelay: Duration.zero),
      ),
    ]);
    await enterDemo(tester, doctor: false);
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Counselling')));
    await _settle(tester);
    await _scrollTo(tester, find.byKey(const Key('openChat')), CounsellingHomeScreen);
    await tester.ensureVisible(find.byKey(const Key('openChat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('openChat')));
    await _settle(tester);
    expect(find.byType(CounsellingChatScreen), findsOneWidget);
    expect(find.textContaining('PROTOTYPE'), findsOneWidget);

    await tester.tap(find.text('What does my latest MRI result mean?'));
    await _settle(tester);
    // The chat scrolls to the newest content; scroll back up to the answer.
    await tester.scrollUntilVisible(find.textContaining('not a diagnosis'), -250,
        scrollable: find.descendant(of: find.byType(CounsellingChatScreen), matching: find.byType(Scrollable)).first);
    expect(find.textContaining('not a diagnosis'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('chatInput')), 'Can I stop taking my medication?');
    await tester.tap(find.byKey(const Key('chatSend')));
    await _settle(tester);
    await tester.scrollUntilVisible(find.text('Message my doctor'), -250,
        scrollable: find.descendant(of: find.byType(CounsellingChatScreen), matching: find.byType(Scrollable)).first);
    expect(find.text('Please ask your doctor'), findsOneWidget);
    expect(find.text('Message my doctor'), findsOneWidget);
  });

  testWidgets('doctor confirms a requested appointment', (tester) async {
    await pumpApp(tester, demo: true);
    await enterDemo(tester, doctor: true);
    routerOf(tester).go('/doctor/appointments/ap-2');
    await _settle(tester);
    expect(find.byType(AppointmentDetailsScreen), findsOneWidget);
    expect(find.text('Requested'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmAppointment')));
    await _settle(tester);
    expect(find.text('Confirmed'), findsOneWidget);
  });

  testWidgets('patient sends a message to the care team', (tester) async {
    await pumpApp(tester, demo: true);
    await enterDemo(tester, doctor: false);
    await tester.tap(find.byTooltip('Messages'));
    await _settle(tester);
    expect(find.textContaining('not to the AI assistant'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('messageInput')), 'Can we move my appointment?');
    await tester.ensureVisible(find.byKey(const Key('sendMessage')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sendMessage')));
    await _settle(tester);
    await _scrollTo(tester, find.text('Can we move my appointment?'), MessageThreadScreen);
    expect(find.text('Can we move my appointment?'), findsOneWidget);
  });
}
