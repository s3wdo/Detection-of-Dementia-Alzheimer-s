import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/repository_providers.dart';
import 'data/models/timeline_event.dart';

typedef TimelineArgs = ({String patientId, bool patientView});

final timelineProvider = FutureProvider.family<List<TimelineEvent>, TimelineArgs>(
  (ref, args) => ref.watch(timelineRepositoryProvider).forPatient(args.patientId, patientView: args.patientView),
);
