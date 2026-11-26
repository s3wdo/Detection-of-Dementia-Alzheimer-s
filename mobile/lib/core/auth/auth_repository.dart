import 'session.dart';
import '../data/user_facing_error.dart';

/// What the app needs from authentication.
/// API: POST /auth/login, POST /auth/logout, GET /me.
abstract interface class AuthRepository {
  Future<Session> signIn({required String email, required String password});
  Future<void> signOut();

  /// The session saved on this device, or null when the user must sign in.
  Future<Session?> restore();
}

/// User-facing authentication failure.
class AuthException implements UserFacingError {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
