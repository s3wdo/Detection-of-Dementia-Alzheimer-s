import 'dart:typed_data';

import '../../core/models/info_source.dart';
import '../../core/utils/formatters.dart';
import '../../features/appointments/data/models/appointment.dart';
import '../../features/diagnosis/data/models/analysis.dart';
import '../../features/diagnosis/data/models/model_class.dart';
import '../../features/messages/data/models/message.dart';
import '../../features/notifications/data/models/app_notification.dart';
import '../../features/patients/data/models/patient.dart';
import '../../features/timeline/data/models/timeline_event.dart';
import 'demo_users.dart';
import '../../features/patients/data/models/doctor_note.dart';

/// FICTIONAL demo data for development only. All people and records are made up.
/// Dates are generated relative to "now" so the demo always looks current.
class FixtureStore {
  FixtureStore._(this.now, this.patients, this.analyses, this.appointments, this.messages, this.notifications);

  final DateTime now;
  final List<Patient> patients; // without latestAnalysis; repositories attach it
  final List<AnalysisSummary> analyses;
  final List<Appointment> appointments;
  final List<Message> messages;
  final List<AppNotification> notifications; // mutable read state

  /// Doctor-only notes per patient (seeded from review notes).
  late final List<DoctorNote> notes = [
    for (final a in analyses)
      if (a.clinicalNotes != null)
        DoctorNote(
          id: 'note-${a.id}',
          patientId: a.patientId,
          author: doctorName,
          body: a.clinicalNotes!,
          createdAt: a.reviewedAt ?? a.createdAt,
        ),
  ];

  /// Uploaded MRI images, by analysis id (demo uploads only).
  final Map<String, Uint8List> images = {};

  /// Analyses still "running" — hidden from lists until they complete.
  final Set<String> pendingAnalysisIds = {};

  /// Current pipeline step of each running simulated analysis.
  final Map<String, int> jobSteps = {};

  /// Scans the demo patient uploaded themselves, newest first.
  final List<({String analysisId, DateTime at})> patientUploads = [];

  static const doctorName = 'Dr. Ahmed Khan';

