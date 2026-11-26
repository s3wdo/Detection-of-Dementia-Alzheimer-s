import 'package:flutter_test/flutter_test.dart';
import 'package:neurosense/dev/fixtures/fixture_store.dart';
import 'package:neurosense/dev/fixtures/fixture_support_repositories.dart';
import 'package:neurosense/features/appointments/data/appointments_repository.dart';
import 'package:neurosense/features/appointments/data/models/appointment.dart';
import 'package:neurosense/features/counselling/data/models/counselling_models.dart';
import 'package:neurosense/features/counselling/data/safety_rules.dart';

void main() {
  group('counselling safety rules', () {
    test('classifies risky questions before anything else', () {
      expect(SafetyRules.classify('I want to end my life'), SafetyCategory.emergency);
      expect(SafetyRules.classify('He has chest pain right now'), SafetyCategory.emergency);
      expect(SafetyRules.classify('Can I stop taking my medication?'), SafetyCategory.medication);
      expect(SafetyRules.classify('What dose should I take?'), SafetyCategory.medication);
      expect(SafetyRules.classify("Do I have Alzheimer's?"), SafetyCategory.diagnosis);
      expect(SafetyRules.classify('How long do I have?'), SafetyCategory.diagnosis);
      expect(SafetyRules.classify('What does my latest MRI result mean?'), SafetyCategory.ownResult);
      expect(SafetyRules.classify('How can I support my mother?'), SafetyCategory.general);
    });

    test('medication question about my result is still treated as medication', () {
      expect(SafetyRules.classify('My report came back — should I stop my pills?'), SafetyCategory.medication);
    });
  });

  group('counselling prototype answers', () {
    late FixtureStore store;
    late FixtureCounsellingRepository repo;
    setUp(() {
      store = FixtureStore.generate(DateTime(2026, 10, 2, 9));
      repo = FixtureCounsellingRepository(store, replyDelay: Duration.zero);
    });

    test('"my result" uses only the released result and never clinical notes', () async {
      final r = await repo.ask('What does my latest MRI result mean?', patientId: 'p-1024');
      expect(r.kind, ReplyKind.answer);
      expect(r.text, contains('Early MCI'));
      expect(r.text, contains('not a diagnosis'));
      expect(r.text, isNot(contains('word-finding'))); // clinical note stays private
      expect(r.text, isNot(contains('64.7%'))); // unreleased result never used
    });

    test('a patient with no released result is told so', () async {
      final r = await repo.ask('What does my report say?', patientId: 'p-1031');
      expect(r.text, contains("don't have a reviewed result"));
    });

    test('medication and emergency questions get fixed safe replies', () async {
      expect((await repo.ask('Can I stop my medication?', patientId: 'p-1024')).kind, ReplyKind.referral);
      final e = await repo.ask('I think he is having a stroke', patientId: 'p-1024');
      expect(e.kind, ReplyKind.emergency);
      expect(e.text, contains('emergency number'));
    });

    test('general questions point to an approved article', () async {
      final r = await repo.ask('Tips for supporting a family member?', patientId: 'p-1024');
      expect(r.sources, contains('Supporting a family member'));
    });
  });

  group('appointments', () {
    late FixtureStore store;
    late FixtureAppointmentsRepository repo;
    setUp(() {
      store = FixtureStore.generate(DateTime.now());
      repo = FixtureAppointmentsRepository(store);
    });

    test('request validation', () {
      final now = DateTime.now();
      expect(AppointmentRequest(patientId: 'p', reason: '', startsAt: now.add(const Duration(days: 1))).validate(now),
          contains('reason'));
      expect(
          AppointmentRequest(patientId: 'p', reason: 'Follow-up', startsAt: now.subtract(const Duration(hours: 1)))
              .validate(now),
          contains('startsAt'));
    });

    test('a request is created as "requested" and notifies the doctor', () async {
      final a = await repo.request(AppointmentRequest(
        patientId: 'p-1024',
        reason: 'Results discussion',
        startsAt: DateTime.now().add(const Duration(days: 3)),
      ));
      expect(a.status, AppointmentStatus.requested);
      expect(store.notifications.any((n) => n.title.contains('Appointment requested — Sarah Johnson')), isTrue);
    });

    test('confirm, reschedule and cancel', () async {
      expect((await repo.setStatus('ap-2', AppointmentStatus.confirmed)).status, AppointmentStatus.confirmed);
      final later = DateTime.now().add(const Duration(days: 10));
      expect((await repo.reschedule('ap-2', later)).startsAt, later);
      await expectLater(repo.reschedule('ap-2', DateTime(2000)), throwsArgumentError);
      expect((await repo.setStatus('ap-2', AppointmentStatus.cancelled)).status, AppointmentStatus.cancelled);
    });
  });

  group('messages', () {
    test('send, read state and doctor inbox', () async {
      final store = FixtureStore.generate(DateTime.now());
      final repo = FixtureMessagesRepository(store);

      final inbox = await repo.threadsForDoctor();
      final robert = inbox.firstWhere((t) => t.patientName == 'Robert Smith');
      expect(robert.unread, 1);
      await repo.markThreadRead('p-1031', readerIsDoctor: true);
      expect((await repo.threadsForDoctor()).firstWhere((t) => t.patientName == 'Robert Smith').unread, 0);

      await repo.send(
          patientId: 'p-1024', body: 'Thank you, see you then.', fromDoctor: false, senderName: 'Sarah Johnson');
      expect((await repo.thread('p-1024')).last.body, 'Thank you, see you then.');
      await expectLater(repo.send(patientId: 'p-1024', body: '   ', fromDoctor: false, senderName: 'Sarah Johnson'),
          throwsArgumentError);
    });
  });
}
