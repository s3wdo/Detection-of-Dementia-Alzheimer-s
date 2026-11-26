import 'model_class.dart';

/// Where an AI analysis is in the review process (State Diagram 2 of the design):
/// below 0.80 confidence → pendingReview, otherwise awaitingConfirmation,
/// until a doctor confirms or overrides it.
enum ReviewStatus {
  awaitingConfirmation,
  pendingReview,
  confirmed,
  overridden;

  bool get isReviewed => this == confirmed || this == overridden;

  static ReviewStatus fromJson(String value) => ReviewStatus.values.byName(value);
  String toJson() => name;
}

/// Set when the analysis came from a full MRI scan (.nii) rather than one slice:
/// the model's scores are averaged over [slicesUsed] axial slices, and the image
/// shown is axial slice [sliceIndex] (0-based, in the scan's order).
class VolumeInfo {
  const VolumeInfo({
    required this.slicesTotal,
    required this.slicesKept,
    required this.slicesUsed,
    required this.sliceIndex,
  });

  final int slicesTotal;

  /// Slices the brain detector accepted.
  final int slicesKept;

  /// Slices classified after the top slices were pruned.
  final int slicesUsed;
  final int sliceIndex;

  static VolumeInfo? fromJson(Map<String, dynamic> json) {
    if (json['input_kind'] != 'volume' || json['slices_used'] == null) return null;
    return VolumeInfo(
      slicesTotal: (json['slices_total'] as num).toInt(),
      slicesKept: (json['slices_kept'] as num).toInt(),
      slicesUsed: (json['slices_used'] as num).toInt(),
      sliceIndex: (json['slice_index'] as num).toInt(),
    );
  }
}

/// One AI analysis of one MRI scan, plus the doctor's review if there is one.
class AnalysisSummary {
  const AnalysisSummary({
    required this.id,
    required this.patientId,
    required this.createdAt,
    required this.predicted,
    required this.confidence,
    required this.status,
    required this.released,
    this.modelName = 'EfficientNetV2S',
    this.modelVersion = 'v1.0',
    this.probabilities = const {},
    this.simulated = false,
    this.finalClass,
    this.reviewedBy,
    this.reviewedAt,
    this.overrideReason,
    this.clinicalNotes,
    this.patientSummary,
    this.volume,
  });

  final String id;
  final String patientId;
  final DateTime createdAt;

  /// AI output: predicted class and its softmax score (not a calibrated probability).
  final ModelClass predicted;
  final double confidence;
  final String modelName;
  final String modelVersion;

  /// Score for each of the four classes (sums to 1). Empty if not available.
  final Map<ModelClass, double> probabilities;

  /// True for demo data produced without the real model. The UI must label
  /// these results as simulated.
  final bool simulated;

  final ReviewStatus status;

  /// True once the doctor has released this result to the patient.
  final bool released;

  /// Doctor's decision. For a confirmed result this equals [predicted].
  final ModelClass? finalClass;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? overrideReason;

  /// Doctor-only notes. The backend never sends these to patients.
  final String? clinicalNotes;

  /// Plain-language summary written for the patient.
  final String? patientSummary;

  /// Doctor view only: set for a full-scan analysis.
  final VolumeInfo? volume;

  /// Copy without anything the patient must not see.
  AnalysisSummary forPatient() => AnalysisSummary(
        id: id,
        patientId: patientId,
        createdAt: createdAt,
        predicted: predicted,
        confidence: 0, // patients are not shown the model's scores
        status: status,
        released: released,
        modelName: modelName,
        modelVersion: modelVersion,
        probabilities: const {},
        simulated: simulated,
        finalClass: finalClass,
        reviewedBy: reviewedBy,
        reviewedAt: reviewedAt,
        patientSummary: patientSummary,
      );

  /// Copy with a doctor's review applied.
  AnalysisSummary withReview({
    required ReviewStatus status,
    required ModelClass finalClass,
    required String reviewedBy,
    required DateTime reviewedAt,
    required bool released,
    String? overrideReason,
    String? clinicalNotes,
    String? patientSummary,
  }) =>
      AnalysisSummary(
        id: id,
        patientId: patientId,
        createdAt: createdAt,
        predicted: predicted,
        confidence: confidence,
        status: status,
        released: released,
        modelName: modelName,
        modelVersion: modelVersion,
        probabilities: probabilities,
        simulated: simulated,
        finalClass: finalClass,
        reviewedBy: reviewedBy,
        reviewedAt: reviewedAt,
        overrideReason: overrideReason,
        clinicalNotes: clinicalNotes,
        patientSummary: patientSummary,
        volume: volume,
      );

  /// Copy marked as released to the patient.
  AnalysisSummary markReleased() => withReview(
        status: status,
        finalClass: finalClass ?? predicted,
        reviewedBy: reviewedBy ?? '',
        reviewedAt: reviewedAt ?? createdAt,
        released: true,
        overrideReason: overrideReason,
        clinicalNotes: clinicalNotes,
        patientSummary: patientSummary,
      );

  factory AnalysisSummary.fromJson(Map<String, dynamic> json) {
    final review = json['review'] as Map<String, dynamic>?;
    return AnalysisSummary(
      id: json['id'] as String,
      patientId: json['patient_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      predicted: ModelClass.fromJson(json['predicted_label'] as String),
      // Absent in the patient's copy: the server does not send scores to patients.
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      status: ReviewStatus.fromJson(json['status'] as String),
      released: review?['released_to_patient'] as bool? ?? false,
      modelName: json['model_name'] as String? ?? 'EfficientNetV2S',
      modelVersion: json['model_version'] as String? ?? 'v1.0',
      simulated: json['simulated'] as bool? ?? false,
      probabilities: {
        for (final e in ((json['probabilities'] as Map<String, dynamic>?) ?? const {}).entries)
          ModelClass.fromJson(e.key): (e.value as num).toDouble(),
      },
      finalClass: review?['final_label'] == null ? null : ModelClass.fromJson(review!['final_label'] as String),
      reviewedBy: review?['doctor_name'] as String?,
      reviewedAt: review?['reviewed_at'] == null ? null : DateTime.parse(review!['reviewed_at'] as String).toLocal(),
      overrideReason: review?['override_reason'] as String?,
      clinicalNotes: review?['clinical_notes'] as String?,
      patientSummary: review?['patient_summary'] as String?,
      volume: VolumeInfo.fromJson(json),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'patient_id': patientId,
        'created_at': createdAt.toIso8601String(),
        'predicted_label': predicted.toJson(),
        'confidence': confidence,
        'status': status.toJson(),
        'model_name': modelName,
        'model_version': modelVersion,
        'simulated': simulated,
        'probabilities': {for (final e in probabilities.entries) e.key.toJson(): e.value},
        if (volume != null) ...{
          'input_kind': 'volume',
          'slices_total': volume!.slicesTotal,
          'slices_kept': volume!.slicesKept,
          'slices_used': volume!.slicesUsed,
          'slice_index': volume!.sliceIndex,
        },
        if (status.isReviewed)
          'review': {
            'final_label': finalClass?.toJson(),
            'doctor_name': reviewedBy,
            'reviewed_at': reviewedAt?.toIso8601String(),
            'override_reason': overrideReason,
            'clinical_notes': clinicalNotes,
            'patient_summary': patientSummary,
            'released_to_patient': released,
          },
      };
}
