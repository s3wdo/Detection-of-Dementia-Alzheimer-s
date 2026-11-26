/// Doctors and patients use the clinical screens. Admins only manage accounts.
enum UserRole {
  doctor,
  patient,
  admin;

  static UserRole fromJson(String value) => UserRole.values.byName(value);
  String toJson() => name;
}

/// The signed-in user, as the app sees them.
class Session {
  const Session({
    required this.userId,
    required this.fullName,
    required this.role,
    required this.subtitle,
    this.patientId,
    this.isDemo = false,
  });

  final String userId;
  final String fullName;
  final UserRole role;

  /// Short line under the name, e.g. "Neurologist" or "Patient ID P-1024".
  final String subtitle;

  /// The patient record this user owns (patients only). Comes from the token,
  /// never from user input, so a patient can only ask for their own data.
  final String? patientId;

  /// True when this session comes from the development-only demo login.
  final bool isDemo;

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        userId: json['id'] as String,
        fullName: json['full_name'] as String,
        role: UserRole.fromJson(json['role'] as String),
        subtitle: json['subtitle'] as String? ?? '',
        patientId: json['patient_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': userId,
        'full_name': fullName,
        'role': role.toJson(),
        'subtitle': subtitle,
        if (patientId != null) 'patient_id': patientId,
      };
}
