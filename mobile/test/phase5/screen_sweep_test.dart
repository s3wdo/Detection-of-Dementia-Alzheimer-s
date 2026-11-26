import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Phase 5 quality sweep: every screen is opened on a small phone, at normal
/// and at 200 % text size, and must lay out without overflow or other errors.
/// At normal size each screen must also meet Flutter's accessibility guidelines.

final _log = StringBuffer();
const _nl = '\n';

const doctorRoutes = [
  '/doctor/dashboard',
  '/doctor/patients',
  '/doctor/patients/p-1024',
  '/doctor/patients/p-1024/timeline',
  '/doctor/patients/p-1024/compare',
  '/doctor/patients/p-1024/upload',
  '/doctor/patients/p-1024/analyses/a-1024-3',
  '/doctor/patients/p-1024/analyses/a-1024-3/explainability',
  '/doctor/patients/p-1024/progress/a-1024-3',
  '/doctor/patients/p-1024/analyses/a-1024-3/report',
  '/doctor/patients/p-1031/analyses/a-1031-1',
  '/doctor/patients/p-1031/analyses/a-1031-1/review',
  '/doctor/appointments',
  '/doctor/appointments/ap-2',
  '/doctor/profile',
  '/doctor/profile/personal',
  '/doctor/profile/health',
  '/doctor/profile/notification-preferences',
  '/doctor/profile/security',
  '/doctor/profile/help',
  '/doctor/notifications',
  '/doctor/messages',
  '/doctor/messages/p-1024',
];

const patientRoutes = [
  '/patient/home',
  '/patient/history',
  '/patient/counselling',
  '/patient/counselling/chat',
  '/patient/counselling/resources',
  '/patient/counselling/resources/understanding-your-results',
  '/patient/profile',
  '/patient/profile/personal',
  '/patient/profile/health',
  '/patient/profile/notification-preferences',
  '/patient/profile/security',
  '/patient/profile/help',
  '/patient/notifications',
  '/patient/messages',
  '/patient/appointments',
  '/patient/appointments/new',
  '/patient/appointments/ap-1',
  '/patient/reports',
  '/patient/upload',
  '/patient/reports/a-1024-3',
  '/patient/compare',
  '/patient/results/a-1024-3',
  '/patient/results/a-1024-3/explainability',
];

/// A small Android phone (360 × 740 dp).
void _smallPhone(WidgetTester tester, {double textScale = 1}) {
  tester.view.physicalSize = const Size(1080, 2220);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Opens every route and returns the problems found, one line per route.
Future<List<String>> _sweep(
  WidgetTester tester, {
  required bool doctor,
  required List<String> routes,
  bool checkGuidelines = false,
}) async {
  final problems = <String>[];
  final original = FlutterError.onError;
  String? current;
  FlutterError.onError = (details) {
    final first = details.exceptionAsString().split('\n').first;
    problems.add('$current → $first');
    _log
      ..writeln('===== $current')
      ..writeln(details.toString());
  };
  try {
    await pumpApp(tester, demo: true);
    await enterDemo(tester, doctor: doctor);
    for (final r in routes) {
      current = r;
      routerOf(tester).go(r);
      try {
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle(
            const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
      } on FlutterError catch (e) {
        problems.add('$r → never settles: ${e.message.split(_nl).first}');
        continue;
      }
      if (find.byType(ErrorWidget).evaluate().isNotEmpty) problems.add('$r → error widget shown');
      if (checkGuidelines) {
        for (final (name, guideline) in [
          ('tap target', androidTapTargetGuideline),
          ('label', labeledTapTargetGuideline),
          ('contrast', textContrastGuideline),
        ]) {
          final result = await guideline.evaluate(tester);
          if (!result.passed) problems.add('$r → $name: ${result.reason?.split(_nl).take(3).join(' | ')}');
        }
      }
    }
  } catch (e, st) {
    problems.add('$current → test stopped: ${e.toString().split(_nl).first}');
    _log
      ..writeln('STOPPED $e')
      ..writeln(st);
  } finally {
    FlutterError.onError = original;
    File('build/sweep_details.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync(_log.toString(), mode: FileMode.append);
    _log.clear();
  }
  return problems;
}

void main() {
  for (final doctor in [true, false]) {
    final role = doctor ? 'doctor' : 'patient';
    final routes = doctor ? doctorRoutes : patientRoutes;

    testWidgets('$role screens: small phone, accessibility guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      _smallPhone(tester);
      final problems = await _sweep(tester, doctor: doctor, routes: routes, checkGuidelines: true);
      handle.dispose();
      expect(problems, isEmpty, reason: problems.join('\n'));
    });

    testWidgets('$role screens: 200 % text size has no overflow', (tester) async {
      _smallPhone(tester, textScale: 2);
      final problems = await _sweep(tester, doctor: doctor, routes: routes);
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  }
}
