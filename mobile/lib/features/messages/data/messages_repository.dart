import 'models/message.dart';

/// Real version: GET/POST /patients/{pid}/messages.
abstract interface class MessagesRepository {
  /// Doctor inbox, newest first.
  Future<List<MessageThread>> threadsForDoctor();

  /// One conversation, oldest first.
  Future<List<Message>> thread(String patientId);

  /// [linkedTo] optionally names what the message is about (e.g. an analysis).
  Future<Message> send({
    required String patientId,
    required String body,
    required bool fromDoctor,
    required String senderName,
    String? linkedTo,
  });

  /// Marks the other side's messages as read.
  Future<void> markThreadRead(String patientId, {required bool readerIsDoctor});
}
