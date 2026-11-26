import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores auth tokens in the platform keystore (Android Keystore / iOS Keychain).
/// In a browser the tokens are kept in memory only (signing in again after a
/// reload): the browser keystore needs HTTPS, which development servers lack.
class TokenStorage {
  TokenStorage([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';

  static final Map<String, String> _memory = {};

  Future<String?> readAccessToken() async => kIsWeb ? _memory[_accessKey] : _storage.read(key: _accessKey);
  Future<String?> readRefreshToken() async => kIsWeb ? _memory[_refreshKey] : _storage.read(key: _refreshKey);

  Future<void> saveTokens({required String access, required String refresh}) async {
    if (kIsWeb) {
      _memory[_accessKey] = access;
      _memory[_refreshKey] = refresh;
      return;
    }
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  Future<void> clear() async {
    if (kIsWeb) {
      _memory.clear();
      return;
    }
    await _storage.deleteAll();
  }
}

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());
