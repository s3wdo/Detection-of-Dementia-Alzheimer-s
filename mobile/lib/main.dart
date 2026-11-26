import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';

/// Run with demo data:  flutter run --dart-define=USE_FIXTURES=true
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final savedServer = await ServerAddress.load();
  runApp(
    ProviderScope(
      overrides: [serverAddressProvider.overrideWith(() => ServerAddress(savedServer))],
      // No automatic retries for now: a "server not connected" error should be
      // shown straight away. Retry will be configured with the real API.
      retry: (retryCount, error) => null,
      child: const NeuroSenseApp(),
    ),
  );
}
