/// The four classes the trained MRI model outputs:
/// AD (Alzheimer's disease), LMCI (late mild cognitive impairment),
/// EMCI (early mild cognitive impairment) and CN (cognitively normal).
/// No other classes exist in this model.
///
/// [apiName] is the name the server sends. The model's output order
/// (AD, LMCI, EMCI, CN) is the server's concern; this enum lists the classes
/// from normal to Alzheimer's disease, the order the app shows them in.
enum ModelClass {
  cognitivelyNormal('CN', 'Cognitively Normal'),
  earlyMci('EMCI', 'Early MCI'),
  lateMci('LMCI', 'Late MCI'),
  alzheimersDisease('AD', "Alzheimer's Disease");

  const ModelClass(this.apiName, this.label);

  final String apiName;

  /// Text shown in the UI.
  final String label;

  static ModelClass fromJson(String value) => ModelClass.values.firstWhere((c) => c.apiName == value);
  String toJson() => apiName;
}
