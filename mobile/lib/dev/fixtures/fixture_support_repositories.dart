import '../../core/utils/formatters.dart';
import '../../features/appointments/data/appointments_repository.dart';
import '../../features/appointments/data/models/appointment.dart';
import '../../features/counselling/data/counselling_repository.dart';
import '../../features/counselling/data/models/counselling_models.dart';
import '../../features/counselling/data/safety_rules.dart';
import '../../features/diagnosis/data/analyses_repository.dart';
import '../../features/diagnosis/data/models/analysis.dart';
import '../../features/messages/data/messages_repository.dart';
import '../../features/messages/data/models/message.dart';
import '../../features/notifications/data/models/app_notification.dart';
import 'counselling_content.dart';
import 'demo_users.dart';
import 'fixture_store.dart';

// DEVELOPMENT ONLY: demo repositories for appointments, messages and counselling.

Future<void> _latency() => Future<void>.delayed(const Duration(milliseconds: 250));

class FixtureAppointmentsRepository implements AppointmentsRepository {
  FixtureAppointmentsRepository(this._store);
  final FixtureStore _store;

  List<Appointment> _sorted(Iterable<Appointment> list) =>
      list.toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  @override
  Future<List<Appointment>> listForDoctor() async {
    await _latency();
    return _sorted(_store.appointments);
  }

  @override
  Future<List<Appointment>> listForPatient(String patientId) async {
    await _latency();
    return _sorted(_store.appointments.where((a) => a.patientId == patientId));
  }

  @override
  Future<Appointment> get(String appointmentId) async {
    await _latency();
    final a = _store.appointments.where((x) => x.id == appointmentId).firstOrNull;
    if (a == null) throw const NotFoundException();
    return a;
  }

  @override
  Future<Appointment> request(AppointmentRequest request) async {
    await _latency();
    final errors = request.validate(DateTime.now());
    if (errors.isNotEmpty) throw ArgumentError(errors.values.first);
    final patient = _store.patientById(request.patientId);
    final created = Appointment(
      id: 'ap-${DateTime.now().millisecondsSinceEpoch}',
      patientId: patient.id,
      patientName: patient.fullName,
      doctorName: FixtureStore.doctorName,
      startsAt: request.startsAt,
      durationMinutes: 30,
      title: request.reason,
      status: AppointmentStatus.requested,
      location: 'Room 3B',
    );
    _store.appointments.add(created);
    _store.notifications.add(AppNotification(
      id: 'n-${created.id}',
      userId: demoDoctor.userId,
      kind: NotificationKind.appointment,
      title: 'Appointment requested — ${patient.fullName}',
      body: '${request.reason} on ${Fmt.dateTime(request.startsAt)}.',
      createdAt: DateTime.now(),
      read: false,
      route: '/doctor/appointments/${created.id}',
    ));
    return created;
  }

  Appointment _update(String id, Appointment Function(Appointment a) change) {
    final i = _store.appointments.indexWhere((a) => a.id == id);
    if (i < 0) throw const NotFoundException();
    final updated = change(_store.appointments[i]);
    _store.appointments[i] = updated;
    return updated;
  }

  @override
  Future<Appointment> setStatus(String appointmentId, AppointmentStatus status) async {
    await _latency();
    return _update(appointmentId, (a) => a.copyWith(status: status));
  }

  @override
  Future<Appointment> reschedule(String appointmentId, DateTime startsAt) async {
    await _latency();
    if (!startsAt.isAfter(DateTime.now())) throw ArgumentError('Choose a time in the future.');
    return _update(appointmentId, (a) => a.copyWith(startsAt: startsAt, status: AppointmentStatus.confirmed));
  }
}

class FixtureMessagesRepository implements MessagesRepository {
  FixtureMessagesRepository(this._store);
  final FixtureStore _store;

  List<Message> _thread(String patientId) =>
      _store.messages.where((m) => m.patientId == patientId).toList()..sort((a, b) => a.sentAt.compareTo(b.sentAt));

  @override
  Future<List<MessageThread>> threadsForDoctor() async {
    await _latency();
    final threads = <MessageThread>[];
    for (final id in _store.messages.map((m) => m.patientId).toSet()) {
      final list = _thread(id);
      threads.add(MessageThread(
        patientId: id,
        patientName: _store.patientById(id).fullName,
        last: list.last,
        unread: list.where((m) => !m.fromDoctor && !m.read).length,
      ));
    }
    threads.sort((a, b) => b.last.sentAt.compareTo(a.last.sentAt));
    return threads;
  }

  @override
  Future<List<Message>> thread(String patientId) async {
    await _latency();
    return _thread(patientId);
  }

