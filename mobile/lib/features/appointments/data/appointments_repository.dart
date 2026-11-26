import 'models/appointment.dart';

/// A patient's request for an appointment (POST /appointments).
class AppointmentRequest {
  const AppointmentRequest({
    required this.patientId,
    required this.reason,
    required this.startsAt,
    this.notes = '',
  });

  final String patientId;
  final String reason;
  final DateTime startsAt;
  final String notes;

  /// Field → error. Empty when valid.
  Map<String, String> validate(DateTime now) => {
        if (reason.trim().isEmpty) 'reason': 'Choose a reason for the appointment.',
        if (!startsAt.isAfter(now)) 'startsAt': 'Choose a time in the future.',
      };
}

/// Real version: GET/POST /appointments, PATCH /appointments/{id}.
abstract interface class AppointmentsRepository {
  Future<List<Appointment>> listForDoctor();
  Future<List<Appointment>> listForPatient(String patientId);
  Future<Appointment> get(String appointmentId);
  Future<Appointment> request(AppointmentRequest request);
  Future<Appointment> setStatus(String appointmentId, AppointmentStatus status);
  Future<Appointment> reschedule(String appointmentId, DateTime startsAt);
}
