import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../data/models/message.dart';
import '../messages_providers.dart';

/// Doctor's inbox: one conversation per patient.
class MessageThreadsScreen extends ConsumerWidget {
  const MessageThreadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threads = ref.watch(doctorThreadsProvider);
    final now = ref.watch(clockProvider)();
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: AsyncValueView<List<MessageThread>>(
        value: threads,
        onRetry: () => ref.invalidate(doctorThreadsProvider),
        isEmpty: (l) => l.isEmpty,
        empty: const EmptyState(icon: Icons.mail_outline_rounded, title: 'No messages yet'),
        data: (list) => ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(indent: AppSpacing.screen, endIndent: AppSpacing.screen),
          itemBuilder: (_, i) {
            final t = list[i];
            return InkWell(
              onTap: () => context.push('/doctor/messages/${t.patientId}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen, vertical: AppSpacing.md),
                child: Row(children: [
                AppAvatar(name: t.patientName),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.patientName,
                        style:
                            AppTextStyles.label.copyWith(fontWeight: t.unread > 0 ? FontWeight.w700 : FontWeight.w600)),
                    Text('${t.last.fromDoctor ? 'You: ' : ''}${t.last.body}',
                        style: AppTextStyles.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(Fmt.relative(t.last.sentAt, now), style: AppTextStyles.caption),
                  ]),
                ),
                if (t.unread > 0)
                  Badge(
                    label: Text('${t.unread}'),
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
              ]),
              ),
            );
          },
        ),
      ),
    );
  }
}
