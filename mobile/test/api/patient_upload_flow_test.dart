import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosense/app.dart';
import 'package:neurosense/core/data/repository_providers.dart';
import 'package:neurosense/core/network/api_client.dart';
import 'package:neurosense/core/network/api_clinical_repositories.dart';
import 'package:neurosense/features/dashboard/screens/patient_dashboard_screen.dart';
import 'package:neurosense/features/diagnosis/screens/analysis_progress_screen.dart';
import 'package:neurosense/features/diagnosis/screens/mri_upload_screen.dart';
import 'package:neurosense/features/diagnosis/services/mri_services.dart';

import '../diagnosis/diagnosis_flow_test.dart' show FakeInspector, FakePicker;
import '../helpers.dart';
import 'fakes.dart';

final _pickers = [
  mriPickerProvider.overrideWithValue(FakePicker()),
  mriInspectorProvider.overrideWithValue(FakeInspector()),
];

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder target, Type screen) async {
  await tester.scrollUntilVisible(target, 200,
      scrollable: find.descendant(of: find.byType(screen), matching: find.byType(Scrollable)).first);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

/// Nothing on screen may reveal analysis output.
void _expectNoAnalysisOutput() {
  for (final label in ['MCI', 'Cognitively Normal', 'Alzheimer']) {
    expect(find.textContaining(label), findsNothing);
  }
  expect(find.textContaining('confidence', findRichText: true), findsNothing);
  expect(find.textContaining('SIMULATED'), findsNothing);
  expect(find.byType(AnalysisProgressScreen), findsNothing);
}

void main() {
  testWidgets('patient upload ends on a confirmation and shows nothing about the analysis', (tester) async {
    await pumpApp(tester, demo: true, overrides: _pickers);
    await enterDemo(tester, doctor: false);
    final container = ProviderScope.containerOf(tester.element(find.byType(NeuroSenseApp)));
    final analyses = container.read(analysesRepositoryProvider);
    final releasedBefore = (await tester.runAsync(() => analyses.listForPatient('p-1024', patientView: true)))!.length;
    final allBefore = (await tester.runAsync(() => analyses.listForPatient('p-1024', patientView: false)))!.length;

    await _scrollTo(tester, find.byKey(const Key('patientUpload')), PatientDashboardScreen);
    await tester.tap(find.byKey(const Key('patientUpload')));
    await tester.pumpAndSettle();
    expect(find.byType(MriUploadScreen), findsOneWidget);
    expect(find.text('Selected patient'), findsNothing); // the doctor-only header

    await tester.tap(find.byKey(const Key('pickMri')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('startAnalysis')), MriUploadScreen);
    expect(find.text('Send to my doctor'), findsOneWidget);
    await tester.tap(find.byKey(const Key('startAnalysis')));
    await _settle(tester);

    expect(find.text('Sent to your doctor'), findsOneWidget);
    _expectNoAnalysisOutput();

    await tester.tap(find.byKey(const Key('uploadDone')));
    await _settle(tester);
    await _settle(tester); // the home screen reloads the upload list once it is visible again
    expect(find.byType(PatientDashboardScreen), findsOneWidget);
    await _scrollTo(tester, find.byKey(const Key('patientUpload')), PatientDashboardScreen);
    expect(find.textContaining('waiting for your doctor to review it'), findsOneWidget);

    // The doctor's side has one more analysis; the patient's released list is unchanged.
    expect((await tester.runAsync(() => analyses.listForPatient('p-1024', patientView: false)))!.length, allBefore + 1);
    expect(
        (await tester.runAsync(() => analyses.listForPatient('p-1024', patientView: true)))!.length, releasedBefore);
  });

  testWidgets('with the server: sign in, see the released result marked simulated, and upload a scan',
      (tester) async {
    final tokens = MemoryTokenStorage();
    final server = FakeServer((c) => switch ((c.method, c.path)) {
          ('POST', '/auth/login') => (200, {'access_token': 'A', 'refresh_token': 'R', 'user': patientUser}),
          ('GET', '/patient/dashboard') => (200, {
              'latest_released': analysisJson(reviewed: true, released: true, forPatient: true),
              'next_appointment': null,
              'recent_activity': <Object>[],
            }),
          ('GET', '/analyses/a-1') => (200, analysisJson(reviewed: true, released: true, forPatient: true)),
          ('GET', '/notifications') => (200, <Object>[]),
          ('GET', '/scans/mine') => (200, <Object>[]),
          ('POST', '/scans') => (202, {'scan_id': 's-1', 'analysis_id': 'a-2', 'status': 'received'}),
          _ => error(404, 'NOT_FOUND', 'This item was not found.'),
        });
    await pumpApp(
      tester,
      demo: false,
      server: server,
      tokens: tokens,
      overrides: [
        ..._pickers,
        // The real image downscaler decodes with the engine; tests send the bytes as they are.
        analysesRepositoryProvider.overrideWith(
          (ref) => ApiAnalysesRepository(ref.watch(apiClientProvider), prepareImage: (bytes) async => bytes),
        ),
      ],
    );

    // No demo login in this mode: the real form signs in against the server.
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('openDemoLogin')), findsNothing);
    await tester.enterText(find.byType(TextField).at(0), 'sarah.johnson@neurosense.test');
    await tester.enterText(find.byType(TextField).at(1), 'pw');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await _settle(tester);

    expect(find.byType(PatientDashboardScreen), findsOneWidget);
    expect(tokens.refresh, 'R');
    expect(find.text('Early MCI'), findsOneWidget);
    expect(find.text('REVIEWED BY DR. AHMED KHAN'), findsOneWidget);

    // The released result keeps the "simulated" notice that came from the server.
    routerOf(tester).push('/patient/results/a-1');
    await _settle(tester);
    expect(find.textContaining('SIMULATED RESULT'), findsOneWidget);
    expect(find.textContaining('private note'), findsNothing);
    routerOf(tester).pop();
    await _settle(tester);

    // Upload: the app sends the image without a patient id and shows only the confirmation.
    routerOf(tester).push('/patient/upload');
    await _settle(tester);
    await tester.tap(find.byKey(const Key('pickMri')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('startAnalysis')), MriUploadScreen);
    await tester.tap(find.byKey(const Key('startAnalysis')));
    await _settle(tester);

    expect(find.text('Sent to your doctor'), findsOneWidget);
    _expectNoAnalysisOutput();
    final upload = server.calls.lastWhere((c) => c.path == '/scans' && c.method == 'POST');
    expect((upload.body as Map).keys, ['image_base64', 'filename']);
    expect(upload.authorization, 'Bearer A');
    // The app never asks for the analysis it just created.
    expect(server.paths, isNot(contains('GET /analyses/a-2')));
    expect(server.paths, isNot(contains('GET /analyses/a-2/status')));
  });
}
