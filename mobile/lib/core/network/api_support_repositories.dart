import '../../features/appointments/data/appointments_repository.dart';
import '../../features/appointments/data/models/appointment.dart';
import '../../features/messages/data/messages_repository.dart';
import '../../features/messages/data/models/message.dart';
import '../../features/notifications/data/models/app_notification.dart';
import '../../features/notifications/data/notifications_repository.dart';
import '../../features/profile/data/profile_repository.dart';
import '../auth/session.dart';
import 'api_client.dart';

// Appointments, messages, notifications and profile from the NeuroSense server.
// As with the clinical repositories, identity comes from the access token:
// ids and names passed in by screens are not sent.

class ApiAppointmentsRepository implements AppointmentsRepository {
  ApiAppointmentsRepository(this._api);
  final ApiClient _api;

  Future<List<Appointment>> _list() async => (await _api.getList('/appointments')).map(Appointment.fromJson).toList();

  @override
  Future<List<Appointment>> listForDoctor() => _list();

  @override
  Future<List<Appointment>> listForPatient(String patientId) => _list();

  @override
  Future<Appointment> get(String appointmentId) async =>
      Appointment.fromJson(await _api.getJson('/appointments/$appointmentId'));

  @override
  Future<Appointment> request(AppointmentRequest request) async {
    final errors = request.validate(DateTime.now());
    if (errors.isNotEmpty) throw ArgumentError(errors.values.first);
    return Appointment.fromJson(await _api.postJson('/appointments', body: {
      'reason': request.reason.trim(),
      'starts_at': request.startsAt.toUtc().toIso8601String(),
      'notes': request.notes.trim(),
    }));
  }

  @override
  Future<Appointment> setStatus(String appointmentId, AppointmentStatus status) async =>
      Appointment.fromJson(await _api.patchJson('/appointments/$appointmentId', body: {'status': status.name}));

  @override
  Future<Appointment> reschedule(String appointmentId, DateTime startsAt) async => Appointment.fromJson(
      await _api.patchJson('/appointments/$appointmentId', body: {'starts_at': startsAt.toUtc().toIso8601String()}));
}

class ApiMessagesRepository implements MessagesRepository {
  ApiMessagesRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<MessageThread>> threadsForDoctor() async => [
        for (final t in await _api.getList('/messages/threads'))
          MessageThread(
            patientId: t['patient_id'] as String,
            patientName: t['patient_name'] as String,
            last: Message.fromJson((t['last'] as Map).cast<String, dynamic>()),
            unread: t['unread'] as int,
          ),
      ];

  @override
  Future<List<Message>> thread(String patientId) async =>
      (await _api.getList('/patients/$patientId/messages')).map(Message.fromJson).toList();

  @override
  Future<Message> send({
    required String patientId,
    required String body,
    required bool fromDoctor,
    required String senderName,
    String? linkedTo,
  }) async {
    if (body.trim().isEmpty) throw ArgumentError('Write a message first.');
    return Message.fromJson(await _api.postJson('/patients/$patientId/messages', body: {
      'body': body.trim(),
      if (linkedTo != null) 'linked_to': linkedTo,
    }));
  }

  @override
  Future<void> markThreadRead(String patientId, {required bool readerIsDoctor}) =>
      _api.post('/patients/$patientId/messages/read');
}

class ApiNotificationsRepository implements NotificationsRepository {
  ApiNotificationsRepository(this._api, {required this.role});
  final ApiClient _api;

  /// The signed-in user's role, used to pick the screen a notification opens.
  final UserRole? Function() role;

  /// The server says what a notification is about; the app decides which
  /// screen that is, so the server never needs to know the app's routes.
  static String? routeFor(Map<String, dynamic> n, UserRole? role) {
    final type = n['entity_type'] as String?;
    final id = n['entity_id'] as String?;
    final patientId = n['patient_id'] as String?;
    final doctor = role == UserRole.doctor;
    return switch (type) {
      'analysis' when id != null => doctor && patientId != null
          ? '/doctor/patients/$patientId/analyses/$id'
          : doctor
              ? null
              : '/patient/results/$id',
      'appointment' when id != null => doctor ? '/doctor/appointments/$id' : '/patient/appointments/$id',
      'message' => doctor
          ? (patientId == null ? '/doctor/messages' : '/doctor/messages/$patientId')
          : '/patient/messages',
      'patient' when doctor && patientId != null => '/doctor/patients/$patientId',
      'upload' when !doctor => '/patient/upload',
      _ => null,
    };
  }

  @override
  Future<List<AppNotification>> listFor(String userId) async => [
        for (final n in await _api.getList('/notifications'))
          AppNotification.fromJson({...n, 'route': routeFor(n, role())}),
      ];

  @override
  Future<void> markRead(String notificationId) => _api.post('/notifications/$notificationId/read');

  @override
  Future<void> markAllRead(String userId) => _api.post('/notifications/read-all');
}

class ApiProfileRepository implements ProfileRepository {
  ApiProfileRepository(this._api);
  final ApiClient _api;

  static List<ProfileField> _fields(Object? list) => [
        for (final f in list as List) (label: (f as Map)['label'] as String, value: f['value'] as String),
      ];

  @override
  Future<ProfileDetails> detailsFor(Session session) async {
    final json = await _api.getJson('/me/profile');
    return ProfileDetails(personal: _fields(json['personal']), health: _fields(json['health']));
  }
}
