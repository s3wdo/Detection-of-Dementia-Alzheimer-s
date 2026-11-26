import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session_controller.dart';
import '../../core/data/repository_providers.dart';
import 'data/models/app_notification.dart';

/// The signed-in user's notifications, with read/unread actions.
class NotificationsController extends AsyncNotifier<List<AppNotification>> {
  @override
  Future<List<AppNotification>> build() async {
    final session = ref.watch(sessionControllerProvider);
    if (session == null) return const [];
    return ref.watch(notificationsRepositoryProvider).listFor(session.userId);
  }

  Future<void> markRead(String id) async {
    await ref.read(notificationsRepositoryProvider).markRead(id);
    final current = state.value;
    if (current != null) {
      state = AsyncData([for (final n in current) n.id == id ? n.copyWith(read: true) : n]);
    }
  }

  Future<void> markAllRead() async {
    final session = ref.read(sessionControllerProvider);
    if (session == null) return;
    await ref.read(notificationsRepositoryProvider).markAllRead(session.userId);
    final current = state.value;
    if (current != null) state = AsyncData([for (final n in current) n.copyWith(read: true)]);
  }
}

final notificationsProvider =
    AsyncNotifierProvider<NotificationsController, List<AppNotification>>(NotificationsController.new);

/// Number shown as the dot on the bell icon.
final unreadCountProvider = Provider<int>(
  (ref) => ref.watch(notificationsProvider).value?.where((n) => !n.read).length ?? 0,
);
