import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:neurosense/app.dart';
import 'package:neurosense/core/config/app_config.dart';
import 'package:neurosense/core/network/api_client.dart';
import 'package:neurosense/core/router/app_router.dart';
import 'package:neurosense/core/storage/token_storage.dart';
import 'package:neurosense/features/auth/screens/splash_screen.dart';

import 'api/fakes.dart';

/// Starts the whole app with demo mode on or off and waits past the splash.
///
/// With demo mode off the app talks to [server] (a fake); without one, the
/// server is unreachable. Tokens are kept in [tokens] instead of the keystore.
Future<void> pumpApp(
  WidgetTester tester, {
  required bool demo,
  List<Override> overrides = const [],
  FakeServer? server,
  MemoryTokenStorage? tokens,
}) async {
  final storage = tokens ?? MemoryTokenStorage();
  await tester.pumpWidget(
    ProviderScope(
      retry: (retryCount, error) => null,
      overrides: [
        appConfigProvider.overrideWithValue(AppConfig(useFixtures: demo, apiBaseUrl: 'http://test.invalid/api/v1')),
        if (!demo) ...[
          tokenStorageProvider.overrideWithValue(storage),
          apiClientProvider.overrideWith((ref) => ApiClient(
                baseUrl: 'http://test.invalid/api/v1',
                tokens: storage,
                adapter: server ?? FakeServer.offline(),
                onSessionExpired: () => ref.read(sessionExpiredProvider.notifier).signal(),
              )),
        ],
        ...overrides,
      ],
      child: const NeuroSenseApp(),
    ),
  );
  await tester.pump(SplashScreen.duration + const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
}

/// The app's router, for jumping straight to a location in tests.
GoRouter routerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(NeuroSenseApp))).read(routerProvider);

/// Welcome → Log in → Open demo login → pick a role.
Future<void> enterDemo(WidgetTester tester, {required bool doctor}) async {
  final logIn = find.widgetWithText(FilledButton, 'Log in');
  await tester.ensureVisible(logIn);
  await tester.tap(logIn);
  await tester.pumpAndSettle();
  await _tapInList(tester, find.byKey(const Key('openDemoLogin')));
  await _tapInList(tester, find.byKey(Key(doctor ? 'demoDoctor' : 'demoPatient')));
}

/// Scrolls the screen's list until [target] is built and visible, then taps it.
/// (Lists build lazily, so at large text sizes the target may not exist yet.)
Future<void> _tapInList(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 200,
        scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// Bottom-nav labels currently shown.
List<String> navLabels(WidgetTester tester) =>
    tester.widgetList<NavigationDestination>(find.byType(NavigationDestination)).map((d) => d.label).toList();

/// Taps a bottom-nav tab (labels like "Patients" also appear elsewhere on screen).
Future<void> tapNav(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await tester.pumpAndSettle();
}
