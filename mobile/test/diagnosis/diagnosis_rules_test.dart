import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurosense/dev/fixtures/fixture_repositories.dart';
import 'package:neurosense/dev/fixtures/fixture_store.dart';
import 'package:neurosense/features/diagnosis/data/analyses_repository.dart';
import 'package:neurosense/features/diagnosis/data/models/analysis.dart';
import 'package:neurosense/features/diagnosis/data/models/analysis_job.dart';
import 'package:neurosense/features/diagnosis/data/models/model_class.dart';
import 'package:neurosense/features/diagnosis/data/models/mri_file.dart';
import 'package:neurosense/features/reviews/data/models/review_draft.dart';

final pngHeader = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3]);
final jpegHeader = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
const goodInspection = MriInspection(width: 512, height: 512, grayscaleRatio: 0.99);

void main() {
  group('MRI upload rules', () {
    test('format is detected from the file content, not the name', () {
      expect(MriFile(name: 'scan.png', bytes: pngHeader).format, MriFormat.png);
      expect(MriFile(name: 'scan.png', bytes: jpegHeader).format, MriFormat.jpeg);
      expect(MriFile(name: 'scan.png', bytes: Uint8List.fromList([1, 2, 3, 4])).format, MriFormat.unsupported);
    });

    test('a valid grayscale PNG passes every check', () {
      final checks = MriRules.check(MriFile(name: 'a.png', bytes: pngHeader), goodInspection);
      expect(checks.every((c) => c.status == CheckStatus.passed), isTrue);
      expect(MriRules.canAnalyze(checks), isTrue);
    });

    test('unsupported, too large or unreadable files cannot be analyzed', () {
      final pdf = MriFile(name: 'a.pdf', bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]));
      expect(MriRules.canAnalyze(MriRules.check(pdf, goodInspection)), isFalse);

      final big = Uint8List(MriRules.maxBytes + 1)..setRange(0, 8, pngHeader);
      expect(MriRules.canAnalyze(MriRules.check(MriFile(name: 'big.png', bytes: big), goodInspection)), isFalse);

      expect(MriRules.canAnalyze(MriRules.check(MriFile(name: 'a.png', bytes: pngHeader), null)), isFalse);
    });

    test('a colour image only gives a warning — the doctor decides', () {
      const colour = MriInspection(width: 512, height: 512, grayscaleRatio: 0.3);
      final checks = MriRules.check(MriFile(name: 'photo.jpg', bytes: jpegHeader), colour);
      expect(checks.last.status, CheckStatus.warning);
      expect(MriRules.canAnalyze(checks), isTrue);
    });
  });

  group('review validation', () {
    ReviewDraft draft({
      ReviewDecision decision = ReviewDecision.confirm,
      ModelClass? finalClass,
      String reason = '',
      String summary = '',
      bool release = false,
    }) =>
        ReviewDraft(
          analysisId: 'a',
          decision: decision,
          predicted: ModelClass.earlyMci,
          finalClass: finalClass,
          overrideReason: reason,
          patientSummary: summary,
          releaseToPatient: release,
        );

    test('confirm without release needs nothing else', () => expect(draft().validate(), isEmpty));

    test('override needs a different class and a reason', () {
      final errors = draft(decision: ReviewDecision.override).validate();
      expect(errors.keys, containsAll(['finalClass', 'overrideReason']));
      expect(
        draft(decision: ReviewDecision.override, finalClass: ModelClass.earlyMci, reason: 'long enough reason')
            .validate()
            .keys,
        contains('finalClass'),
      );
      expect(
        draft(decision: ReviewDecision.override, finalClass: ModelClass.lateMci, reason: 'long enough reason')
            .validate(),
        isEmpty,
      );
    });

    test('releasing needs a patient summary', () {
      expect(draft(release: true).validate().keys, contains('patientSummary'));
      expect(draft(release: true, summary: 'Reviewed.').validate(), isEmpty);
    });
  });

  group('simulated analysis and review (demo repositories)', () {
    late FixtureStore store;
    late FixtureAnalysesRepository analyses;
    late FixtureReviewsRepository reviews;
    setUp(() {
      store = FixtureStore.generate(DateTime(2026, 10, 2, 9));
      analyses = FixtureAnalysesRepository(store, stepDelay: const Duration(milliseconds: 400));
      reviews = FixtureReviewsRepository(store);
    });

    test('runs through every step, is marked simulated, and appears only when complete', () async {
      final id = await analyses.startAnalysis(patientId: 'p-1052', file: MriFile(name: 'a.png', bytes: pngHeader));
      expect(await analyses.listForPatient('p-1052', patientView: false), isEmpty); // still running

      final steps = await analyses.watchJob(id).map((j) => j.step).toList();
      expect(steps, [...AnalysisStep.visible, AnalysisStep.completed]);

      final list = await analyses.listForPatient('p-1052', patientView: false);
      expect(list.single.id, id);
      expect(list.single.simulated, isTrue);
      expect(list.single.probabilities.values.fold<double>(0, (a, b) => a + b), closeTo(1, 0.01));
      expect(await analyses.imageFor(id), pngHeader);
    });

    test('patients cannot open unreleased results; they can after release', () async {
      await expectLater(analyses.getAnalysis('a-1024-1', patientView: true), throwsA(isA<NotFoundException>()));

      await reviews.submitReview(
        const ReviewDraft(
          analysisId: 'a-1024-1',
          decision: ReviewDecision.confirm,
          predicted: ModelClass.earlyMci,
          clinicalNotes: 'private note',
          patientSummary: 'Reviewed with you at your visit.',
          releaseToPatient: true,
        ),
        doctorName: 'Dr. Ahmed Khan',
      );

      final seen = await analyses.getAnalysis('a-1024-1', patientView: true);
      expect(seen.status, ReviewStatus.confirmed);
      expect(seen.clinicalNotes, isNull); // stripped for patients
      expect(store.notifications.any((n) => n.id == 'n-release-a-1024-1'), isTrue);
    });

    test('an analysis cannot be reviewed twice', () async {
      const draft =
          ReviewDraft(analysisId: 'a-1031-1', decision: ReviewDecision.confirm, predicted: ModelClass.lateMci);
      await reviews.submitReview(draft, doctorName: 'Dr. Ahmed Khan');
      await expectLater(reviews.submitReview(draft, doctorName: 'Dr. Ahmed Khan'), throwsA(isA<ConflictException>()));
    });
  });
}
