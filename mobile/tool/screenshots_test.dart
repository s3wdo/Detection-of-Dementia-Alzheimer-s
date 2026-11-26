// Renders every main screen to PNG with the real fonts, for design review.
// Not part of the normal test run. Usage:
//   flutter test tool/screenshots_test.dart --update-goldens
// Output: tool/screenshots/<role>-<name>.png (390 × 844 phone, 2× pixels).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosense/core/network/server_finder.dart';
import 'package:neurosense/features/diagnosis/services/volume_picker.dart';

import '../test/helpers.dart';

Future<void> _loadFonts() async {
  Future<ByteData> bytes(String path) async => ByteData.view(Uint8List.fromList(await File(path).readAsBytes()).buffer);
  const dir = 'assets/fonts';
  final families = {
    'IBMPlexSans': ['Regular', 'Medium', 'SemiBold', 'Bold'],
    'SourceSerif4': ['Medium', 'SemiBold', 'Bold'],
    'IBMPlexMono': ['Regular', 'Medium', 'SemiBold'],
  };
  for (final e in families.entries) {
    final loader = FontLoader(e.key);
    for (final w in e.value) {
      loader.addFont(bytes('$dir/${e.key}-$w.ttf'));
    }
    await loader.load();
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? 'C:/dev/flutter';
  await (FontLoader('MaterialIcons')
        ..addFont(bytes('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')))
      .load();
}

const doctorScreens = {
  'dashboard': '/doctor/dashboard',
  'patients': '/doctor/patients',
  'patient-profile': '/doctor/patients/p-1024',
  'upload': '/doctor/patients/p-1024/upload',
  'result': '/doctor/patients/p-1024/analyses/a-1024-3',
  'explainability': '/doctor/patients/p-1024/analyses/a-1024-3/explainability',
  'review': '/doctor/patients/p-1031/analyses/a-1031-1/review',
  'report': '/doctor/patients/p-1024/analyses/a-1024-3/report',
  'timeline': '/doctor/patients/p-1024/timeline',
  'compare': '/doctor/patients/p-1024/compare',
  'appointments': '/doctor/appointments',
  'appointment-details': '/doctor/appointments/ap-2',
  'notifications': '/doctor/notifications',
  'messages': '/doctor/messages',
  'profile': '/doctor/profile',
  'progress': '/doctor/patients/p-1024/progress/a-1024-3',
  'security': '/doctor/profile/security',
  'review-confirmed': '/doctor/patients/p-1024/analyses/a-1024-3',
  'result-pending': '/doctor/patients/p-1031/analyses/a-1031-1',
};

const patientScreens = {
  'home': '/patient/home',
  'history': '/patient/history',
  'result': '/patient/results/a-1024-3',
  'counselling': '/patient/counselling',
  'chat': '/patient/counselling/chat',
  'resource': '/patient/counselling/resources/understanding-your-results',
  'messages': '/patient/messages',
  'appointments': '/patient/appointments',
  'book': '/patient/appointments/new',
  'reports': '/patient/reports',
  'report': '/patient/reports/a-1024-3',
  'notifications': '/patient/notifications',
  'profile': '/patient/profile',
  'compare': '/patient/compare',
  'timeline-tab': '/patient/history',
  'security': '/patient/profile/security',
  'appointment-details': '/patient/appointments/ap-1',
  'resources': '/patient/counselling/resources',
};

void main() {
  setUpAll(_loadFonts);

  // FULL=true renders tall pages so whole scrolling screens are visible.
  const full = bool.fromEnvironment('FULL');
  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(780, full ? 5200 : 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  testWidgets('welcome, login, role picker', (tester) async {
    await phone(tester);
    await pumpApp(tester, demo: true);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/welcome.png'));
    routerOf(tester).go('/login');
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/login.png'));
    routerOf(tester).go('/dev-login');
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/role-picker.png'));
  });

  testWidgets('server address: find server on this Wi-Fi', (tester) async {
    await phone(tester);
    final result = Completer<String?>();
    await pumpApp(tester, demo: false, overrides: [
      serverFinderProvider.overrideWithValue((progress) {
        progress(118, 254);
        return result.future;
      }),
    ]);
    routerOf(tester).go('/login');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('serverAddress')));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/server-1-dialog.png'));
    await tester.tap(find.byKey(const Key('findServerButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/server-2-searching.png'));
    result.complete('192.168.1.178');
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/server-3-found.png'));
  });

  testWidgets('server address: nothing found', (tester) async {
    await phone(tester);
    await pumpApp(tester, demo: false, overrides: [serverFinderProvider.overrideWithValue((_) async => null)]);
    routerOf(tester).go('/login');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('serverAddress')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('findServerButton')));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/server-4-not-found.png'));
  });

  // Upload screens as an iPhone shows them (iOS look, 1170 x 2532, room for the
  // status bar and home indicator). The status bar itself is drawn on afterwards.
  Future<void> iphone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 141, bottom: 102);
    tester.view.viewPadding = const FakeViewPadding(top: 141, bottom: 102);
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('iPhone: doctor upload screens', (tester) async {
    await iphone(tester);
    // An empty 12 MB stand-in: only its name and size are shown.
    final scan = VolumeFile(name: 'sub-01_T1w.nii.gz', bytes: Uint8List(12 * 1024 * 1024 + 400000));
    await pumpApp(tester, demo: true, overrides: [volumePickerProvider.overrideWithValue(() async => scan)]);
    await enterDemo(tester, doctor: true);
    routerOf(tester).go('/doctor/patients/p-1024/upload');
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/iphone/1-doctor-upload.png'));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/iphone/2-doctor-upload-slice-guide.png'));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('pickVolume')));
    await tester.tap(find.byKey(const Key('pickVolume')));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/iphone/3-doctor-full-scan-selected.png'));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('iPhone: patient upload screen', (tester) async {
    await iphone(tester);
    await pumpApp(tester, demo: true);
    await enterDemo(tester, doctor: false);
    routerOf(tester).go('/patient/upload');
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/iphone/4-patient-upload.png'));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  for (final doctor in [true, false]) {
    final role = doctor ? 'doctor' : 'patient';
    testWidgets('$role screens', (tester) async {
      await phone(tester);
      await pumpApp(tester, demo: true);
      await enterDemo(tester, doctor: doctor);
      for (final e in (doctor ? doctorScreens : patientScreens).entries) {
        routerOf(tester).go(e.value);
        // Nested data loads one after another; give each step its simulated latency.
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        await tester.pumpAndSettle();
        await expectLater(
            find.byType(MaterialApp), matchesGoldenFile('screenshots/${full ? 'full/' : ''}$role-${e.key}.png'));
      }
    });
  }
}
