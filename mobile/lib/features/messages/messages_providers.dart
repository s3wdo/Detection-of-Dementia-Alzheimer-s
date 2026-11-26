import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/repository_providers.dart';
import 'data/models/message.dart';

final doctorThreadsProvider = FutureProvider<List<MessageThread>>(
  (ref) => ref.watch(messagesRepositoryProvider).threadsForDoctor(),
);

/// One conversation (by patient id), oldest first.
final threadProvider = FutureProvider.family<List<Message>, String>(
  (ref, patientId) => ref.watch(messagesRepositoryProvider).thread(patientId),
);
