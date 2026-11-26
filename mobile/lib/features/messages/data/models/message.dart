/// A message between a patient and their care team (not the AI assistant).
class Message {
  const Message({
    required this.id,
    required this.patientId,
    required this.fromDoctor,
    required this.senderName,
    required this.body,
    required this.sentAt,
    this.read = false,
    this.linkedTo,
  });

  final String id;
  final String patientId;
  final bool fromDoctor;
  final String senderName;
  final String body;
  final DateTime sentAt;

  /// Read by the recipient.
  final bool read;

  /// What the message is about, e.g. "MRI analysis · 15 Sep 2026" (optional).
  final String? linkedTo;

  Message copyWith({bool? read}) => Message(
        id: id,
        patientId: patientId,
        fromDoctor: fromDoctor,
        senderName: senderName,
        body: body,
        sentAt: sentAt,
        read: read ?? this.read,
        linkedTo: linkedTo,
      );

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        patientId: json['patient_id'] as String,
        fromDoctor: json['from_doctor'] as bool,
        senderName: json['sender_name'] as String,
        body: json['body'] as String,
        sentAt: DateTime.parse(json['created_at'] as String).toLocal(),
        read: json['read_at'] != null,
        linkedTo: json['linked_to'] as String?,
      );
}

/// One conversation in the doctor's inbox.
class MessageThread {
  const MessageThread({
    required this.patientId,
    required this.patientName,
    required this.last,
    required this.unread,
  });

  final String patientId;
  final String patientName;
  final Message last;

  /// Messages from the patient the doctor hasn't read.
  final int unread;
}
