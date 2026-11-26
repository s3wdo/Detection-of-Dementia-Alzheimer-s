enum ResourceCategory {
  results('My results'),
  condition('Understanding dementia'),
  appointments('Appointments'),
  caregiving('Family & caregiving'),
  lifestyle('Lifestyle');

  const ResourceCategory(this.label);
  final String label;
}

/// An approved educational article (real version: GET /counselling/resources).
class Resource {
  const Resource({
    required this.slug,
    required this.title,
    required this.category,
    required this.summary,
    required this.minutes,
    required this.source,
    required this.sections,
    this.keywords = const [],
  });

  final String slug;
  final String title;
  final ResourceCategory category;
  final String summary;
  final int minutes;

  /// Where the content comes from, shown to the reader.
  final String source;
  final List<({String heading, String body})> sections;

  /// Words that make the assistant suggest this article.
  final List<String> keywords;
}

/// What kind of answer the assistant gave. Drives the styling and actions.
enum ReplyKind {
  /// Educational answer.
  answer,

  /// Out of scope (medicines, diagnosis…): refers the patient to their doctor.
  referral,

  /// Possible emergency: tells the patient to call emergency services.
  emergency,
}

class CounsellingReply {
  const CounsellingReply({required this.text, required this.kind, this.sources = const []});

  final String text;
  final ReplyKind kind;
  final List<String> sources;
}

/// One bubble in the counselling chat.
class ChatEntry {
  const ChatEntry(
      {required this.fromPatient, required this.text, this.kind = ReplyKind.answer, this.sources = const []});

  final bool fromPatient;
  final String text;
  final ReplyKind kind;
  final List<String> sources;
}