  @override
  Future<Message> send({
    required String patientId,
    required String body,
    required bool fromDoctor,
    required String senderName,
    String? linkedTo,
  }) async {
    await _latency();
    if (body.trim().isEmpty) throw ArgumentError('Write a message first.');
    final msg = Message(
      id: 'm-${DateTime.now().microsecondsSinceEpoch}',
      patientId: patientId,
      fromDoctor: fromDoctor,
      senderName: senderName,
      body: body.trim(),
      sentAt: DateTime.now(),
      linkedTo: linkedTo,
    );
    _store.messages.add(msg);
    // Notify the other side (the demo only has one patient account).
    if (!fromDoctor || patientId == demoPatient.patientId) {
      _store.notifications.add(AppNotification(
        id: 'n-${msg.id}',
        userId: fromDoctor ? demoPatient.userId : demoDoctor.userId,
        kind: NotificationKind.message,
        title: fromDoctor ? 'New message from $senderName' : 'New message — $senderName',
        body: msg.body,
        createdAt: msg.sentAt,
        read: false,
        route: fromDoctor ? '/patient/messages' : '/doctor/messages/$patientId',
      ));
    }
    return msg;
  }

  @override
  Future<void> markThreadRead(String patientId, {required bool readerIsDoctor}) async {
    for (var i = 0; i < _store.messages.length; i++) {
      final m = _store.messages[i];
      // The reader marks the messages sent by the other side.
      if (m.patientId == patientId && m.fromDoctor != readerIsDoctor && !m.read) {
        _store.messages[i] = m.copyWith(read: true);
      }
    }
  }
}

/// Counselling prototype: predefined answers only — no LLM.
/// Every question passes through [SafetyRules] first.
///
/// It runs inside the app in both modes. With the real server, pass
/// [releasedResults] so "my result" answers use the patient's released result
/// from the API instead of demo data.
class FixtureCounsellingRepository implements CounsellingRepository {
  FixtureCounsellingRepository(
    this._store, {
    this.replyDelay = const Duration(milliseconds: 700),
    this.releasedResults,
  });
  final FixtureStore _store;
  final Duration replyDelay;

  /// The patient's released results, newest first (patient-visible fields only).
  final Future<List<AnalysisSummary>> Function(String patientId)? releasedResults;

  @override
  Future<List<Resource>> resources() async {
    await _latency();
    return counsellingResources;
  }

  @override
  Future<Resource> resource(String slug) async {
    await _latency();
    final r = counsellingResources.where((r) => r.slug == slug).firstOrNull;
    if (r == null) throw const NotFoundException();
    return r;
  }

  @override
  Future<CounsellingReply> ask(String question, {required String patientId}) async {
    await Future<void>.delayed(replyDelay);
    return switch (SafetyRules.classify(question)) {
      SafetyCategory.emergency => const CounsellingReply(text: SafetyRules.emergencyReply, kind: ReplyKind.emergency),
      SafetyCategory.medication => const CounsellingReply(text: SafetyRules.medicationReply, kind: ReplyKind.referral),
      SafetyCategory.diagnosis => const CounsellingReply(
          text: SafetyRules.diagnosisReply,
          kind: ReplyKind.referral,
          sources: ['Questions to ask your doctor'],
        ),
      SafetyCategory.ownResult => await _ownResultReply(patientId),
      SafetyCategory.general => _generalReply(question),
    };
  }

  /// Uses only the latest RELEASED result and only patient-visible fields.
  Future<CounsellingReply> _ownResultReply(String patientId) async {
    final released = releasedResults != null
        ? await releasedResults!(patientId)
        : _store.analysesOf(patientId).where((a) => a.released).map((a) => a.forPatient()).toList();
    if (released.isEmpty) {
      return const CounsellingReply(
        text: "You don't have a reviewed result yet. Results appear here after your doctor has reviewed and "
            'released them.',
        kind: ReplyKind.answer,
      );
    }
    final a = released.first;
    final finalClass = (a.finalClass ?? a.predicted).label;
    final sameAsAi = a.finalClass == null || a.finalClass == a.predicted;
    final text = StringBuffer()
      ..write('Your latest released result is from ${Fmt.date(a.createdAt)}. ')
      ..write('${a.reviewedBy ?? 'Your doctor'} reviewed it and recorded the classification "$finalClass". ')
      ..write(sameAsAi
          ? 'The AI model gave the same classification. '
          : 'The AI model had suggested "${a.predicted.label}", and your doctor decided differently after review. ')
      ..write('The AI result is a support tool for your doctor. It is not a diagnosis and not the chance that '
          'you have a condition. ');
    if (a.patientSummary != null) text.write('Your doctor wrote: "${a.patientSummary}" ');
    text.write('Please talk to your doctor about what it means for you.');
    return CounsellingReply(
      text: text.toString(),
      kind: ReplyKind.answer,
      sources: const ['Your released report', 'Understanding your MRI analysis'],
    );
  }

  CounsellingReply _generalReply(String question) {
    final q = question.toLowerCase();
    Resource? best;
    var bestScore = 0;
    for (final r in counsellingResources) {
      final score = r.keywords.where(q.contains).length;
      if (score > bestScore) {
        best = r;
        bestScore = score;
      }
    }
    if (best == null) {
      return const CounsellingReply(
        text: 'I can share general information about memory problems and dementia, MRI scans, your released '
            'results, preparing for appointments, supporting a family member and brain health. '
            'Could you ask about one of these?',
        kind: ReplyKind.answer,
      );
    }
    return CounsellingReply(
        text: '${best.summary} ${best.sections.first.body}', kind: ReplyKind.answer, sources: [best.title]);
  }
}
