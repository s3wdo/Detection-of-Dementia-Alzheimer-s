import '../../core/auth/session.dart';

// FICTIONAL demo users for development only. Not real people or records.

const demoDoctor = Session(
  userId: 'demo-doctor-001',
  fullName: 'Dr. Ahmed Khan',
  role: UserRole.doctor,
  subtitle: 'Neurologist',
  isDemo: true,
);

const demoPatient = Session(
  userId: 'demo-patient-1024',
  fullName: 'Sarah Johnson',
  role: UserRole.patient,
  subtitle: 'Patient ID P-1024',
  patientId: 'p-1024',
  isDemo: true,
);
