import '../../diagnosis/data/models/analysis.dart';
import 'models/review_draft.dart';

/// Real version: POST /analyses/{aid}/review, PATCH /reviews/{rid}/release.
abstract interface class ReviewsRepository {
  /// Saves the doctor's decision. Throws ConflictException if already reviewed.
  Future<AnalysisSummary> submitReview(ReviewDraft draft, {required String doctorName});

  /// Makes an already reviewed result visible to the patient.
  Future<AnalysisSummary> releaseToPatient(String analysisId);
}
