import 'dart:async';
import 'dart:typed_data';

import '../../core/auth/session.dart';
import '../../core/utils/formatters.dart';
import '../../features/dashboard/data/dashboard_repository.dart';
import '../../features/dashboard/data/models/dashboards.dart';
import '../../features/diagnosis/data/analyses_repository.dart';
import '../../features/diagnosis/data/models/analysis.dart';
import '../../features/diagnosis/data/models/analysis_job.dart';
import '../../features/diagnosis/data/models/explanation.dart';
import '../../features/diagnosis/data/models/model_class.dart';
import '../../features/diagnosis/data/models/mri_file.dart';
import '../../features/diagnosis/data/models/upload_models.dart';
import '../../features/notifications/data/models/app_notification.dart';
import '../../features/notifications/data/notifications_repository.dart';
import '../../features/patients/data/models/patient.dart';
import '../../features/patients/data/patients_repository.dart';
import '../../features/profile/data/profile_repository.dart';
import '../../features/reviews/data/models/review_draft.dart';
import '../../features/reviews/data/reviews_repository.dart';
import '../../features/timeline/data/models/timeline_event.dart';
import '../../features/timeline/data/timeline_repository.dart';
import 'demo_users.dart';
import 'fixture_store.dart';
import '../../core/data/not_connected.dart';
import '../../features/patients/data/models/doctor_note.dart';

// DEVELOPMENT ONLY: repositories backed by the fictional FixtureStore.
// They apply the same visibility rules the backend will enforce, so the UI
// behaves the same once real API repositories replace them.

/// Short artificial delay so loading states are visible in demos.
Future<void> _latency() => Future<void>.delayed(const Duration(milliseconds: 250));

class FixturePatientsRepository implements PatientsRepository {
  FixturePatientsRepository(this._store);
  final FixtureStore _store;

  Patient _withLatest(Patient p) {
    final list = _store.analysesOf(p.id);
    return Patient(
      id: p.id,
      mrn: p.mrn,
      fullName: p.fullName,
      dateOfBirth: p.dateOfBirth,
      sex: p.sex,
      phone: p.phone,
      email: p.email,
      emergencyContact: p.emergencyContact,
      latestAnalysis: list.isEmpty ? null : list.first,
    );
  }

