import 'models/doctor_note.dart';
import 'models/patient.dart';

typedef PatientQuery = ({String text, PatientFilter filter});

/// The doctor's assigned patients. Real version: GET /patients?search=,
/// GET /patients/{pid} — the backend only returns patients assigned to the doctor.
abstract interface class PatientsRepository {
  Future<List<Patient>> listAssigned(PatientQuery query);
  Future<Patient> getPatient(String patientId);

  /// Doctor-only notes, newest first. Real version: GET /patients/{pid}/notes.
  Future<List<DoctorNote>> notes(String patientId);

  /// Real version: POST /patients/{pid}/notes. Throws [ArgumentError] when empty.
  Future<DoctorNote> addNote(String patientId, {required String body, required String author});

  /// Updates contact details. Real version: PATCH /patients/{pid}.
  Future<Patient> updateContact(String patientId, {required String phone, required String emergencyContact});
}