  factory FixtureStore.generate(DateTime now) {
    DateTime ago(int days, [int hour = 10, int minute = 0]) =>
        DateTime(now.year, now.month, now.day, hour, minute).subtract(Duration(days: days));
    DateTime inDays(int days, int hour, [int minute = 0]) =>
        DateTime(now.year, now.month, now.day, hour, minute).add(Duration(days: days));

    Patient p(String id, String mrn, String name, DateTime dob, Sex sex, String contact) => Patient(
          id: id,
          mrn: mrn,
          fullName: name,
          dateOfBirth: dob,
          sex: sex,
          phone: '+971 50 000 ${mrn.substring(2)}',
          email: '${name.toLowerCase().replaceAll(' ', '.')}@example.com',
          emergencyContact: contact,
        );

    final patients = [
      p('p-1024', 'P-1024', 'Sarah Johnson', DateTime(1958, 3, 12), Sex.female, 'Daniel Johnson (son)'),
      p('p-1031', 'P-1031', 'Robert Smith', DateTime(1951, 7, 4), Sex.male, 'Mary Smith (wife)'),
      p('p-1047', 'P-1047', 'Emily Davis', DateTime(1960, 11, 23), Sex.female, 'Tom Davis (husband)'),
      p('p-1052', 'P-1052', 'Michael Chen', DateTime(1955, 1, 30), Sex.male, 'Grace Chen (daughter)'),
      p('p-1063', 'P-1063', 'Aisha Rahman', DateTime(1949, 9, 8), Sex.female, 'Yusuf Rahman (son)'),
      p('p-1071', 'P-1071', 'Omar Haddad', DateTime(1947, 5, 17), Sex.male, 'Layla Haddad (wife)'),
      p('p-1088', 'P-1088', 'Lina Saleh', DateTime(1962, 2, 2), Sex.female, 'Karim Saleh (brother)'),
      p('p-1093', 'P-1093', 'James Carter', DateTime(1953, 12, 19), Sex.male, 'Anna Carter (wife)'),
    ];

    AnalysisSummary a(String id, String pid, DateTime at, ModelClass c, double conf,
            {bool reviewed = false,
            ModelClass? finalClass,
            bool released = false,
            String? reason,
            String? notes,
            String? summary}) =>
        AnalysisSummary(
          id: id,
          patientId: pid,
          createdAt: at,
          predicted: c,
          confidence: conf,
          status: reviewed
              ? (finalClass != null && finalClass != c ? ReviewStatus.overridden : ReviewStatus.confirmed)
              : (conf < 0.80 ? ReviewStatus.pendingReview : ReviewStatus.awaitingConfirmation),
          released: released,
          finalClass: reviewed ? (finalClass ?? c) : null,
          reviewedBy: reviewed ? doctorName : null,
          reviewedAt: reviewed ? at.add(const Duration(hours: 20)) : null,
          overrideReason: reason,
          clinicalNotes: notes,
          patientSummary: summary,
          probabilities: spreadProbabilities(c, conf),
          simulated: true,
        );

    final analyses = [
      a('a-1024-3', 'p-1024', ago(17, 14, 32), ModelClass.earlyMci, 0.914,
          reviewed: true,
          released: true,
          notes:
              'Family reports occasional word-finding difficulty. Correlate with cognitive assessment at next visit.',
          summary:
              'Your MRI analysis has been reviewed. We will go through the result and next steps together at your appointment.'),
      a('a-1024-2', 'p-1024', ago(145, 11, 5), ModelClass.cognitivelyNormal, 0.782,
          reviewed: true,
          released: true,
          notes: 'Low model confidence; reviewed with the full scan series.',
          summary: 'Your MRI analysis was reviewed. No changes to your care plan are needed now.'),
      a('a-1024-1', 'p-1024', ago(255, 9, 40), ModelClass.earlyMci, 0.647),
      a('a-1031-1', 'p-1031', ago(2, 8, 47), ModelClass.lateMci, 0.726),
      a('a-1047-1', 'p-1047', ago(3, 17, 30), ModelClass.cognitivelyNormal, 0.883),
      a('a-1063-1', 'p-1063', ago(30, 13, 15), ModelClass.cognitivelyNormal, 0.951,
          reviewed: true, released: true, summary: 'Your MRI analysis has been reviewed.'),
      a('a-1071-1', 'p-1071', ago(6, 15, 0), ModelClass.alzheimersDisease, 0.840),
      a('a-1088-1', 'p-1088', ago(45, 10, 20), ModelClass.earlyMci, 0.699,
          reviewed: true,
          finalClass: ModelClass.lateMci,
          released: true,
          reason: 'Clinical picture and cognitive screening are more consistent with Late MCI.',
          notes: 'MoCA 19/30. Override documented.',
          summary: 'Your doctor reviewed the AI result and recorded a final classification.'),
      a('a-1093-1', 'p-1093', ago(4, 12, 10), ModelClass.lateMci, 0.815),
    ];

    Appointment ap(String id, String pid, String name, DateTime at, String title, AppointmentStatus st,
            [int min = 30]) =>
        Appointment(
          id: id,
          patientId: pid,
          patientName: name,
          doctorName: doctorName,
          startsAt: at,
          durationMinutes: min,
          title: title,
          status: st,
          location: 'Room 3B',
        );

    final appointments = [
      ap('ap-1', 'p-1024', 'Sarah Johnson', inDays(2, 10), 'Neurology consultation', AppointmentStatus.confirmed),
      ap('ap-2', 'p-1031', 'Robert Smith', inDays(3, 14), 'Results discussion', AppointmentStatus.requested),
      ap('ap-3', 'p-1047', 'Emily Davis', inDays(5, 11, 30), 'Follow-up review', AppointmentStatus.confirmed, 20),
      ap('ap-4', 'p-1052', 'Michael Chen', inDays(1, 9), 'Initial assessment', AppointmentStatus.requested, 45),
      ap('ap-5', 'p-1024', 'Sarah Johnson', ago(18, 9), 'MRI scan', AppointmentStatus.completed, 45),
    ];

    Message m(String id, String pid, bool fromDoctor, String sender, String body, DateTime at, {bool read = true}) =>
        Message(id: id, patientId: pid, fromDoctor: fromDoctor, senderName: sender, body: body, sentAt: at, read: read);

    final messages = [
      m('m-1', 'p-1024', true, doctorName,
          'Please bring a list of your current medications and, if possible, a family member.', ago(21, 9, 30)),
      m('m-2', 'p-1024', false, 'Sarah Johnson', 'Thank you. Should I bring my previous scan reports too?',
          ago(20, 18, 2)),
      m('m-3', 'p-1024', true, doctorName,
          'Your results are ready. We will go through them together at your appointment.', ago(14, 16, 5),
          read: false),
      m('m-4', 'p-1031', false, 'Robert Smith', 'When will my MRI results be ready?', ago(1, 19, 40), read: false),
      m('m-5', 'p-1047', true, doctorName, 'Your scan was received. I will review it this week.', ago(3, 18, 0)),
    ];

    AppNotification n(String id, String user, NotificationKind k, String title, String body, DateTime at,
            {bool read = false, String? route}) =>
        AppNotification(
            id: id, userId: user, kind: k, title: title, body: body, createdAt: at, read: read, route: route);

    final doctorId = demoDoctor.userId;
    final patientId = demoPatient.userId;
    final notifications = [
      n('n-d1', doctorId, NotificationKind.review, 'Review pending — Robert Smith',
          'AI result below the 0.80 confidence threshold is waiting for your review.', ago(2, 8, 50),
          route: '/doctor/patients/p-1031/analyses/a-1031-1'),
      n('n-d2', doctorId, NotificationKind.analysis, 'Analysis completed — Emily Davis',
          'An AI analysis is ready for your confirmation.', ago(3, 17, 35),
          route: '/doctor/patients/p-1047/analyses/a-1047-1'),
      n('n-d3', doctorId, NotificationKind.appointment, 'Appointment requested — Michael Chen',
          'Initial assessment on ${Fmt.dateTime(inDays(1, 9))}.', ago(1, 11, 5),
          route: '/doctor/appointments/ap-4'),
      n('n-d4', doctorId, NotificationKind.analysis, 'Analysis completed — Omar Haddad',
          'An AI analysis is ready for your confirmation.', ago(6, 15, 5),
          read: true, route: '/doctor/patients/p-1071/analyses/a-1071-1'),
      n('n-p1', patientId, NotificationKind.review, 'Your MRI result has been reviewed',
          'Dr. Ahmed Khan reviewed your analysis from ${Fmt.date(ago(17))}.', ago(16, 10, 20),
          route: '/patient/results/a-1024-3'),
      n('n-p2', patientId, NotificationKind.message, 'New message from Dr. Ahmed Khan',
          'Your results are ready. We will go through them together…', ago(14, 16, 5),
          route: '/patient/messages'),
      n('n-p3', patientId, NotificationKind.appointment, 'Appointment reminder',
          'Neurology consultation on ${Fmt.dateTime(inDays(2, 10))}.', ago(0, 8, 0),
          route: '/patient/appointments/ap-1'),
      n('n-p4', patientId, NotificationKind.appointment, 'Appointment confirmed',
          'Neurology consultation with Dr. Ahmed Khan.', ago(20, 12, 0),
          read: true, route: '/patient/appointments/ap-1'),
    ];

    return FixtureStore._(now, patients, analyses, appointments, messages, notifications);
  }

