import '../network/api_client.dart';
import '../network/api_error.dart';
import '../storage/token_storage.dart';
import 'auth_repository.dart';
import 'session.dart';

/// Sign-in against the NeuroSense server. Tokens live only in secure storage.
class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStorage _tokens;

  static const unreachable =
      "Couldn't reach the NeuroSense server. Check your connection and that the server is running.";

  @override
  Future<Session> signIn({required String email, required String password}) async {
    try {
      final data = await _api.postJson('/auth/login', body: {'email': email, 'password': password});
      await _tokens.saveTokens(access: data['access_token'] as String, refresh: data['refresh_token'] as String);
      return Session.fromJson(data['user'] as Map<String, dynamic>);
    } on ApiError catch (e) {
      // Wrong password, rate limit and validation messages come from the server.
      throw AuthException(e.statusCode == null ? unreachable : e.message);
    }
  }

  @override
  Future<void> signOut() async {
    final refresh = await _tokens.readRefreshToken();
    await _tokens.clear();
    if (refresh == null) return;
    try {
      await _api.post('/auth/logout', body: {'refresh_token': refresh});
    } catch (_) {
      // Signed out on this device either way; the token expires on the server.
    }
  }

  /// The saved session, if the stored tokens still work.
  @override
  Future<Session?> restore() async {
    try {
      if (await _tokens.readRefreshToken() == null) return null;
      return Session.fromJson(await _api.getJson('/me'));
    } catch (_) {
      return null;
    }
  }
}
