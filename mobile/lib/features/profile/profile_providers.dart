import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session_controller.dart';
import '../../core/data/repository_providers.dart';
import 'data/profile_repository.dart';

final profileDetailsProvider = FutureProvider<ProfileDetails>((ref) {
  final session = ref.watch(sessionControllerProvider);
  if (session == null) throw StateError('Not signed in');
  return ref.watch(profileRepositoryProvider).detailsFor(session);
});

/// Notification preference switches. Kept in memory for now; they will be
/// saved to the user's account once the backend exists.
class NotificationPrefsController extends Notifier<Map<String, bool>> {
  static const keys = ['Reviewed results', 'Messages from my care team', 'Appointment reminders', 'New analyses'];

  @override
  Map<String, bool> build() => {for (final k in keys) k: true};

  void toggle(String key, bool value) => state = {...state, key: value};
}

final notificationPrefsProvider =
    NotifierProvider<NotificationPrefsController, Map<String, bool>>(NotificationPrefsController.new);
