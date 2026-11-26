import 'analysis.dart';

/// What a patient is told about a scan they uploaded. Deliberately coarse:
/// it never says whether the analysis has run or what it found.
enum UploadState {
  /// Received by the server and waiting for the doctor.
  received,

  /// The doctor has reviewed it and released the result.
  released,

  /// The image could not be processed; the patient should upload again.
  needsReupload;

  static UploadState fromJson(String value) => switch (value) {
        'released' => released,
        'needs_reupload' => needsReupload,
        _ => received,
      };
}

/// One of the patient's own uploads (GET /scans/mine).
class PatientUpload {
  const PatientUpload({required this.scanId, required this.analysisId, required this.uploadedAt, required this.state});

  final String scanId;
  final String analysisId;
  final DateTime uploadedAt;
  final UploadState state;

  factory PatientUpload.fromJson(Map<String, dynamic> json) => PatientUpload(
        scanId: json['scan_id'] as String,
        analysisId: json['analysis_id'] as String,
        uploadedAt: DateTime.parse(json['uploaded_at'] as String).toLocal(),
        state: UploadState.fromJson(json['state'] as String),
      );
}

/// One item waiting for the doctor (GET /doctor/review-queue): an analysis
/// that needs a review, or one that failed and needs a retry or a new upload.
class ReviewQueueItem {
  const ReviewQueueItem({
    required this.analysisId,
    required this.patientId,
    required this.patientName,
    required this.uploadedAt,
    this.analysis,
  });

  final String analysisId;
  final String patientId;
  final String patientName;
  final DateTime uploadedAt;

  /// The AI result. Null when the analysis failed.
  final AnalysisSummary? analysis;

  bool get failed => analysis == null;

  factory ReviewQueueItem.fromJson(Map<String, dynamic> json) => ReviewQueueItem(
        analysisId: json['analysis_id'] as String,
        patientId: json['patient_id'] as String,
        patientName: json['patient_name'] as String,
        uploadedAt: DateTime.parse(json['uploaded_at'] as String).toLocal(),
        analysis: json['analysis'] == null ? null : AnalysisSummary.fromJson(json['analysis'] as Map<String, dynamic>),
      );
}
