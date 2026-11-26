import '../../../../core/models/info_source.dart';

enum TimelineKind { mriAnalysis, doctorReview, appointment, message }

/// One entry on a patient's timeline. [source] says who produced it, so the
/// UI can keep AI output, doctor decisions and admin events visibly apart.
class TimelineEvent {
  const TimelineEvent({
    required this.id,
    required this.patientId,
    required this.at,
    required this.kind,
    required this.source,
    required this.title,
    required this.detail,
    this.patientName,
    this.pending = false,
  });

  final String id;
  final String patientId;
  final DateTime at;
  final TimelineKind kind;
  final InfoSource source;
  final String title;
  final String detail;

  /// Filled in for doctor-wide activity feeds.
  final String? patientName;

  /// AI result still waiting for a doctor (doctor view only).
  final bool pending;

  factory TimelineEvent.fromJson(Map<String, dynamic> json) => TimelineEvent(
        id: json['id'] as String,
        patientId: json['patient_id'] as String,
        at: DateTime.parse(json['date'] as String).toLocal(),
        kind: TimelineKind.values.byName(json['type'] as String),
        source: InfoSource.fromJson(json['source'] as String),
        title: json['title'] as String,
        detail: json['summary'] as String,
        patientName: json['patient_name'] as String?,
        pending: json['pending'] as bool? ?? false,
      );
}
