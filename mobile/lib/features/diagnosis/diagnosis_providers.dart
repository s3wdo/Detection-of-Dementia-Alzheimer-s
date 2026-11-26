import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/repository_providers.dart';
import '../dashboard/dashboard_providers.dart';
import '../notifications/notifications_providers.dart';
import '../patients/patients_providers.dart';
import '../timeline/timeline_providers.dart';
import 'data/models/analysis.dart';
import 'data/models/analysis_job.dart';
import 'data/models/explanation.dart';
import 'data/models/mri_file.dart';
import 'data/models/upload_models.dart';
import 'services/mri_services.dart';

typedef AnalysesArgs = ({String patientId, bool patientView});
typedef AnalysisArgs = ({String analysisId, bool patientView});

/// A patient's analyses, newest first. Patient view = released only.
final analysesProvider = FutureProvider.family<List<AnalysisSummary>, AnalysesArgs>(
  (ref, args) => ref.watch(analysesRepositoryProvider).listForPatient(args.patientId, patientView: args.patientView),
);

/// One analysis (result screen, review, patient details).
final analysisProvider = FutureProvider.family<AnalysisSummary, AnalysisArgs>(
  (ref, args) => ref.watch(analysesRepositoryProvider).getAnalysis(args.analysisId, patientView: args.patientView),
);

/// The signed-in patient's own uploads, newest first (a coarse state only).
final myUploadsProvider = FutureProvider<List<PatientUpload>>(
  (ref) => ref.watch(analysesRepositoryProvider).myUploads(),
);

/// The original MRI image of an analysis, if available.
final analysisImageProvider = FutureProvider.family<Uint8List?, String>(
  (ref, analysisId) => ref.watch(analysesRepositoryProvider).imageFor(analysisId),
);

/// The model's Grad-CAM map for an analysis, or null when there is none.
final analysisExplanationProvider = FutureProvider.family<Explanation?, String>(
  (ref, analysisId) => ref.watch(analysesRepositoryProvider).explanationFor(analysisId),
);

/// Progress of a running analysis.
final analysisJobProvider = StreamProvider.family<AnalysisJob, String>(
  (ref, analysisId) => ref.watch(analysesRepositoryProvider).watchJob(analysisId),
);

/// The MRI image the doctor has picked but not yet sent for analysis.
class SelectedMriController extends Notifier<MriFile?> {
  @override
  MriFile? build() => null;

  void select(MriFile? file) => state = file;
}

final selectedMriProvider = NotifierProvider<SelectedMriController, MriFile?>(SelectedMriController.new);

/// Result of decoding the selected image on the phone (size, grayscale check).
final selectedMriInspectionProvider = FutureProvider<MriInspection?>((ref) async {
  final file = ref.watch(selectedMriProvider);
  if (file == null) return null;
  return ref.watch(mriInspectorProvider).inspect(file.bytes);
});

/// Refreshes every screen that shows clinical data after an analysis or a
/// review changes something.
void refreshClinicalData(WidgetRef ref) {
  ref.invalidate(analysesProvider);
  ref.invalidate(analysisProvider);
  ref.invalidate(patientListProvider);
  ref.invalidate(patientCountsProvider);
  ref.invalidate(patientProvider);
  ref.invalidate(timelineProvider);
  ref.invalidate(doctorDashboardProvider);
  ref.invalidate(patientDashboardProvider);
  ref.invalidate(notificationsProvider);
}
