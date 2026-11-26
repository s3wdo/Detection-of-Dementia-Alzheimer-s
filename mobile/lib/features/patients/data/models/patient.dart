import '../../../diagnosis/data/models/analysis.dart';

enum Sex {
  female('Female'),
  male('Male');

  const Sex(this.label);
  final String label;
}

/// Filters on the doctor's patient list.
enum PatientFilter {
  all('All'),
  needsReview('Needs review'),
  reviewed('Reviewed'),
  noAnalyses('No analyses');

  const PatientFilter(this.label);
  final String label;
}

/// A patient assigned to the signed-in doctor.
class Patient {
  const Patient({
    required this.id,
    required this.mrn,
    required this.fullName,
    required this.dateOfBirth,
    required this.sex,
    required this.phone,
    required this.email,
    required this.emergencyContact,
    this.latestAnalysis,
  });

  final String id;

  /// Patient number shown in the UI, e.g. "P-1024".
  final String mrn;
  final String fullName;
  final DateTime dateOfBirth;
  final Sex sex;
  final String phone;
  final String email;
  final String emergencyContact;

  /// Most recent AI analysis, if any (doctor view).
  final AnalysisSummary? latestAnalysis;

  bool matchesFilter(PatientFilter filter) => switch (filter) {
        PatientFilter.all => true,
        PatientFilter.needsReview => latestAnalysis != null && !latestAnalysis!.status.isReviewed,
        PatientFilter.reviewed => latestAnalysis != null && latestAnalysis!.status.isReviewed,
        PatientFilter.noAnalyses => latestAnalysis == null,
      };

  /// Case-insensitive match on name or patient number.
  bool matchesQuery(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty || fullName.toLowerCase().contains(q) || mrn.toLowerCase().contains(q);
  }

  factory Patient.fromJson(Map<String, dynamic> json) => Patient(
        id: json['id'] as String,
        mrn: json['mrn'] as String,
        fullName: json['full_name'] as String,
        dateOfBirth: DateTime.parse(json['date_of_birth'] as String),
        sex: Sex.values.byName(json['sex'] as String),
        phone: json['phone'] as String? ?? '',
        email: json['email'] as String? ?? '',
        emergencyContact: json['emergency_contact'] as String? ?? '',
        latestAnalysis: json['latest_analysis'] == null
            ? null
            : AnalysisSummary.fromJson(json['latest_analysis'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'mrn': mrn,
        'full_name': fullName,
        'date_of_birth': dateOfBirth.toIso8601String(),
        'sex': sex.name,
        'phone': phone,
        'email': email,
        'emergency_contact': emergencyContact,
        if (latestAnalysis != null) 'latest_analysis': latestAnalysis!.toJson(),
      };
}