  /// Demo scores for all four classes: the predicted class gets [confidence],
  /// the rest is shared out in fixed proportions. (Not model output.)
  static Map<ModelClass, double> spreadProbabilities(ModelClass predicted, double confidence) {
    const weights = [0.55, 0.30, 0.15];
    final others = ModelClass.values.where((c) => c != predicted).toList();
    final rest = 1 - confidence;
    return {
      predicted: confidence,
      for (var i = 0; i < others.length; i++) others[i]: double.parse((rest * weights[i]).toStringAsFixed(3)),
    };
  }

  void replaceAnalysis(AnalysisSummary updated) {
    final i = analyses.indexWhere((a) => a.id == updated.id);
    analyses[i] = updated;
  }

  /// Tells the demo doctor that a simulated analysis has finished.
  void notifyAnalysisCompleted(String analysisId) {
    final a = analyses.firstWhere((x) => x.id == analysisId);
    notifications.add(AppNotification(
      id: 'n-done-$analysisId',
      userId: demoDoctor.userId,
      kind: NotificationKind.analysis,
      title: 'Analysis completed — ${patientById(a.patientId).fullName}',
      body: 'A simulated AI analysis is ready for your review.',
      createdAt: DateTime.now(),
      read: false,
      route: '/doctor/patients/${a.patientId}/analyses/$analysisId',
    ));
  }

