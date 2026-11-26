import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../data/profile_repository.dart';
import '../profile_providers.dart';

/// Read-only list of profile fields ("Personal Information",
/// "Medical Information" or "Professional Information").
class ProfileDetailScreen extends ConsumerWidget {
  const ProfileDetailScreen.personal({super.key})
      : title = 'Personal Information',
        _health = false;

  const ProfileDetailScreen.health({super.key, required this.title}) : _health = true;

  final String title;
  final bool _health;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(profileDetailsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AsyncValueView<ProfileDetails>(
        value: details,
        onRetry: () => ref.invalidate(profileDetailsProvider),
        data: (d) => ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xxl),
          children: [
            AppCard(
              child: Column(children: [
                for (final f in _health ? d.health : d.personal) InfoRow(label: f.label, value: f.value),
              ]),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text('To change these details, contact your clinic.', style: AppTextStyles.caption),
          ],
        ),
      ),
    );
  }
}
