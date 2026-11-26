import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';

/// Password reset request. The backend endpoint does not exist yet, so the
/// screen says so instead of pretending an email was sent.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _notice = _email.text.trim().isEmpty
        ? 'Enter the email address of your NeuroSense account.'
        : "Passwords can't be reset in the app. Please ask your clinic to set a new one for you.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xxl),
          children: [
            const Text('Forgot password', style: AppTextStyles.display),
            const SizedBox(height: AppSpacing.xs),
            Text("Enter your email and we'll send you a link to reset your password.",
                style: AppTextStyles.body.copyWith(color: AppColors.muted)),
            const SizedBox(height: AppSpacing.xxl),
            AppTextField(
              label: 'Email',
              controller: _email,
              hint: 'name@example.com',
              keyboardType: TextInputType.emailAddress,
              prefixIcon: Icons.mail_outline_rounded,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.xxl),
            AppButton(label: 'Send reset link', onPressed: _submit),
            if (_notice != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTint,
                    borderRadius: BorderRadius.circular(AppRadii.tile),
                  ),
                  child: Text(_notice!, style: AppTextStyles.bodySmall),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
