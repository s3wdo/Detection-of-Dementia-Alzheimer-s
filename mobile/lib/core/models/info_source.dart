/// Where a piece of information came from. AI output must never look like a
/// doctor's decision, so the UI gives each source its own colour and wording.
enum InfoSource {
  ai,
  doctor,
  admin;

  static InfoSource fromJson(String value) => InfoSource.values.byName(value);
  String toJson() => name;
}
