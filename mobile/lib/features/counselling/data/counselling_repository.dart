import 'models/counselling_models.dart';

/// Real version: GET /counselling/resources, POST /counselling/sessions/{id}/messages.
abstract interface class CounsellingRepository {
  Future<List<Resource>> resources();
  Future<Resource> resource(String slug);

  /// Answers a patient question. The patient id comes from the session so the
  /// answer can only use that patient's released results.
  Future<CounsellingReply> ask(String question, {required String patientId});
}
