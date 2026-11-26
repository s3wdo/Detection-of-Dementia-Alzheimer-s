import '../../../diagnosis/data/models/model_class.dart';

enum ReviewDecision { confirm, override }

/// What the doctor fills in on the review screen.
/// Matches POST /analyses/{aid}/review.
class ReviewDraft {
  const ReviewDraft({
    required this.analysisId,
    required this.decision,
    required this.predicted,
    this.finalClass,
    this.overrideReason = '',
    this.clinicalNotes = '',
    this.patientSummary = '',
    this.releaseToPatient = false,
  });

  final String analysisId;
  final ReviewDecision decision;

  /// The AI's predicted class (used to check that an override changes it).
  final ModelClass predicted;
  final ModelClass? finalClass;
  final String overrideReason;
  final String clinicalNotes;
  final String patientSummary;
  final bool releaseToPatient;

  /// The class that becomes the doctor's final classification.
  ModelClass get effectiveFinalClass => decision == ReviewDecision.confirm ? predicted : finalClass!;

  /// Field name → error message. Empty when the review can be submitted.
  Map<String, String> validate() => {
        if (decision == ReviewDecision.override && finalClass == null) 'finalClass': 'Select the final classification.',
        if (decision == ReviewDecision.override && finalClass == predicted)
          'finalClass': 'An override must differ from the AI prediction.',
        if (decision == ReviewDecision.override && overrideReason.trim().length < 10)
          'overrideReason': 'Explain why you are overriding the AI result (at least 10 characters).',
        if (releaseToPatient && patientSummary.trim().isEmpty)
          'patientSummary': 'Write a summary for the patient before releasing the result.',
      };

  Map<String, dynamic> toJson() => {
        'decision': decision == ReviewDecision.confirm ? 'confirmed' : 'overridden',
        if (decision == ReviewDecision.override) 'final_label': finalClass!.toJson(),
        if (decision == ReviewDecision.override) 'override_reason': overrideReason.trim(),
        'clinical_notes': clinicalNotes.trim(),
        'patient_summary': patientSummary.trim(),
        'release_to_patient': releaseToPatient,
      };
}
