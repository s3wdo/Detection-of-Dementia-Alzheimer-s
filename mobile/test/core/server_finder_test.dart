import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosense/core/network/server_finder.dart';

import '../helpers.dart';

void main() {
  group('server search rules', () {
    test('only private Wi-Fi ranges are searched', () {
      expect(isPrivateIpv4('192.168.1.178'), isTrue);
      expect(isPrivateIpv4('10.0.0.5'), isTrue);
      expect(isPrivateIpv4('172.20.1.1'), isTrue);
      expect(isPrivateIpv4('172.32.1.1'), isFalse);
      expect(isPrivateIpv4('8.8.8.8'), isFalse);
      expect(isPrivateIpv4('not an ip'), isFalse);
    });

    test('only a NeuroSense /health answer counts', () {
      expect(looksLikeNeuroSense({'status': 'ok', 'model': 'loaded'}), isTrue);
      expect(looksLikeNeuroSense({'status': 'ok'}), isFalse);
      expect(looksLikeNeuroSense('<html>router</html>'), isFalse);
      expect(looksLikeNeuroSense(null), isFalse);
    });

    test('scan finds the one host that answers and reports progress', () async {
      final seen = <int>[];
      final host = await scanHosts(
        ['192.168.1'],
        (h) async {
          if (h == '192.168.1.40') throw Exception('refused');
          return h == '192.168.1.178';
        },
        onProgress: (done, total) {
          expect(total, 254);
          seen.add(done);
        },
      );
      expect(host, '192.168.1.178');
      expect(seen, isNotEmpty);
    });

    test('scan returns null when nothing answers', () async {
      var calls = 0;
      final host = await scanHosts(['10.0.0'], (_) async {
        calls++;
        return false;
      });
      expect(host, isNull);
      expect(calls, 254);
    });
  });

  group('Find server button', () {
    Future<void> openDialog(WidgetTester tester, ServerFinder finder) async {
      await pumpApp(tester, demo: false, overrides: [serverFinderProvider.overrideWithValue(finder)]);
      routerOf(tester).go('/login');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('serverAddress')));
      await tester.pumpAndSettle();
    }

    testWidgets('fills in the found server and saves it', (tester) async {
      final result = Completer<String?>();
      await openDialog(tester, (progress) {
        progress(100, 254);
        return result.future;
      });
      await tester.tap(find.byKey(const Key('findServerButton')));
      await tester.pump();
      expect(find.text('Checked 100 of 254 addresses'), findsOneWidget);

      result.complete('192.168.1.178');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('serverFound')), findsOneWidget);
      expect(find.widgetWithText(TextField, '192.168.1.178'), findsOneWidget);

      await tester.tap(find.byKey(const Key('saveServerButton')));
      await tester.pumpAndSettle();
      expect(find.text('Server: http://192.168.1.178:8000/api/v1'), findsOneWidget);
    });

    testWidgets('says so when no server is found and keeps the old address', (tester) async {
      await openDialog(tester, (_) async => null);
      await tester.tap(find.byKey(const Key('findServerButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('serverNotFound')), findsOneWidget);
      expect(find.widgetWithText(TextField, 'http://test.invalid/api/v1'), findsOneWidget);
    });
  });
}
