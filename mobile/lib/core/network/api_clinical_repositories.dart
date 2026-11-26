import 'dart:convert';
import 'dart:typed_data';

import '../../features/dashboard/data/dashboard_repository.dart';
import '../../features/dashboard/data/models/dashboards.dart';
import '../../features/diagnosis/data/analyses_repository.dart';
import '../../features/diagnosis/data/models/analysis.dart';
import '../../features/diagnosis/data/models/analysis_job.dart';
import '../../features/diagnosis/data/models/explanation.dart';
import '../../features/diagnosis/data/models/mri_file.dart';
import '../../features/diagnosis/data/models/upload_models.dart';
import '../../features/appointments/data/models/appointment.dart';
import '../../features/patients/data/models/doctor_note.dart';
import '../../features/patients/data/models/patient.dart';
import '../../features/patients/data/patients_repository.dart';
import '../../features/reviews/data/models/review_draft.dart';
import '../../features/reviews/data/reviews_repository.dart';
import '../../features/timeline/data/models/timeline_event.dart';
import '../../features/timeline/data/timeline_repository.dart';
import 'api_client.dart';

// Repositories backed by the NeuroSense server. They only translate between
// the server's JSON and the app's models: who may see what is decided by the
// server from the access token. Arguments such as [patientView], author or
// sender names are not sent, because the server does not trust them.

class ApiPatientsRepository implements PatientsRepository {
  ApiPatientsRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<Patient>> listAssigned(PatientQuery query) async {
    final rows = await _api.getList('/patients', query: {
      if (query.text.trim().isNotEmpty) 'search': query.text.trim(),
      'filter': query.filter.name,
    });
    return rows.map(Patient.fromJson).toList();
  }

  @override
  Future<Patient> getPatient(String patientId) async => Patient.fromJson(await _api.getJson('/patients/$patientId'));

  @override
  Future<List<DoctorNote>> notes(String patientId) async =>
      (await _api.getList('/patients/$patientId/notes')).map(DoctorNote.fromJson).toList();

  @override
  Future<DoctorNote> addNote(String patientId, {required String body, required String author}) async {
    if (body.trim().isEmpty) throw ArgumentError('Write a note first.');
    return DoctorNote.fromJson(await _api.postJson('/patients/$patientId/notes', body: {'body': body.trim()}));
  }

  @override
  Future<Patient> updateContact(String patientId, {required String phone, required String emergencyContact}) async =>
      Patient.fromJson(await _api.patchJson(
        '/patients/$patientId/contact',
        body: {'phone': phone, 'emergency_contact': emergencyContact},
      ));
}

class ApiAnalysesRepository implements AnalysesRepository {
  ApiAnalysesRepository(
    this._api, {
    required this.prepareImage,
    this.pollInterval = const Duration(seconds: 1),
  });

  final ApiClient _api;

  /// Makes the picked image fit the server's size limit before upload.
  final Future<Uint8List> Function(Uint8List bytes) prepareImage;
  final Duration pollInterval;

  @override
  Future<List<AnalysisSummary>> listForPatient(String patientId, {required bool patientView}) async =>
      (await _api.getList('/patients/$patientId/analyses')).map(AnalysisSummary.fromJson).toList();

  @override
  Future<AnalysisSummary> getAnalysis(String analysisId, {required bool patientView}) async =>
      AnalysisSummary.fromJson(await _api.getJson('/analyses/$analysisId'));

  Future<Map<String, dynamic>> _upload(MriFile file, {String? patientId}) async => _api.postJson('/scans', body: {
        'image_base64': base64Encode(await prepareImage(file.bytes)),
        'filename': file.name,
        if (patientId != null) 'patient_id': patientId,
      });

  @override
  Future<String> startAnalysis({required String patientId, required MriFile file}) async =>
      (await _upload(file, patientId: patientId))['analysis_id'] as String;

  @override
  Future<void> uploadForReview(MriFile file) => _upload(file);

  @override
  Future<String> startVolumeAnalysis(
          {required String patientId, required String filename, required Uint8List bytes}) async =>
      (await _api.postBytes('/scans/volume', bytes, query: {'patient_id': patientId, 'filename': filename}))[
          'analysis_id'] as String;

  @override
  Future<ReportFile> reportPdf(String analysisId) async {
    // Times in the PDF follow this phone's time zone.
    final file = await _api.getFile('/analyses/$analysisId/report.pdf',
        query: {'utc_offset_minutes': DateTime.now().timeZoneOffset.inMinutes});
    return ReportFile(filename: file.filename ?? 'NeuroSense-report.pdf', bytes: file.bytes);
  }

