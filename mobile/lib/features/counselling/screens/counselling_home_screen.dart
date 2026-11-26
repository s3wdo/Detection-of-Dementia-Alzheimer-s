import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../../dashboard/dashboard_providers.dart';
import '../counselling_providers.dart';
import '../data/models/counselling_models.dart';

/// Education & Support: understanding a released result, topic articles,
/// preparing for the appointment, and the predefined-answer assistant.
class CounsellingHomeScreen extends ConsumerWidget {
  const CounsellingHomeScreen({super.key});

  static const reportQuestion = 'What does my latest MRI result mean?';
  static const doctorQuestion = 'What should I ask my doctor?';

  static String _chat([String? ask]) =>
      ask == null ? '/patient/counselling/chat' : '/patient/counselling/chat?ask=${Uri.encodeComponent(ask)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resources = ref.watch(resourcesProvider);
    final latest = ref.watch(patientDashboardProvider).value?.latestReleased;

    return Scaffold(
      appBar: AppBar(
        title: const PageTitle('Education & Support', subtitle: 'Information for you and your family'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xxl),
        children: [
          RowGroup(title: 'Your result', children: [
            if (latest == null)
              ListRowTile(
                key: const Key('explainReport'),
                icon: Icons.help_outline_rounded,
                title: 'Ask a question',
                subtitle: 'Your result appears here after your doctor has released it',
                onTap: () => context.push(_chat()),
              )
            else
              ListRowTile(
                key: const Key('explainReport'),
                icon: Icons.description_outlined,
                title: 'Understand your latest result',
                subtitle: 'Plain-language explanation of your report from ${Fmt.date(latest.createdAt)}',
                onTap: () => context.push(_chat(reportQuestion)),
              ),
          ]),
          const SizedBox(height: AppSpacing.xxl),
          AsyncValueView<List<Resource>>(
            value: resources,
            onRetry: () => ref.invalidate(resourcesProvider),
            data: (all) => RowGroup(
              title: 'Topics',
              action: TextButton(
                onPressed: () => context.push('/patient/counselling/resources'),
                child: const Text('All resources'),
              ),
              children: [
                for (final r in all.take(5))
                  ListRowTile(
                    title: r.title,
                    subtitle: r.summary,
                    onTap: () => context.push('/patient/counselling/resources/${r.slug}'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          RowGroup(title: 'Prepare for your appointment', children: [
            ListRowTile(
              icon: Icons.checklist_rounded,
              title: 'Questions to ask your doctor',
              onTap: () => context.push(_chat(doctorQuestion)),
            ),
            ListRowTile(
              icon: Icons.mail_outline_rounded,
              title: 'Message your care team',
              onTap: () => context.push(Routes.patientMessages),
            ),
          ]),
          const SizedBox(height: AppSpacing.xxl),
          RowGroup(title: 'Ask NeuroSense Support', children: [
            ListRowTile(
              key: const Key('openChat'),
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Ask a general question',
              subtitle: 'Predefined educational answers, not medical advice',
              onTap: () => context.push(_chat()),
            ),
          ]),
          const SizedBox(height: AppSpacing.xl),
          const Text(
            'NeuroSense Support explains and educates. It does not diagnose, prescribe or change medication, '
            'and it does not replace your doctor. In an emergency, call your local emergency number.',
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }
}
