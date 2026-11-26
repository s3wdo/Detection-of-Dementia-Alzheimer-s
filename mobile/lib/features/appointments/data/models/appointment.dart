enum AppointmentStatus {
  requested,
  confirmed,
  cancelled,
  completed;

  static AppointmentStatus fromJson(String value) => AppointmentStatus.values.byName(value);
}

/// An appointment between a patient and a doctor.
/// (Full appointment screens are built in Phase 4; dashboards use it now.)
class Appointment {
  const Appointment({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.doctorName,
    required this.startsAt,
    required this.durationMinutes,
    required this.title,
    required this.status,
    this.location,
  });

  final String id;
  final String patientId;
  final String patientName;
  final String doctorName;
  final DateTime startsAt;
  final int durationMinutes;
  final String title;
  final AppointmentStatus status;
  final String? location;

  String get statusLabel => '${status.name[0].toUpperCase()}${status.name.substring(1)}';

  Appointment copyWith({AppointmentStatus? status, DateTime? startsAt}) => Appointment(
        id: id,
        patientId: patientId,
        patientName: patientName,
        doctorName: doctorName,
        startsAt: startsAt ?? this.startsAt,
        durationMinutes: durationMinutes,
        title: title,
        status: status ?? this.status,
        location: location,
      );

  bool isUpcoming(DateTime now) =>
      startsAt.isAfter(now) && (status == AppointmentStatus.confirmed || status == AppointmentStatus.requested);

  factory Appointment.fromJson(Map<String, dynamic> json) => Appointment(
        id: json['id'] as String,
        patientId: json['patient_id'] as String,
        patientName: json['patient_name'] as String,
        doctorName: json['doctor_name'] as String,
        startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
        durationMinutes: json['duration_min'] as int,
        title: json['reason'] as String,
        status: AppointmentStatus.fromJson(json['status'] as String),
        location: json['location'] as String?,
      );
}
