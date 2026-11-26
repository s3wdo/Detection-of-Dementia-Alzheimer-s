/// A clinician's working note about a patient. Doctor-only: never shown in the
/// patient app and never sent to the counselling assistant.
class DoctorNote {
  const DoctorNote({
    required this.id,
    required this.patientId,
    required this.author,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String patientId;
  final String author;
  final String body;
  final DateTime createdAt;

  factory DoctorNote.fromJson(Map<String, dynamic> json) => DoctorNote(
        id: json['id'] as String,
        patientId: json['patient_id'] as String,
        author: json['author'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );
}
