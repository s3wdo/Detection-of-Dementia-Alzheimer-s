/// Steps of the analysis pipeline shown on the progress screen (design screen 5).
enum AnalysisStep {
  validating('Image validation', 'Format, size and grayscale checks'),
  preprocessing('Preprocessing', 'Prepared for the model'),
  runningModel('Running AI model', 'Four-class output'),
  explaining('Generating explainability', 'Heatmap for the predicted class, when the model provides one'),
  saving('Saving results', 'Private record for this patient'),
  completed('Completed', '');

  const AnalysisStep(this.label, this.detail);
  final String label;

  /// Technical line shown under the step on the progress screen.
  final String detail;

  /// Steps listed on screen (everything except "completed").
  static const visible = [validating, preprocessing, runningModel, explaining, saving];
}

/// Progress of one analysis. The real backend reports queued/running/completed
/// via GET /analyses/{id}; the repository maps that onto these steps.
class AnalysisJob {
  const AnalysisJob({required this.analysisId, required this.step, this.errorMessage});

  final String analysisId;
  final AnalysisStep step;

  /// Set when the analysis failed.
  final String? errorMessage;

  bool get isDone => step == AnalysisStep.completed;
  bool get failed => errorMessage != null;

  /// 0–1, for the progress ring.
  double get progress => step.index / AnalysisStep.completed.index;
}
