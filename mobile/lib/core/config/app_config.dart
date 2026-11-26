import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Build-time configuration, passed with --dart-define.
///
///   flutter run --dart-define=USE_FIXTURES=true
///   flutter run --dart-define=API_BASE_URL=https://example.org/api/v1
class AppConfig {
  const AppConfig({required this.useFixtures, required this.apiBaseUrl});

  /// When true the app uses fictional demo data from lib/dev/ and shows the
  /// development-only demo login. Never enable this in a real release.
  final bool useFixtures;

  /// Base URL of the future FastAPI backend (not called in this stage).
  final String apiBaseUrl;

  factory AppConfig.fromEnvironment() => const AppConfig(
        useFixtures: bool.fromEnvironment('USE_FIXTURES'),
        apiBaseUrl: String.fromEnvironment(
          'API_BASE_URL',
          // 10.0.2.2 is the host machine as seen from the Android emulator.
          defaultValue: 'http://10.0.2.2:8000/api/v1',
        ),
      );
}

/// Overridden in tests to switch demo mode on or off.
final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.fromEnvironment());

/// Turns what a person types ("192.168.1.20") into a full API address
/// ("http://192.168.1.20:8000/api/v1"). Empty or unreadable input gives null.
String? normalizeServerAddress(String input) {
  var value = input.trim();
  if (value.isEmpty) return null;
  if (!value.contains('://')) value = 'http://$value';
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return null;
  final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 8000);
  return '${uri.scheme}://${uri.host}:$port/api/v1';
}

/// A server address set on this device from the login screen. It replaces the
/// build-time API_BASE_URL, so a development build can follow the PC when its
/// network address changes. Null means "use the build-time address".
class ServerAddress extends Notifier<String?> {
  ServerAddress([this._saved]);

  final String? _saved;
  static const _key = 'server_address';

  /// Reads the saved address at startup. Any storage problem means "none".
  static Future<String?> load() async {
    if (kIsWeb) return null;
    try {
      return await const FlutterSecureStorage().read(key: _key);
    } catch (_) {
      return null;
    }
  }

  @override
  String? build() => _saved;

  Future<void> set(String? address) async {
    state = address;
    if (kIsWeb) return;
    try {
      const storage = FlutterSecureStorage();
      await (address == null ? storage.delete(key: _key) : storage.write(key: _key, value: address));
    } catch (_) {
      // Still used until the app closes.
    }
  }
}

final serverAddressProvider = NotifierProvider<ServerAddress, String?>(ServerAddress.new);

/// The API address in use: the one set on this device, else the build-time one.
/// In a browser the default is the server the page was loaded from.
final apiBaseUrlProvider = Provider<String>((ref) =>
    ref.watch(serverAddressProvider) ??
    (kIsWeb ? '${Uri.base.origin}/api/v1' : ref.watch(appConfigProvider).apiBaseUrl));
