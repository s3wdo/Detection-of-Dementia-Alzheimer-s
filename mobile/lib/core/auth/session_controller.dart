import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dev/demo_auth_repository.dart';
import '../config/app_config.dart';
import '../network/api_client.dart';
import '../storage/token_storage.dart';
import 'api_auth_repository.dart';
import 'auth_repository.dart';
import 'session.dart';

/// Picks the auth implementation: demo (fixtures) or the NeuroSense server.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  return config.useFixtures
      ? DemoAuthRepository()
      : ApiAuthRepository(ref.watch(apiClientProvider), ref.watch(tokenStorageProvider));
});

/// Holds the current session (null = signed out). The router listens to it.
class SessionController extends Notifier<Session?> {
  @override
  Session? build() {
    // The server rejected the session (refresh failed): back to the login screen.
    ref.listen(sessionExpiredProvider, (_, __) => state = null);
    return null;
  }

  Future<void> signIn(String email, String password) async {
    state = await ref.read(authRepositoryProvider).signIn(email: email, password: password);
  }

  /// Signs back in with the tokens saved on this device, if they still work.
  Future<void> restore() async {
    final session = await ref.read(authRepositoryProvider).restore();
    if (session != null && state == null) state = session;
  }

  /// Development-only: enter the app as a fictional demo user.
  Future<void> signInAsDemo(UserRole role) async {
    final repo = ref.read(authRepositoryProvider);
    if (repo is! DemoAuthRepository) {
      throw const AuthException('Demo login is only available in development mode.');
    }
    state = await repo.signInAsDemo(role);
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = null;
  }
}

final sessionControllerProvider = NotifierProvider<SessionController, Session?>(SessionController.new);
