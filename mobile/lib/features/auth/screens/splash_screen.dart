import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/config/app_config.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/neuro_logo.dart';
import '../widgets/wave_painter.dart';

/// Dark launch screen, shown briefly on start.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  static const duration = Duration(milliseconds: 1600);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // With the real server, sign back in from the tokens saved on this device.
    // The router redirect then sends signed-in users to their home.
    if (!ref.read(appConfigProvider).useFixtures) {
      Future.microtask(() => ref.read(sessionControllerProvider.notifier).restore());
    }
    _timer = Timer(SplashScreen.duration, () {
      if (mounted) context.go(Routes.welcome);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.launch,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: BrainLinePainter())),
          Center(child: NeuroWordmark(onDark: true, logoSize: 72)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Text(
              'Supporting informed healthcare decisions.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.onNavyMuted, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