  @override
  Future<List<PatientUpload>> myUploads() async =>
      (await _api.getList('/scans/mine')).map(PatientUpload.fromJson).toList();

  /// Polls the job status and maps it onto the steps the progress screen shows.
  @override
  Stream<AnalysisJob> watchJob(String analysisId) async* {
    AnalysisStep? last;
    while (true) {
      final job = await _api.getJson('/analyses/$analysisId/status');
      final status = job['job_status'] as String;
      if (status == 'failed') {
        // Shown by the progress screen's error state.
        throw ConflictException(failureMessage(job['error_code'] as String?));
      }
      if (status == 'completed') {
        yield AnalysisJob(analysisId: analysisId, step: AnalysisStep.completed);
        return;
      }
      final step = status == 'running' ? AnalysisStep.runningModel : AnalysisStep.validating;
      if (step != last) {
        last = step;
        yield AnalysisJob(analysisId: analysisId, step: step);
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  @override
  Future<Uint8List?> imageFor(String analysisId) async {
    try {
      final data = await _api.getJson('/analyses/$analysisId/image');
      return base64Decode(data['image_base64'] as String);
    } on NotFoundException {
      return null; // not stored any more (retention), or not visible
    }
  }

  @override
  Future<Explanation?> explanationFor(String analysisId) async {
    try {
      return Explanation.fromJson(await _api.getJson('/analyses/$analysisId/explanation'));
    } on NotFoundException {
      return null; // no map for this result
    }
  }
}

/// What the doctor is told when an analysis fails, by the server's error code.
String failureMessage(String? code) => switch (code) {
      'VOLUME_TOO_FEW_SLICES' =>
        'Too few brain slices were found in this scan to analyse it. Check that it is a brain MRI.',
      'VOLUME_INVALID' => 'The scan file could not be read. Upload a .nii or .nii.gz file.',
      'VOLUME_TOO_LARGE' => 'The scan file is too large.',
      'BRAIN_FILTER_MISSING' => 'Full-scan analysis is not available on this server.',
      _ => 'The server could not analyse this scan. Try uploading it again.',
    };

class ApiReviewsRepository implements ReviewsRepository {
  ApiReviewsRepository(this._api);
  final ApiClient _api;

  @override
  Future<AnalysisSummary> submitReview(ReviewDraft draft, {required String doctorName}) async {
    final errors = draft.validate();
    if (errors.isNotEmpty) throw ArgumentError(errors.values.first);
    return AnalysisSummary.fromJson(await _api.postJson('/analyses/${draft.analysisId}/review', body: draft.toJson()));
  }

  @override
  Future<AnalysisSummary> releaseToPatient(String analysisId) async =>
      AnalysisSummary.fromJson(await _api.postJson('/analyses/$analysisId/release'));
}

class ApiTimelineRepository implements TimelineRepository {
  ApiTimelineRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<TimelineEvent>> forPatient(String patientId, {required bool patientView}) async =>
      (await _api.getList('/patients/$patientId/timeline')).map(TimelineEvent.fromJson).toList();
}

class ApiDashboardRepository implements DashboardRepository {
  ApiDashboardRepository(this._api);
  final ApiClient _api;

  static List<TimelineEvent> _events(Object? list) =>
      [for (final e in list as List) TimelineEvent.fromJson((e as Map).cast<String, dynamic>())];

  @override
  Future<DoctorDashboard> doctorDashboard() async {
    final json = await _api.getJson('/doctor/dashboard');
    return DoctorDashboard(
      patientCount: json['patient_count'] as int,
      pendingReviews: json['pending_reviews'] as int,
      recentAnalyses: json['recent_analyses'] as int,
      upcomingAppointments: json['upcoming_appointments'] as int,
      recentActivity: _events(json['recent_activity']),
    );
  }

  @override
  Future<List<ReviewQueueItem>> reviewQueue() async =>
      (await _api.getList('/doctor/review-queue')).map(ReviewQueueItem.fromJson).toList();

  @override
  Future<PatientDashboard> patientDashboard(String patientId) async {
    final json = await _api.getJson('/patient/dashboard');
    final latest = json['latest_released'] as Map?;
    final next = json['next_appointment'] as Map?;
    return PatientDashboard(
      latestReleased: latest == null ? null : AnalysisSummary.fromJson(latest.cast<String, dynamic>()),
      nextAppointment: next == null ? null : Appointment.fromJson(next.cast<String, dynamic>()),
      recentActivity: _events(json['recent_activity']),
    );
  }
}
