import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../api/fakes.dart';
import '../helpers.dart';

// A 1 x 1 grey PNG.
const _png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNgAAAAAgABSK+kcQAAAABJRU5ErkJggg==';

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

void main() {
  testWidgets('compare and report show each analysis\'s stored MRI slice', (tester) async {
    final server = FakeServer((c) => switch (c.path) {
          '/me' => (200, doctorUser),
          '/patients/p-1' => (200, _patient),
          '/patients/p-1/analyses' => (200, [analysisJson(id: 'a-2'), analysisJson(id: 'a-1', reviewed: true)]),
          '/analyses/a-1' => (200, analysisJson(id: 'a-1', reviewed: true)),
          '/analyses/a-1/image' || '/analyses/a-2/image' => (200, {'image_base64': _png, 'mime': 'image/png'}),
          _ when c.path.endsWith('s') || c.path.contains('queue') => (200, <Object>[]),
          _ => (200, <String, Object>{}),
        });
    await pumpApp(tester, demo: false, server: server, tokens: MemoryTokenStorage(access: 'A', refresh: 'R'));
    expect(base64Decode(_png), isNotEmpty);

    routerOf(tester).go('/doctor/patients/p-1/compare');
    await tester.pumpAndSettle();
    expect(server.paths, containsAll(['GET /analyses/a-1/image', 'GET /analyses/a-2/image']));
    expect(find.bySemanticsLabel('MRI image'), findsNWidgets(2));
    expect(find.bySemanticsLabel('MRI image not available'), findsNothing);

    server.calls.clear();
    routerOf(tester).go('/doctor/patients/p-1/analyses/a-1/report');
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('MRI image'), findsOneWidget);
  });
}
