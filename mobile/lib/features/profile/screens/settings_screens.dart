import 'package:flutter/material.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/auth/session_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../profile_providers.dart';

/// Notification preference switches (kept in memory until the backend exists).
class NotificationPrefsScreen extends ConsumerWidget {
  const NotificationPrefsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPrefsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notification Preferences')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xxl),
        children: [
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(children: [
              for (final entry in prefs.entries)
                SwitchListTile(
                  title: Text(entry.key, style: AppTextStyles.label),
                  value: entry.value,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => ref.read(notificationPrefsProvider.notifier).toggle(entry.key, v),
                ),
            ]),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text(
            'These settings are kept on this device for now and will be saved to your account '
            'once the NeuroSense server is connected.',
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }
}

/// How NeuroSense protects data (content from the approved security model).
class SecurityPrivacyScreen extends ConsumerWidget {
  const SecurityPrivacyScreen({super.key});

  static const _items = [
    (
      Icons.key_outlined,
      'Secure authentication',
      'Passwords are never stored in readable form, and sessions expire automatically.'
    ),
    (
      Icons.wifi_outlined,
      'Local network connection',
      'In this academic prototype the app talks to the NeuroSense server over your local Wi-Fi without '
          'encryption (HTTP). Use fictional data only; a real deployment would use HTTPS.'
    ),
    (
      Icons.folder_shared_outlined,
      'Private medical records',
      'MRI scans and reports are only shown to people involved in your care.'
    ),
    (
      Icons.how_to_reg_outlined,
      'Controlled access',
      'Patients see only their own records. Doctors see only their assigned patients.'
    ),
    (
      Icons.visibility_off_outlined,
      'Doctor-only clinical notes',
      'Some working notes are kept for clinicians and never shown in the patient app.'
    ),
    (
      Icons.visibility_outlined,
      'Patient-visible information',
      'Patients see a result only after their doctor has reviewed and released it.'
    ),
  ];

  Future<void> _signOutEverywhere(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Sign out of all devices?',
      message: 'You will be signed out here and on every other device. You will need to sign in again.',
      confirmLabel: 'Sign out everywhere',
      destructive: true,
    );
    if (ok) await ref.read(sessionControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security & Privacy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xxl),
        children: [
          const Text('How NeuroSense protects your information.', style: AppTextStyles.body),
          const SizedBox(height: AppSpacing.lg),
          RowGroup(children: [
            for (final (icon, title, text) in _items) ListRowTile(icon: icon, title: title, subtitle: text),
          ]),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Change password',
            icon: Icons.password_rounded,
            variant: AppButtonVariant.secondary,
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Changing your password isn't available until the server is connected."))),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const Key('signOutEverywhere'),
            label: 'Sign out of all devices',
            icon: Icons.logout_rounded,
            variant: AppButtonVariant.secondary,
            onPressed: () => _signOutEverywhere(context, ref),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: 'NeuroSense is an academic project and is not a certified medical device. ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: 'Demonstrations use fictional patient data.'),
              ]),
              style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }
}

/// Simple help page with common questions.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static const _faq = [
    (
      'What does "model confidence" mean?',
      'It shows how strongly the AI model favoured its classification. It is not a calibrated probability '
          'and not a diagnosis. Your doctor interprets every result.'
    ),
    (
      'Who can see my results?',
      'Your assigned doctor. You see a result after your doctor has reviewed it and released it to you.'
    ),
    ('How do I contact my doctor?', 'Use Messages in the app, or contact your clinic directly for anything urgent.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xxl),
        children: [
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final (q, a) in _faq)
                ExpansionTile(
                  title: Text(q, style: AppTextStyles.label),
                  childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                  shape: const Border(),
                  children: [Text(a, style: AppTextStyles.bodySmall)],
                ),
            ]),
          ),
          const SizedBox(height: AppSpacing.lg),
          const AppCard(
            child: ListRowTile(
              icon: Icons.local_hospital_outlined,
              title: 'Contact your clinic',
              subtitle: 'For account problems or anything urgent, contact your clinic directly. '
                  'In an emergency, call your local emergency number.',
            ),
          ),
        ],
      ),
    );
  }
}
