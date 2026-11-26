import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session_controller.dart';
import '../../core/data/repository_providers.dart';
import 'data/models/counselling_models.dart';

final resourcesProvider = FutureProvider<List<Resource>>(
  (ref) => ref.watch(counsellingRepositoryProvider).resources(),
);

final resourceProvider = FutureProvider.family<Resource, String>(
  (ref, slug) => ref.watch(counsellingRepositoryProvider).resource(slug),
);

class CounsellingChatState {
  const CounsellingChatState({this.entries = const [], this.sending = false, this.error, this.lastQuestion});

  final List<ChatEntry> entries;
  final bool sending;

  /// Set when the last question could not be answered.
  final String? error;
  final String? lastQuestion;
}

/// Conversation with the counselling prototype (kept in memory for this session).
class CounsellingChatController extends Notifier<CounsellingChatState> {
  @override
  CounsellingChatState build() => const CounsellingChatState();

  Future<void> send(String question) async {
    final text = question.trim();
    if (text.isEmpty || state.sending) return;
    final patientId = ref.read(sessionControllerProvider)?.patientId;
    if (patientId == null) return;

    state = CounsellingChatState(
      entries: [...state.entries, ChatEntry(fromPatient: true, text: text)],
      sending: true,
      lastQuestion: text,
    );
    try {
      final reply = await ref.read(counsellingRepositoryProvider).ask(text, patientId: patientId);
      state = CounsellingChatState(
        entries: [
          ...state.entries,
          ChatEntry(fromPatient: false, text: reply.text, kind: reply.kind, sources: reply.sources),
        ],
      );
    } catch (e) {
      state = CounsellingChatState(entries: state.entries, error: 'No answer could be loaded. $e', lastQuestion: text);
    }
  }

  /// Asks the failed question again (without adding it twice).
  Future<void> retry() async {
    final q = state.lastQuestion;
    if (q == null) return;
    final entries = [...state.entries];
    if (entries.isNotEmpty && entries.last.fromPatient) entries.removeLast();
    state = CounsellingChatState(entries: entries);
    await send(q);
  }
}

final counsellingChatProvider =
    NotifierProvider<CounsellingChatController, CounsellingChatState>(CounsellingChatController.new);
