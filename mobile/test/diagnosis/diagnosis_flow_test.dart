import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosense/core/data/repository_providers.dart';
import 'package:neurosense/dev/fixtures/fixture_repositories.dart';
import 'package:neurosense/features/diagnosis/data/models/mri_file.dart';
import 'package:neurosense/features/diagnosis/screens/diagnosis_result_screen.dart';
import 'package:neurosense/features/diagnosis/screens/mri_upload_screen.dart';
import 'package:neurosense/features/diagnosis/services/mri_services.dart';
import 'package:neurosense/features/reviews/screens/diagnosis_review_screen.dart';

import '../helpers.dart';

/// A real 1×1 PNG so Image.memory can decode it.
final tinyPng =
    base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z/C/HgAGgwJ/lK3Q6wAAAABJRU5ErkJggg==');

class FakePicker implements MriPicker {
  @override
  Future<MriFile?> pick() async => MriFile(name: 'axial_slice_112.png', bytes: tinyPng);
}

class FakeInspector implements MriInspector {
  @override
  Future<MriInspection?> inspect(Uint8List bytes) async =>
      const MriInspection(width: 512, height: 512, grayscaleRatio: 0.98);
}

final overrides = [
  mriPickerProvider.overrideWithValue(FakePicker()),
  mriInspectorProvider.overrideWithValue(FakeInspector()),
  analysesRepositoryProvider.overrideWith(
    (ref) => FixtureAnalysesRepository(ref.watch(fixtureStoreProvider), stepDelay: const Duration(milliseconds: 200)),
  ),
];

Future<void> _scrollTo(WidgetTester tester, Finder target, Type screen) => tester.scrollUntilVisible(
      target,
      250,
      scrollable: find.descendant(of: find.byType(screen), matching: find.byType(Scrollable)).first,
    );

/// Advances time without waiting for endless spinners to stop.
Future<void> _advance(WidgetTester tester, {int steps = 12}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('doctor: upload → preview → simulated analysis → result → review and release', (tester) async {
    await pumpApp(tester, demo: true, overrides: overrides);
    await enterDemo(tester, doctor: true);
    routerOf(tester).go('/doctor/patients/p-1052/upload');
    await tester.pumpAndSettle();

    // Pick an image → preview with checks
    await tester.tap(find.byKey(const Key('pickMri')));
    await tester.pumpAndSettle();
    expect(find.byType(MriUploadScreen), findsOneWidget);
    expect(find.text('Supported format'), findsOneWidget);
    expect(find.text('512 × 512 px'), findsOneWidget);
    expect(find.text('Selected file'), findsOneWidget);

    // Start → progress → result
    await _scrollTo(tester, find.byKey(const Key('startAnalysis')), MriUploadScreen);
    await tester.ensureVisible(find.byKey(const Key('startAnalysis')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('startAnalysis')));
    await _advance(tester, steps: 4); // upload (~250 ms) then the first pipeline steps
    expect(find.text('Analyzing MRI'), findsOneWidget);
    expect(find.text('Running AI model'), findsOneWidget);
    await _advance(tester, steps: 20);
    await tester.pumpAndSettle();
    expect(find.byType(DiagnosisResultScreen), findsOneWidget);
    expect(find.textContaining('SIMULATED RESULT'), findsOneWidget);
    // Explainability states plainly that no map exists yet: no heatmap tabs to click.
    await _scrollTo(tester, find.text('Explainability'), DiagnosisResultScreen);
    await tester.ensureVisible(find.text('Explainability'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Explainability'));
    await tester.pumpAndSettle();
    expect(find.text('Not available yet'), findsOneWidget);
    expect(find.text('Heatmap'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Review: validation, then confirm + release
    await _scrollTo(tester, find.byKey(const Key('reviewButton')), DiagnosisResultScreen);
    await tester.tap(find.byKey(const Key('reviewButton')));
    await tester.pumpAndSettle();
    expect(find.byType(DiagnosisReviewScreen), findsOneWidget);

    await _scrollTo(tester, find.byKey(const Key('releaseSwitch')), DiagnosisReviewScreen);
    await tester.ensureVisible(find.byKey(const Key('releaseSwitch')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byKey(const Key('releaseSwitch')), matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('submitReview')), DiagnosisReviewScreen);
    await tester.ensureVisible(find.byKey(const Key('submitReview')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('submitReview')));
    await tester.pumpAndSettle();
    expect(find.text('Write a summary for the patient before releasing the result.'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('field_patientSummary')), 'Your scan was reviewed. We will talk at your visit.');
    await _scrollTo(tester, find.byKey(const Key('submitReview')), DiagnosisReviewScreen);
    await tester.ensureVisible(find.byKey(const Key('submitReview')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('submitReview')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Submit')));
    await tester.pumpAndSettle();

    // Back on the result: the doctor's decision and release are shown
    expect(find.byType(DiagnosisResultScreen), findsOneWidget);
    await _scrollTo(tester, find.text('Released to patient'), DiagnosisResultScreen);
    expect(find.text('Released to patient'), findsOneWidget);
    expect(find.text('REVIEWED BY DR. AHMED KHAN'), findsOneWidget);
  });

  testWidgets('patient: an unreleased result cannot be opened', (tester) async {
    await pumpApp(tester, demo: true);
    await enterDemo(tester, doctor: false);
    routerOf(tester).go('/patient/results/a-1024-1');
    await tester.pumpAndSettle();
    expect(find.text('This item was not found.'), findsOneWidget);
  });

  testWidgets('patient: released result shows the doctor decision first, then AI output', (tester) async {
    await pumpApp(tester, demo: true);
    await enterDemo(tester, doctor: false);
    await tester.ensureVisible(find.text('View result'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View result'));
    await tester.pumpAndSettle();
    expect(find.text('REVIEWED BY DR. AHMED KHAN'), findsOneWidget);
    expect(find.text("Your doctor's classification"), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
  });
}