  /// Adds a notification for the demo patient when one of their results is released.
  void notifyResultReleased(AnalysisSummary a) {
    if (a.patientId != demoPatient.patientId) return;
    notifications.add(AppNotification(
      id: 'n-release-${a.id}',
      userId: demoPatient.userId,
      kind: NotificationKind.review,
      title: 'Your MRI result has been reviewed',
      body: '$doctorName reviewed your analysis from ${Fmt.date(a.createdAt)}.',
      createdAt: DateTime.now(),
      read: false,
      route: '/patient/results/${a.id}',
    ));
  }

  // ---------------------------------------------------------------- queries

  List<AnalysisSummary> analysesOf(String patientId) =>
      analyses.where((x) => x.patientId == patientId && !pendingAnalysisIds.contains(x.id)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Patient patientById(String id) => patients.firstWhere((p) => p.id == id);

  /// Timeline built from analyses, reviews, appointments and doctor messages.
  /// [patientView] applies the release rule the backend will enforce.
  List<TimelineEvent> timelineOf(String patientId, {required bool patientView}) {
    final name = patientById(patientId).fullName;
    final events = <TimelineEvent>[];

    for (final x in analysesOf(patientId)) {
      if (patientView && !x.released) continue;
      events.add(TimelineEvent(
        id: '${x.id}-ai',
        patientId: patientId,
        patientName: name,
        at: x.createdAt,
        kind: TimelineKind.mriAnalysis,
        source: InfoSource.ai,
        title: 'MRI analysis',
        // Patients are not shown the model's confidence score.
        detail: patientView
            ? x.predicted.label
            : '${x.predicted.label} · ${Fmt.percent(x.confidence)} model confidence',
        pending: !x.status.isReviewed,
      ));
      if (x.status.isReviewed) {
        final decision = x.status == ReviewStatus.overridden
            ? 'Final classification: ${x.finalClass!.label}'
            : 'AI result confirmed';
        events.add(TimelineEvent(
          id: '${x.id}-review',
          patientId: patientId,
          patientName: name,
          at: x.reviewedAt!,
          kind: TimelineKind.doctorReview,
          source: InfoSource.doctor,
          title: 'Doctor review',
          detail: 'Reviewed by ${x.reviewedBy} · $decision'
              '${!patientView && x.released ? ' · released to patient' : ''}',
        ));
      }
    }
    for (final ap in appointments.where((ap) => ap.patientId == patientId)) {
      events.add(TimelineEvent(
        id: '${ap.id}-appt',
        patientId: patientId,
        patientName: name,
        at: ap.startsAt,
        kind: TimelineKind.appointment,
        source: InfoSource.admin,
        title: ap.title,
        detail: '${Fmt.dateTime(ap.startsAt)} · ${ap.status.name[0].toUpperCase()}${ap.status.name.substring(1)}',
      ));
    }
    for (final m in messages.where((m) => m.patientId == patientId && m.fromDoctor)) {
      events.add(TimelineEvent(
        id: 'msg-${m.id}',
        patientId: patientId,
        patientName: name,
        at: m.sentAt,
        kind: TimelineKind.message,
        source: InfoSource.doctor,
        title: 'Message from ${m.senderName}',
        detail: m.body,
      ));
    }
    events.sort((a, b) => b.at.compareTo(a.at));
    return events;
  }
}
