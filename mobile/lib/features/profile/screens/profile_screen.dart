import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/layout_widgets.dart';

/// Profile & settings, shared by both roles: identity, grouped settings, log out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Log out?',
      message: 'You will need to sign in again to use NeuroSense.',
      confirmLabel: 'Log out',
      destructive: true,
    );
    if (ok) await ref.read(sessionControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    if (session == null) return const SizedBox.shrink();
    final isDoctor = session.role == UserRole.doctor;
    void open(String page) => context.push(Routes.profileSetting(session.role, page));
    final id = session.subtitle.replaceFirst('Patient ID ', '');

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.xxl),
        children: [
          Row(children: [
            isDoctor
                ? AppAvatar(
                    name: session.fullName, size: 56, background: AppColors.doctorTint, foreground: AppColors.doctor)
                : AppAvatar(name: session.fullName, size: 56),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(session.fullName, style: AppTextStyles.title),
                Text(isDoctor ? 'Doctor · ${session.subtitle}' : 'Patient', style: AppTextStyles.bodySmall),
                if (!isDoctor)
                  Text(id, style: AppTextStyles.mono.copyWith(color: AppColors.muted, fontWeight: FontWeight.w400)),
              ]),
            ),
          ]),
          if (session.isDemo) ...[
            const SizedBox(height: AppSpacing.md),
            const Text('Demo account · fictional data', style: AppTextStyles.caption),
          ],
          const SizedBox(height: AppSpacing.xl),
          RowGroup(title: 'Account', children: [
            ListRowTile(
              icon: Icons.person_outline_rounded,
              title: 'Personal information',
              subtitle: 'Name, contact details, emergency contact',
              onTap: () => open(Routes.settingsPersonal),
            ),
            ListRowTile(
              icon: isDoctor ? Icons.badge_outlined : Icons.assignment_outlined,
              title: isDoctor ? 'Professional information' : 'Medical information',
              subtitle: isDoctor ? 'Specialty, licence, clinic' : 'Assigned doctor, clinic, record number',
              onTap: () => open(Routes.settingsHealth),
            ),
          ]),
          const SizedBox(height: AppSpacing.xl),
          RowGroup(title: 'Preferences', children: [
            ListRowTile(
              icon: Icons.notifications_none_rounded,
              title: 'Notifications',
              subtitle: 'Reports, messages, reminders',
              onTap: () => open(Routes.settingsNotifications),
            ),
          ]),
          const SizedBox(height: AppSpacing.xl),
          RowGroup(title: 'Privacy', children: [
            ListRowTile(
              icon: Icons.shield_outlined,
              title: 'Security & privacy',
              subtitle: 'Password, sessions, how data is used',
              onTap: () => open(Routes.settingsSecurity),
            ),
          ]),
          const SizedBox(height: AppSpacing.xl),
          RowGroup(title: 'Support', children: [
            ListRowTile(
              icon: Icons.help_outline_rounded,
              title: 'Help & support',
              subtitle: 'Common questions and contact',
              onTap: () => open(Routes.settingsHelp),
            ),
          ]),
          const SizedBox(height: AppSpacing.xxl),
          AppButton(
            key: const Key('logoutButton'),
            label: 'Log out',
            icon: Icons.logout_rounded,
            variant: AppButtonVariant.danger,
            onPressed: () => _logout(context, ref),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('NeuroSense 0.1 · Academic project · Not a certified medical device',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(fontSize: 12.5)),
        ],
      ),
    );
  }
}
