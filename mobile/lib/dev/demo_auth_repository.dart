import '../core/auth/auth_repository.dart';
import '../core/auth/session.dart';
import 'fixtures/demo_users.dart';

/// DEVELOPMENT ONLY. Lets the team enter either role with fictional data.
/// This is not authentication: no credentials are checked or stored.
/// Only wired in when the app runs with --dart-define=USE_FIXTURES=true.
class DemoAuthRepository implements AuthRepository {
  Future<Session> signInAsDemo(UserRole role) async {
    // Small delay so loading states are visible during demos.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return role == UserRole.doctor ? demoDoctor : demoPatient;
  }

  @override
  Future<Session> signIn({required String email, required String password}) async => throw const AuthException(
      'Email sign-in is off in demo mode. Use the demo login below, or run the app against the NeuroSense server.');

  @override
  Future<void> signOut() async {}

  @override
  Future<Session?> restore() async => null;
}
