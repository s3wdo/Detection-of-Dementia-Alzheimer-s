import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosense/core/widgets/app_button.dart';
import 'package:neurosense/core/widgets/badges.dart';
import 'package:neurosense/core/widgets/disclaimer_banner.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('SourceBadge keeps AI output and doctor review visibly different', (tester) async {
    await tester.pumpWidget(_wrap(const Column(children: [
      SourceBadge(InfoSource.ai),
      SourceBadge(InfoSource.doctor, doctorName: 'Dr. Ahmed Khan'),
    ])));
    expect(find.text('AI MODEL OUTPUT'), findsOneWidget);
    expect(find.text('REVIEWED BY DR. AHMED KHAN'), findsOneWidget);
    // Screen readers get the readable label, not the uppercase styling.
    expect(find.bySemanticsLabel('AI model output'), findsOneWidget);
  });

  testWidgets('StatusBadge shows the right wording', (tester) async {
    await tester.pumpWidget(_wrap(const Column(children: [
      StatusBadge(StatusKind.awaitingConfirmation),
      StatusBadge(StatusKind.released),
    ])));
    expect(find.text('Awaiting confirmation'), findsOneWidget);
    expect(find.text('Released to patient'), findsOneWidget);
  });

  testWidgets('DisclaimerBanner states that AI output is not a diagnosis', (tester) async {
    await tester.pumpWidget(_wrap(const DisclaimerBanner()));
    expect(find.textContaining('not a medical diagnosis'), findsOneWidget);
  });

  testWidgets('AppButton ignores taps and shows a spinner while loading', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(AppButton(label: 'Save', loading: true, onPressed: () => taps++)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    expect(taps, 0);

    await tester.pumpWidget(_wrap(AppButton(label: 'Save', onPressed: () => taps++)));
    await tester.tap(find.text('Save'));
    expect(taps, 1);
  });
}
