import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/neuro_logo.dart';
import '../widgets/wave_painter.dart';

/// Welcome screen (design section 01 "Splash"): dark navy, serif wordmark,
/// white "Log in" and an outlined "How do I get an account?".
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.launch,
      body: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: BrainLinePainter())),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 72),
                        const NeuroLogo(size: 72, onDark: true),
                        const SizedBox(height: AppSpacing.xxl),
                        Semantics(
                          header: true,
                          child: const Text(
                            'NeuroSense',
                            style: TextStyle(
                              fontFamily: AppTextStyles.serif,
                              fontSize: 44,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.1,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text('AI-ASSISTED MRI ANALYSIS',
                            style: AppTextStyles.overline
                                .copyWith(fontSize: 13, letterSpacing: 2.6, color: AppColors.onNavyAccent)),
                        const SizedBox(height: AppSpacing.xxl),
                        const Text(
                          'Supporting informed healthcare decisions.',
                          style: TextStyle(
                            fontFamily: AppTextStyles.serif,
                            fontSize: 24,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFE4E9F5),
                            height: 1.3,
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(height: AppSpacing.xxl),
                        FilledButton(
                          onPressed: () => context.push(Routes.login),
                          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.navy),
                          child: const Text('Log in'),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        OutlinedButton(
                          onPressed: () => showAppBottomSheet<void>(
                            context,
                            title: 'Getting an account',
                            child: const Text(
                              'NeuroSense accounts are created by your clinic, so doctors and patients are verified. '
                              'Please contact your clinic to get access.',
                              style: AppTextStyles.body,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: AppColors.onNavyAccent, width: 1.4),
                          ),
                          child: const Text('How do I get an account?'),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.school_outlined, size: 16, color: AppColors.onNavyMuted),
                            SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Academic project · Not a certified medical device',
                                style: TextStyle(fontSize: 13, color: AppColors.onNavyMuted),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
