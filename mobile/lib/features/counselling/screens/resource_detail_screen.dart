import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/state_views.dart';
import '../counselling_providers.dart';
import '../data/models/counselling_models.dart';

class ResourceDetailScreen extends ConsumerWidget {
  const ResourceDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resource = ref.watch(resourceProvider(slug));
    return Scaffold(
      appBar: AppBar(),
      body: AsyncValueView<Resource>(
        value: resource,
        onRetry: () => ref.invalidate(resourceProvider(slug)),
        data: (r) => ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xxl),
          children: [
            Text(r.category.label.toUpperCase(),
                style: AppTextStyles.caption.copyWith(color: AppColors.violet, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(r.title, style: AppTextStyles.display),
            const SizedBox(height: AppSpacing.sm),
            Text(r.summary, style: AppTextStyles.body),
            const SizedBox(height: AppSpacing.xl),
            for (final s in r.sections) ...[
              Semantics(header: true, child: Text(s.heading, style: AppTextStyles.headline)),
              const SizedBox(height: AppSpacing.xs),
              Text(s.body, style: AppTextStyles.body),
              const SizedBox(height: AppSpacing.lg),
            ],
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(color: AppColors.adminTint, borderRadius: BorderRadius.circular(AppRadii.tile)),
              child: Text(
                  'Source: ${r.source}. General information only — it does not replace advice from your doctor.',
                  style: AppTextStyles.caption.copyWith(color: AppColors.body)),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Ask a question about this',
              icon: Icons.chat_bubble_outline_rounded,
              variant: AppButtonVariant.secondary,
              onPressed: () => context.push('/patient/counselling/chat'),
            ),
          ],
        ),
      ),
    );
  }
}
