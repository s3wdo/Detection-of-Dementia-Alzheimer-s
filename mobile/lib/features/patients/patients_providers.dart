import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/repository_providers.dart';
import 'data/models/doctor_note.dart';
import 'data/models/patient.dart';
import 'data/patients_repository.dart';

/// Current search text + filter on the doctor's patient list.
class PatientQueryController extends Notifier<PatientQuery> {
  @override
  PatientQuery build() => (text: '', filter: PatientFilter.all);

  void setText(String text) => state = (text: text, filter: state.filter);
  void setFilter(PatientFilter filter) => state = (text: state.text, filter: filter);
}

final patientQueryProvider = NotifierProvider<PatientQueryController, PatientQuery>(PatientQueryController.new);

final patientListProvider = FutureProvider<List<Patient>>(
  (ref) => ref.watch(patientsRepositoryProvider).listAssigned(ref.watch(patientQueryProvider)),
);

final patientProvider = FutureProvider.family<Patient, String>(
  (ref, patientId) => ref.watch(patientsRepositoryProvider).getPatient(patientId),
);

/// How many assigned patients fall under each filter (for the chip counts).
final patientCountsProvider = FutureProvider<Map<PatientFilter, int>>((ref) async {
  final all = await ref.watch(patientsRepositoryProvider).listAssigned((text: '', filter: PatientFilter.all));
  return {for (final f in PatientFilter.values) f: all.where((p) => p.matchesFilter(f)).length};
});

/// Doctor-only notes for one patient, newest first.
final patientNotesProvider = FutureProvider.family<List<DoctorNote>, String>(
  (ref, patientId) => ref.watch(patientsRepositoryProvider).notes(patientId),
);
