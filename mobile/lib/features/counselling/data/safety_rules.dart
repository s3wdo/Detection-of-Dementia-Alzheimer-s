/// First safety layer of the counselling assistant (see the plan's counselling
/// architecture). It runs before any answer is produced — today before the
/// predefined demo answers, later before the LLM — and routes risky questions
/// to fixed, safe replies.
enum SafetyCategory {
  /// Possible danger to life → call emergency services.
  emergency,

  /// Starting, stopping or changing medicine → doctor or pharmacist.
  medication,

  /// "Do I have…", prognosis, treatment choice → doctor.
  diagnosis,

  /// Questions about the patient's own result → answered only from the
  /// released, doctor-reviewed result.
  ownResult,

  /// General education.
  general,
}

abstract final class SafetyRules {
  static final _emergency = RegExp(
    r"suicid|kill myself|end my life|self[- ]?harm|hurt myself|can'?t breathe|chest pain|"
    r'stroke|face (is )?droop|slurred speech|unconscious|emergency|overdose',
    caseSensitive: false,
  );
  static final _medication = RegExp(
    r'medic|medicine|tablet|pill|dose|dosage|prescri|stop taking|start taking|side effect|\bdrug',
    caseSensitive: false,
  );
  static final _diagnosis = RegExp(
    r'do i have|have i got|am i going to|will i (get|become)|how long (do|will) i|is it alzheimer|'
    r'cure|what treatment|should i be treated|diagnose me|prognosis',
    caseSensitive: false,
  );
  static final _ownResult = RegExp(
    r'\bmy\b.{0,20}\b(mri|result|report|scan|analysis|classification)|what does my',
    caseSensitive: false,
  );

  /// Most serious category wins.
  static SafetyCategory classify(String question) {
    if (_emergency.hasMatch(question)) return SafetyCategory.emergency;
    if (_medication.hasMatch(question)) return SafetyCategory.medication;
    if (_diagnosis.hasMatch(question)) return SafetyCategory.diagnosis;
    if (_ownResult.hasMatch(question)) return SafetyCategory.ownResult;
    return SafetyCategory.general;
  }

  static const emergencyReply =
      'If you or someone else may be in danger, or has sudden symptoms such as chest pain, trouble speaking, '
      'or weakness on one side of the body, call your local emergency number now. '
      'NeuroSense cannot help in an emergency.';

  static const medicationReply =
      "I can't give advice about starting, stopping or changing any medicine. Please ask your doctor or "
      'pharmacist — they know your full medical history. You can message your doctor from here.';

  static const diagnosisReply =
      "I can't tell you whether you have a condition or what will happen next. Only your doctor can do that, "
      'using your examination, history and tests together. I can explain general information or help you '
      'prepare questions for your appointment.';
}
