import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/dev_mode_banner.dart';
import '../../../core/widgets/neuro_logo.dart';
import '../../../core/data/user_facing_error.dart';

/// DEVELOPMENT ONLY. Uses the design's "Role Selection" layout (screen 2)
/// to enter the app as a fictional demo doctor or patient.
class DevRolePickerScreen extends ConsumerStatefulWidget {
  const DevRolePickerScreen({super.key});

  @override
  ConsumerState<DevRolePickerScreen> createState() => _DevRolePickerScreenState();
}

class _DevRolePickerScreenState extends ConsumerState<DevRolePickerScreen> {
  UserRole? _loading;

  Future<void> _enter(UserRole role) async {
    setState(() => _loading = role);
    try {
      // On success the router redirect moves to the role's home screen.
      await ref.read(sessionControllerProvider.notifier).signInAsDemo(role);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(userMessage(e))));
    } finally {
      if (mounted) setState(() => _loading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xxl),
          children: [
            const DevModeBanner(
              message: 'Demo accounts use fictional data (Dr. Ahmed Khan, Sarah Johnson). '
                  'This is not real authentication.',
            ),
            const SizedBox(height: AppSpacing.xxl),
            const Align(alignment: Alignment.centerLeft, child: NeuroLogo(size: 64)),
            const SizedBox(height: AppSpacing.xl),
            Semantics(header: true, child: const Text('Welcome to NeuroSense', style: AppTextStyles.display)),
            const SizedBox(height: AppSpacing.sm),
            Text('How are you using NeuroSense?', style: AppTextStyles.body.copyWith(fontSize: 17)),
            const SizedBox(height: AppSpacing.xxl),
            _RoleCard(
              key: const Key('demoPatient'),
              icon: Icons.person_outline_rounded,
              overline: 'Patient',
              title: "I'm a patient",
              description: 'View your reports, analysis history, appointments and counselling.',
              loading: _loading == UserRole.patient,
              onTap: _loading == null ? () => _enter(UserRole.patient) : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            _RoleCard(
              key: const Key('demoDoctor'),
              icon: Icons.medical_services_outlined,
              overline: 'Doctor',
              title: "I'm a doctor",
              description: 'Manage patients, review MRI analyses and generate reports.',
              loading: _loading == UserRole.doctor,
              onTap: _loading == null ? () => _enter(UserRole.doctor) : null,
            ),
            const SizedBox(height: AppSpacing.xxl),
            const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.verified_user_outlined, size: 20, color: AppColors.muted),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Access is verified against your clinic account. You will only see information your role permits.',
                  style: AppTextStyles.caption,
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    super.key,
    required this.icon,
    required this.overline,
    required this.title,
    required this.description,
    required this.loading,
    required this.onTap,
  });

  final IconData icon;
  final String overline;
  final String title;
  final String description;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Continue as demo $overline',
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: AppColors.primary, size: 28),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(overline.toUpperCase(), style: AppTextStyles.overline.copyWith(color: AppColors.primary)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(title, style: AppTextStyles.title),
                  const SizedBox(height: AppSpacing.xs),
                  Text(description, style: AppTextStyles.body),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            loading
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                : const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
