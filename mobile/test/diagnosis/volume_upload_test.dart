import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosense/core/network/api_clinical_repositories.dart';
import 'package:neurosense/features/diagnosis/data/models/analysis.dart';
import 'package:neurosense/features/diagnosis/services/volume_picker.dart';

import '../api/fakes.dart';
import '../helpers.dart';

final _scan = VolumeFile(name: 'brain.nii.gz', bytes: Uint8List.fromList(List.filled(2048, 7)));

void main() {
  group('full MRI scan (.nii) upload', () {
    test('the scan goes to /scans/volume as the raw file, with the patient in the query', () async {
      final server = FakeServer((c) => (202, {'scan_id': 's-1', 'analysis_id': 'a-7', 'status': 'received'}));
      final repo = ApiAnalysesRepository(
        clientFor(server, MemoryTokenStorage(access: 'A')),
        prepareImage: (bytes) async => bytes,
        pollInterval: Duration.zero,
      );
      final id = await repo.startVolumeAnalysis(patientId: 'p-7', filename: 'brain.nii.gz', bytes: _scan.bytes);

      expect(id, 'a-7');
      expect(server.paths, ['POST /scans/volume']);
      expect(server.calls.single.query, {'patient_id': 'p-7', 'filename': 'brain.nii.gz'});
    });

    test('a failed full-scan analysis says why', () async {
      final server = FakeServer(
          (c) => (200, {'analysis_id': 'a-7', 'job_status': 'failed', 'error_code': 'VOLUME_TOO_FEW_SLICES'}));
      final repo = ApiAnalysesRepository(
        clientFor(server, MemoryTokenStorage(access: 'A')),
        prepareImage: (bytes) async => bytes,
        pollInterval: Duration.zero,
      );
      expect(
        repo.watchJob('a-7').toList(),
        throwsA(predicate((e) => e.toString().contains('Too few brain slices'))),
      );
    });

    test('the result keeps how many slices were averaged', () {
      final a = AnalysisSummary.fromJson({
        ...analysisJson(),
        'input_kind': 'volume',
        'slices_total': 182,
        'slices_kept': 96,
        'slices_used': 81,
        'slice_index': 70,
      });
      expect(a.volume?.slicesUsed, 81);
      expect(a.volume?.sliceIndex, 70);
      expect(AnalysisSummary.fromJson(a.toJson()).volume?.slicesKept, 96);
      expect(AnalysisSummary.fromJson(analysisJson()).volume, isNull);
      expect(a.forPatient().volume, isNull, reason: 'patients get no model details');
    });

    test('only .nii and .nii.gz files up to 64 MB are sent', () {
      expect(VolumeRules.problem(_scan), isNull);
      expect(VolumeRules.problem(VolumeFile(name: 'BRAIN.NII', bytes: Uint8List(10))), isNull);
      expect(VolumeRules.problem(VolumeFile(name: 'slice.png', bytes: Uint8List(10))), isNotNull);
      expect(VolumeRules.problem(VolumeFile(name: 'scan.nii', bytes: Uint8List(0))), isNotNull);
    });

    Future<void> openUpload(WidgetTester tester, VolumeFile? picked) async {
      await pumpApp(tester, demo: true, overrides: [volumePickerProvider.overrideWithValue(() async => picked)]);
      await enterDemo(tester, doctor: true);
      routerOf(tester).go('/doctor/patients/p-1024/upload');
      await tester.pumpAndSettle();
    }

    testWidgets('the doctor screen explains which slice to upload and offers a full scan', (tester) async {
      await openUpload(tester, _scan);
      expect(find.text('WHICH SLICE TO UPLOAD'), findsOneWidget);
      expect(find.textContaining('Face pointing up'), findsOneWidget);
      expect(find.textContaining('brain tissue filling most of the image'), findsOneWidget);

      await tester.scrollUntilVisible(find.byKey(const Key('pickVolume')), 200);
      await tester.tap(find.byKey(const Key('pickVolume')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('volumeCard')), findsOneWidget);
      expect(find.text('brain.nii.gz'), findsOneWidget);

      // Demo data cannot analyse a full scan; it says so instead of inventing a result.
      await tester.scrollUntilVisible(find.byKey(const Key('startVolumeAnalysis')), 200);
      await tester.tap(find.byKey(const Key('startVolumeAnalysis')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Upload failed'), findsOneWidget);
    });

    testWidgets('a file that is not a NIfTI scan cannot be sent', (tester) async {
      await openUpload(tester, VolumeFile(name: 'notes.pdf', bytes: Uint8List(100)));
      await tester.scrollUntilVisible(find.byKey(const Key('pickVolume')), 200);
      await tester.tap(find.byKey(const Key('pickVolume')));
      await tester.pumpAndSettle();
      expect(find.textContaining('.nii or .nii.gz'), findsOneWidget);
      final button = tester.widget<FilledButton>(
          find.descendant(of: find.byKey(const Key('startVolumeAnalysis')), matching: find.byType(FilledButton)));
      expect(button.onPressed, isNull);
    });

    testWidgets('patients see the slice guidance but no full-scan option', (tester) async {
      await pumpApp(tester, demo: true);
      await enterDemo(tester, doctor: false);
      routerOf(tester).go('/patient/upload');
      await tester.pumpAndSettle();
      expect(find.text('WHICH SLICE TO UPLOAD'), findsOneWidget);
      expect(find.byKey(const Key('pickVolume')), findsNothing);
    });
  });
}
