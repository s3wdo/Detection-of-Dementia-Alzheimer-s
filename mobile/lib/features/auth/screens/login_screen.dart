import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/config/app_config.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/dev_mode_banner.dart';
import '../../../core/widgets/neuro_logo.dart';
import '../../../core/data/user_facing_error.dart';
import '../../../core/network/server_finder.dart';
import '../widgets/server_address_dialog.dart';

/// Email (or account ID) + password login. Real sign-in needs the backend; until then it
/// shows an honest "not connected" message. In development builds a clearly
/// marked demo-login panel is shown underneath.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _hidePassword = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your email or ID, and your password.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(sessionControllerProvider.notifier).signIn(_email.text.trim(), _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Development builds reach the server on the local network, where the PC's
  /// address changes. This lets the address be corrected without a new build.
  Future<void> _editServer() async {
    final entered = await showDialog<String>(
      context: context,
      builder: (_) => ServerAddressDialog(current: ref.read(apiBaseUrlProvider), showFind: canFindServer),
    );
    if (entered == null) return;
    await ref.read(serverAddressProvider.notifier).set(normalizeServerAddress(entered));
  }

  @override
  Widget build(BuildContext context) {
    final demoEnabled = ref.watch(appConfigProvider).useFixtures;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xxl),
          children: [
            const SizedBox(height: AppSpacing.md),
            const Align(alignment: Alignment.centerLeft, child: NeuroLogo(size: 56)),
            const SizedBox(height: AppSpacing.xl),
            Semantics(header: true, child: const Text('Log in', style: AppTextStyles.display)),
            const SizedBox(height: AppSpacing.xs),
            Text('Welcome back to NeuroSense', style: AppTextStyles.body.copyWith(fontSize: 17)),
            const SizedBox(height: AppSpacing.xxl),
            AutofillGroup(
              child: Column(
                children: [
                  AppTextField(
                    label: 'Email or ID',
                    controller: _email,
                    hint: 'name@example.com or P-1024',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    prefixIcon: Icons.mail_outline_rounded,
                    autofillHints: const [AutofillHints.email],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppTextField(
                    label: 'Password',
                    controller: _password,
                    obscureText: _hidePassword,
                    textInputAction: TextInputAction.done,
                    prefixIcon: Icons.lock_outline_rounded,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _submit(),
                    suffix: IconButton(
                      tooltip: _hidePassword ? 'Show password' : 'Hide password',
                      icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _hidePassword = !_hidePassword),
                    ),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => context.push(Routes.forgotPassword),
                child: const Text('Forgot password?'),
              ),
            ),
            if (_error != null) ...[
              Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.errorTint,
                    borderRadius: BorderRadius.circular(AppRadii.tile),
                  ),
                  child: Text(_error!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            AppButton(label: 'Log in', loading: _loading, onPressed: _submit),
            if (!demoEnabled)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('serverAddress'),
                  onPressed: _editServer,
                  child: Text('Server: ${ref.watch(apiBaseUrlProvider)}', style: AppTextStyles.caption),
                ),
              ),
            if (demoEnabled) ...[
              const SizedBox(height: AppSpacing.xxxl),
              const DevModeBanner(
                message: 'Demo login opens the app with fictional data. It is not real authentication '
                    'and is removed in release builds.',
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                key: const Key('openDemoLogin'),
                label: 'Open demo login',
                icon: Icons.science_outlined,
                variant: AppButtonVariant.secondary,
                onPressed: () => context.push(Routes.devLogin),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
