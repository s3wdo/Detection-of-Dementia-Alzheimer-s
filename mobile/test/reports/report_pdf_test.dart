import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosense/features/diagnosis/data/analyses_repository.dart';
import 'package:neurosense/features/reports/services/report_pdf.dart';

import '../api/fakes.dart';
import '../helpers.dart';

final _pdf = Uint8List.fromList('%PDF-1.4 test'.codeUnits);

const _patient = {
  'id': 'p-1',
  'mrn': 'P-1024',
  'full_name': 'Sarah Johnson',
  'date_of_birth': '1958-03-12',
  'sex': 'female',
  'phone': '+000 555 1024',
  'email': 'sarah@example.test',
  'emergency_contact': 'Daniel Johnson (son)',
  'latest_analysis': null,
};

FakeServer _server({required Reply pdfReply}) => FakeServer((c) => switch (c.path) {
      '/me' => (200, doctorUser),
      '/patients/p-1' => (200, _patient),
      '/patients/p-1/analyses' => (200, [analysisJson(id: 'a-1', reviewed: true)]),
      '/analyses/a-1' => (200, analysisJson(id: 'a-1', reviewed: true)),
      '/analyses/a-1/report.pdf' => pdfReply,
      _ when c.path.endsWith('s') || c.path.contains('queue') => (200, <Object>[]),
      _ => (200, <String, Object>{}),
    });

/// Brings the button to the middle of the screen (clear of the tab bar) and taps it.
Future<void> _tapDownload(WidgetTester tester) async {
  final button = find.byKey(const Key('downloadPdf'));
  await tester.scrollUntilVisible(button, 300);
  await tester.runAsync(() => Scrollable.ensureVisible(tester.element(button), alignment: 0.5));
  await tester.pumpAndSettle();
  await tester.tap(button);
}

Future<List<ReportFile>> _openReport(WidgetTester tester, FakeServer server) async {
  final shared = <ReportFile>[];
  await pumpApp(tester,
      demo: false,
      server: server,
      tokens: MemoryTokenStorage(access: 'A', refresh: 'R'),
      overrides: [
        reportSharerProvider.overrideWithValue((ReportFile file, Rect? origin) async => shared.add(file)),
      ]);
  routerOf(tester).go('/doctor/patients/p-1/analyses/a-1/report');
  await tester.pumpAndSettle();
  await _tapDownload(tester);
  await tester.pumpAndSettle();
  return shared;
}

void main() {
  testWidgets('Download PDF fetches the server-made report and opens the share sheet', (tester) async {
    final server = _server(pdfReply: (200, _pdf));
    final shared = await _openReport(tester, server);

    final call = server.calls.singleWhere((c) => c.path == '/analyses/a-1/report.pdf');
    expect(call.query['utc_offset_minutes'], DateTime.now().timeZoneOffset.inMinutes);
    expect(shared, hasLength(1));
    expect(shared.single.filename, 'NeuroSense-report-P-1024-2026-11-23.pdf');
    expect(shared.single.bytes, _pdf);
  });

  testWidgets('a refused download says why and shares nothing', (tester) async {
    final server = _server(
        pdfReply: error(409, 'CONFLICT', 'A report is available after the doctor has reviewed the result.'));
    final shared = await _openReport(tester, server);
    expect(shared, isEmpty);
    expect(find.textContaining('after the doctor has reviewed the result'), findsOneWidget);
  });

  testWidgets('demo data does not invent a PDF', (tester) async {
    await pumpApp(tester, demo: true);
    await enterDemo(tester, doctor: true);
    routerOf(tester).go('/doctor/patients/p-1024/analyses/a-1024-3/report');
    await tester.pumpAndSettle();
    await _tapDownload(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.textContaining("server isn't connected"), findsOneWidget);
  });
}