  @override
  Future<List<Patient>> listAssigned(PatientQuery query) async {
    await _latency();
    final result = _store.patients
        .map(_withLatest)
        .where((p) => p.matchesQuery(query.text) && p.matchesFilter(query.filter))
        .toList();
    // Most recent activity first; patients without analyses last.
    result.sort((a, b) {
      final da = a.latestAnalysis?.createdAt, db = b.latestAnalysis?.createdAt;
      if (da == null && db == null) return a.fullName.compareTo(b.fullName);
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return result;
  }

  @override
  Future<Patient> getPatient(String patientId) async {
    await _latency();
    return _withLatest(_store.patientById(patientId));
  }

  @override
  Future<List<DoctorNote>> notes(String patientId) async {
    await _latency();
    return _store.notes.where((n) => n.patientId == patientId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<DoctorNote> addNote(String patientId, {required String body, required String author}) async {
    await _latency();
    if (body.trim().isEmpty) throw ArgumentError('Write a note first.');
    final note = DoctorNote(
      id: 'note-${DateTime.now().microsecondsSinceEpoch}',
      patientId: patientId,
      author: author,
      body: body.trim(),
      createdAt: DateTime.now(),
    );
    _store.notes.add(note);
    return note;
  }

  @override
  Future<Patient> updateContact(String patientId, {required String phone, required String emergencyContact}) async {
    await _latency();
    if (phone.trim().isEmpty) throw ArgumentError('Enter a phone number.');
    final i = _store.patients.indexWhere((p) => p.id == patientId);
    final p = _store.patients[i];
    _store.patients[i] = Patient(
      id: p.id,
      mrn: p.mrn,
      fullName: p.fullName,
      dateOfBirth: p.dateOfBirth,
      sex: p.sex,
      phone: phone.trim(),
      email: p.email,
      emergencyContact: emergencyContact.trim(),
    );
    return _withLatest(_store.patients[i]);
  }
}

class FixtureAnalysesRepository implements AnalysesRepository {
  FixtureAnalysesRepository(this._store, {this.stepDelay = const Duration(milliseconds: 700)});
  final FixtureStore _store;

  /// Time per simulated pipeline step.
  final Duration stepDelay;

  /// Demo results used for simulated analyses (class, model confidence).
  /// Chosen from the uploaded file so the same image gives the same demo result.
  /// These are NOT model outputs.
  static const _demoResults = [
    (ModelClass.earlyMci, 0.914),
    (ModelClass.cognitivelyNormal, 0.872),
    (ModelClass.lateMci, 0.726),
    (ModelClass.alzheimersDisease, 0.831),
  ];

  @override
  Future<List<AnalysisSummary>> listForPatient(String patientId, {required bool patientView}) async {
    await _latency();
    final all = _store.analysesOf(patientId);
    return patientView ? all.where((a) => a.released).map((a) => a.forPatient()).toList() : all;
  }

  @override
  Future<AnalysisSummary> getAnalysis(String analysisId, {required bool patientView}) async {
    await _latency();
    final a = _store.analyses.where((x) => x.id == analysisId).firstOrNull;
    if (a == null || _store.pendingAnalysisIds.contains(analysisId)) throw const NotFoundException();
    if (patientView && !a.released) throw const NotFoundException();
    return patientView ? a.forPatient() : a;
  }

  @override
  Future<String> startAnalysis({required String patientId, required MriFile file}) async {
    await _latency();
    final count = _store.analyses.where((a) => a.patientId == patientId).length + 1;
    final id = 'a-${patientId.substring(2)}-sim-$count-${DateTime.now().millisecondsSinceEpoch % 100000}';
    final (cls, conf) = _demoResults[file.bytes.fold<int>(0, (s, b) => (s + b) % 997) % _demoResults.length];
    _store.analyses.add(AnalysisSummary(
      id: id,
      patientId: patientId,
      createdAt: DateTime.now(),
      predicted: cls,
      confidence: conf,
      status: conf < 0.80 ? ReviewStatus.pendingReview : ReviewStatus.awaitingConfirmation,
      released: false,
      probabilities: FixtureStore.spreadProbabilities(cls, conf),
      simulated: true,
    ));
    _store.images[id] = file.bytes;
    _store.pendingAnalysisIds.add(id);
    // The simulated job runs on its own, like the real background job: it finishes
    // even if the doctor leaves the progress screen, and then notifies them.
    _store.jobSteps[id] = 0;
    Timer.periodic(stepDelay, (timer) {
      final next = (_store.jobSteps[id] ?? 0) + 1;
      if (next < AnalysisStep.visible.length) {
        _store.jobSteps[id] = next;
        return;
      }
      timer.cancel();
      _store.jobSteps.remove(id);
      _store.pendingAnalysisIds.remove(id);
      _store.notifyAnalysisCompleted(id);
    });
    return id;
  }

  @override
  Stream<AnalysisJob> watchJob(String analysisId) async* {
    int? last;
    while (_store.pendingAnalysisIds.contains(analysisId)) {
      final i = _store.jobSteps[analysisId] ?? 0;
      if (i != last) {
        last = i;
        yield AnalysisJob(analysisId: analysisId, step: AnalysisStep.visible[i]);
      }
      await Future<void>.delayed(stepDelay ~/ 4);
    }
    yield AnalysisJob(analysisId: analysisId, step: AnalysisStep.completed);
  }

  /// PDFs are made by the server; demo data does not invent one.
  @override
  Future<ReportFile> reportPdf(String analysisId) async {
    await _latency();
    throw const NotConnectedException();
  }

  /// Full scans need the real server (slice extraction, brain detector, model);
  /// demo data does not pretend to analyse them.
  @override
  Future<String> startVolumeAnalysis(
      {required String patientId, required String filename, required Uint8List bytes}) async {
    await _latency();
    throw const NotConnectedException();
  }

  @override
  Future<void> uploadForReview(MriFile file) async {
    await _latency();
    final patientId = demoPatient.patientId!;
    final id = 'a-${patientId.substring(2)}-up-${DateTime.now().millisecondsSinceEpoch % 100000}';
    final (cls, conf) = _demoResults[file.bytes.fold<int>(0, (s, b) => (s + b) % 997) % _demoResults.length];
    // Stored for the doctor only: patient views list released results, so the
    // patient sees nothing of this until the doctor reviews and releases it.
    _store.analyses.add(AnalysisSummary(
      id: id,
      patientId: patientId,
      createdAt: DateTime.now(),
      predicted: cls,
      confidence: conf,
      status: conf < 0.80 ? ReviewStatus.pendingReview : ReviewStatus.awaitingConfirmation,
      released: false,
      probabilities: FixtureStore.spreadProbabilities(cls, conf),
      simulated: true,
    ));
    _store.images[id] = file.bytes;
    _store.patientUploads.insert(0, (analysisId: id, at: DateTime.now()));
    _store.notifyAnalysisCompleted(id);
  }

  @override
  Future<List<PatientUpload>> myUploads() async {
    await _latency();
    return [
      for (final u in _store.patientUploads)
        PatientUpload(
          scanId: 'scan-${u.analysisId}',
          analysisId: u.analysisId,
          uploadedAt: u.at,
          state: _store.analyses.any((a) => a.id == u.analysisId && a.released)
              ? UploadState.released
              : UploadState.received,
        ),
    ];
  }

  @override
  Future<Uint8List?> imageFor(String analysisId) async => _store.images[analysisId];

  /// Demo data has no model, so it has no maps.
  @override
  Future<Explanation?> explanationFor(String analysisId) async => null;
}

class FixtureReviewsRepository implements ReviewsRepository {
  FixtureReviewsRepository(this._store);
  final FixtureStore _store;

  @override
  Future<AnalysisSummary> submitReview(ReviewDraft draft, {required String doctorName}) async {
    await _latency();
    final errors = draft.validate();
    if (errors.isNotEmpty) throw ArgumentError(errors.values.first);
    final a = _store.analyses.firstWhere((x) => x.id == draft.analysisId);
    if (a.status.isReviewed) throw const ConflictException('This analysis has already been reviewed.');
    final updated = a.withReview(
      status: draft.decision == ReviewDecision.confirm ? ReviewStatus.confirmed : ReviewStatus.overridden,
      finalClass: draft.effectiveFinalClass,
      reviewedBy: doctorName,
      reviewedAt: DateTime.now(),
      released: draft.releaseToPatient,
      overrideReason: draft.decision == ReviewDecision.override ? draft.overrideReason.trim() : null,
      clinicalNotes: draft.clinicalNotes.trim().isEmpty ? null : draft.clinicalNotes.trim(),
      patientSummary: draft.patientSummary.trim().isEmpty ? null : draft.patientSummary.trim(),
    );
    _store.replaceAnalysis(updated);
    if (updated.released) _store.notifyResultReleased(updated);
    return updated;
  }

  @override
  Future<AnalysisSummary> releaseToPatient(String analysisId) async {
    await _latency();
    final a = _store.analyses.firstWhere((x) => x.id == analysisId);
    if (!a.status.isReviewed) throw const ConflictException('Review the result before releasing it.');
    if ((a.patientSummary ?? '').isEmpty) {
      throw const ConflictException('Add a patient summary before releasing the result.');
    }
    final updated = a.markReleased();
    _store.replaceAnalysis(updated);
    _store.notifyResultReleased(updated);
    return updated;
  }
}

class FixtureTimelineRepository implements TimelineRepository {
  FixtureTimelineRepository(this._store);
  final FixtureStore _store;

  @override
  Future<List<TimelineEvent>> forPatient(String patientId, {required bool patientView}) async {
    await _latency();
    return _store.timelineOf(patientId, patientView: patientView);
  }
}

class FixtureDashboardRepository implements DashboardRepository {
  FixtureDashboardRepository(this._store);
  final FixtureStore _store;

  @override
  Future<List<ReviewQueueItem>> reviewQueue() async {
    await _latency();
    final waiting = _store.analyses
        .where((a) => !a.status.isReviewed && !_store.pendingAnalysisIds.contains(a.id))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return [
      for (final a in waiting)
        ReviewQueueItem(
          analysisId: a.id,
          patientId: a.patientId,
          patientName: _store.patientById(a.patientId).fullName,
          uploadedAt: a.createdAt,
          analysis: a,
        ),
    ];
  }

  @override
  Future<DoctorDashboard> doctorDashboard() async {
    await _latency();
    final now = _store.now;
    final weekAgo = now.subtract(const Duration(days: 7));
    final weekAhead = now.add(const Duration(days: 7));
    final visible = _store.analyses.where((a) => !_store.pendingAnalysisIds.contains(a.id));
    final activity = [
      for (final p in _store.patients) ..._store.timelineOf(p.id, patientView: false).where((e) => !e.at.isAfter(now)),
    ]..sort((a, b) => b.at.compareTo(a.at));
    return DoctorDashboard(
      patientCount: _store.patients.length,
      pendingReviews: visible.where((a) => !a.status.isReviewed).length,
      recentAnalyses: visible.where((a) => a.createdAt.isAfter(weekAgo)).length,
      upcomingAppointments:
          _store.appointments.where((ap) => ap.isUpcoming(now) && ap.startsAt.isBefore(weekAhead)).length,
      recentActivity: activity.take(5).toList(),
    );
  }

  @override
  Future<PatientDashboard> patientDashboard(String patientId) async {
    await _latency();
    final now = _store.now;
    final released = _store.analysesOf(patientId).where((a) => a.released).toList();
    final upcoming = _store.appointments.where((ap) => ap.patientId == patientId && ap.isUpcoming(now)).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return PatientDashboard(
      latestReleased: released.isEmpty ? null : released.first.forPatient(),
      nextAppointment: upcoming.isEmpty ? null : upcoming.first,
      recentActivity: _store.timelineOf(patientId, patientView: true).where((e) => !e.at.isAfter(now)).take(3).toList(),
    );
  }
}

class FixtureNotificationsRepository implements NotificationsRepository {
  FixtureNotificationsRepository(this._store);
  final FixtureStore _store;

  @override
  Future<List<AppNotification>> listFor(String userId) async {
    await _latency();
    return _store.notifications.where((n) => n.userId == userId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<void> markRead(String notificationId) async {
    final i = _store.notifications.indexWhere((n) => n.id == notificationId);
    if (i >= 0) _store.notifications[i] = _store.notifications[i].copyWith(read: true);
  }

  @override
  Future<void> markAllRead(String userId) async {
    for (var i = 0; i < _store.notifications.length; i++) {
      if (_store.notifications[i].userId == userId) {
        _store.notifications[i] = _store.notifications[i].copyWith(read: true);
      }
    }
  }
}

class FixtureProfileRepository implements ProfileRepository {
  FixtureProfileRepository(this._store);
  final FixtureStore _store;

  @override
  Future<ProfileDetails> detailsFor(Session session) async {
    await _latency();
    if (session.role == UserRole.doctor) {
      return const ProfileDetails(
        personal: [
          (label: 'Full name', value: 'Dr. Ahmed Khan'),
          (label: 'Email', value: 'ahmed.khan@example.com'),
          (label: 'Phone', value: '+971 50 000 0001'),
        ],
        health: [
          (label: 'Specialty', value: 'Neurology'),
          (label: 'Clinic', value: 'NeuroSense Demo Clinic'),
          (label: 'Licence number', value: 'DEMO-0001'),
        ],
      );
    }
    final p = _store.patientById(session.patientId!);
    return ProfileDetails(
      personal: [
        (label: 'Full name', value: p.fullName),
        (label: 'Date of birth', value: Fmt.date(p.dateOfBirth)),
        (label: 'Sex', value: p.sex.label),
        (label: 'Email', value: p.email),
        (label: 'Phone', value: p.phone),
        (label: 'Emergency contact', value: p.emergencyContact),
      ],
      health: [
        (label: 'Patient ID', value: p.mrn),
        (label: 'Assigned doctor', value: FixtureStore.doctorName),
        (label: 'Clinic', value: 'NeuroSense Demo Clinic'),
      ],
    );
  }
}
