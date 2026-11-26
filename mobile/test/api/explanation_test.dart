import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosense/core/network/api_clinical_repositories.dart';
import 'package:neurosense/features/explainability/widgets/explainability_panel.dart';

import 'fakes.dart';

// A 1 x 1 transparent PNG, enough for Image.memory.
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

ApiAnalysesRepository _analyses(FakeServer server) =>
    ApiAnalysesRepository(clientFor(server, MemoryTokenStorage(access: 'A')), prepareImage: (bytes) async => bytes);

void main() {
  test('the Grad-CAM map comes from the server and is decoded', () async {
    final server = FakeServer((c) => (200, {
          'method': 'gradcam',
          'target_label': 'AD',
          'image_base64': base64Encode(_png),
          'heatmap_base64': base64Encode(_png),
          'width': 224,
          'height': 224,
        }));
    final explanation = await _analyses(server).explanationFor('a-1');
    expect(server.paths, ['GET /analyses/a-1/explanation']);
    expect(explanation!.method, 'gradcam');
    expect(explanation.targetLabel, 'AD');
    expect(explanation.heatmap, _png);
  });

  test('no map on the server means no map in the app', () async {
    final server = FakeServer((c) => error(404, 'NOT_FOUND', 'There is no explainability map for this result.'));
    expect(await _analyses(server).explanationFor('a-1'), isNull);
  });

  testWidgets('with a map the viewer offers the brain image, the map and an overlay', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: ExplainabilityPanel(image: _png, heatmap: _png, showOpacity: true))),
    ));
    expect(find.text('Brain'), findsOneWidget);
    expect(find.text('Heatmap'), findsOneWidget);
    await tester.tap(find.text('Overlay'));
    await tester.pumpAndSettle();
    expect(find.text('40%'), findsOneWidget); // same blend as the team's Grad-CAM script
    expect(find.text('Not available yet'), findsNothing);
  });
}
