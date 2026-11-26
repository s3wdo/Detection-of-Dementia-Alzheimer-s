import 'models/explanation.dart';
import 'dart:typed_data';

import 'models/analysis.dart';
import 'models/analysis_job.dart';
import 'models/mri_file.dart';
import 'models/upload_models.dart';
import '../../../core/data/user_facing_error.dart';

/// A report PDF as the server made it.
class ReportFile {
  const ReportFile({required this.filename, required this.bytes});

  final String filename;
  final Uint8List bytes;
}

/// Access to MRI scans and AI analyses.
/// API: POST /scans, GET /scans/mine, GET /patients/{pid}/analyses,
/// GET /analyses/{aid}, GET /analyses/{aid}/status, GET /analyses/{aid}/image.
abstract interface class AnalysesRepository {
  /// Newest first. With [patientView] only released results are returned and
  /// doctor-only fields are removed (the backend enforces the same rule).
  Future<List<AnalysisSummary>> listForPatient(String patientId, {required bool patientView});

  /// Throws [NotFoundException] if it doesn't exist or isn't visible to a patient.
  Future<AnalysisSummary> getAnalysis(String analysisId, {required bool patientView});

  /// Doctor: uploads a scan for an assigned patient and starts its analysis.
  /// Returns the analysis id.
  Future<String> startAnalysis({required String patientId, required MriFile file});

  /// Doctor: uploads a full MRI scan (.nii or .nii.gz) for an assigned patient.
  /// The server extracts the axial slices, keeps the brain slices and averages
  /// the model's scores over them. Returns the analysis id.
  Future<String> startVolumeAnalysis({required String patientId, required String filename, required Uint8List bytes});

  /// Doctor: progress updates until the analysis completes or fails.
  Stream<AnalysisJob> watchJob(String analysisId);

  /// Patient: sends their own scan to their doctor. Nothing about the analysis
  /// comes back; the result is visible only after the doctor releases it.
  Future<void> uploadForReview(MriFile file);

  /// Patient: their own uploads, newest first, with a coarse state only.
  Future<List<PatientUpload>> myUploads();

  /// The report as a PDF, made by the server for a reviewed result: the doctor
  /// version for doctors, the patient copy (released results only) for patients.
  /// Throws [ConflictException] before the review, [NotFoundException] when not visible.
  Future<ReportFile> reportPdf(String analysisId);

  /// The original MRI image, if stored.
  Future<Uint8List?> imageFor(String analysisId);

  /// The model's Grad-CAM map, or null when the server has none (stub results,
  /// older results, images removed by retention). Never invented on the phone.
  Future<Explanation?> explanationFor(String analysisId);
}

/// Matches the backend's 404 (also used for "exists but is not yours").
class NotFoundException implements UserFacingError {
  const NotFoundException([this.message = 'This item was not found.']);
  final String message;

  @override
  String toString() => message;
}

/// Matches the backend's 409, e.g. reviewing an analysis twice.
class ConflictException implements UserFacingError {
  const ConflictException(this.message);
  final String message;

  @override
  String toString() => message;
}
