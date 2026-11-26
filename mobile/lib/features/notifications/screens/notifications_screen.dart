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
import '../data/models/app_notification.dart';
import '../notifications_providers.dart';

/// Notifications grouped into Today / Earlier, with an All / Unread filter.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _unreadOnly = false;

  Future<void> _open(AppNotification n) async {
    await ref.read(notificationsProvider.notifier).markRead(n.id);
    // push keeps this screen underneath, so the opened screen has a back button.
    if (mounted && n.route != null) context.push(n.route!);
  }

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadCountProvider);
    final now = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unread > 0)
            IconButton(
              tooltip: 'Mark all read',
              onPressed: () => ref.read(notificationsProvider.notifier).markAllRead(),
              icon: const Icon(Icons.done_all_rounded),
            ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.sm),
            child: SegmentedButton<bool>(
              segments: [
                const ButtonSegment(value: false, label: Text('All')),
                ButtonSegment(value: true, label: Text(unread == 0 ? 'Unread' : 'Unread ($unread)')),
              ],
              selected: {_unreadOnly},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _unreadOnly = s.first),
            ),
          ),
          Expanded(
            child: AsyncValueView<List<AppNotification>>(
              value: notifications,
              onRetry: () => ref.invalidate(notificationsProvider),
              data: (all) {
                final list = _unreadOnly ? all.where((n) => !n.read).toList() : all;
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: "You're all caught up.",
                    message: 'New results, messages and reminders will appear here.',
                  );
                }
                final today = list.where((n) => _sameDay(n.createdAt, now)).toList();
                final earlier = list.where((n) => !_sameDay(n.createdAt, now)).toList();
                return ListView(
                  padding: const EdgeInsets.fromLTRB(0, AppSpacing.sm, 0, AppSpacing.xxl),
                  children: [
                    for (final (title, group) in [('Today', today), ('Earlier', earlier)])
                      if (group.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.lg, AppSpacing.screen, AppSpacing.sm),
                          child: Overline(title),
                        ),
                        const Divider(),
                        for (final n in group) ...[
                          _NotificationTile(notification: n, now: now, onTap: () => _open(n)),
                          const Divider(),
                        ],
                      ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// One notification: type icon, title (bold when unread), body and time, unread dot.
class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.now, required this.onTap});

  final AppNotification notification;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final (icon, color) = switch (n.kind) {
      NotificationKind.review => (Icons.assignment_turned_in_outlined, AppColors.doctor),
      NotificationKind.message => (Icons.mail_outline_rounded, AppColors.doctor),
      NotificationKind.appointment => (Icons.calendar_today_outlined, AppColors.admin),
      NotificationKind.analysis => (Icons.filter_center_focus_rounded, AppColors.ai),
    };
    return Semantics(
      label: n.read ? null : 'Unread',
      child: Material(
        color: n.read ? Colors.transparent : AppColors.primaryTint.withValues(alpha: 0.55),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.md, AppSpacing.screen, AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 22, color: color)),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(n.title,
                        style: n.read
                            ? AppTextStyles.body.copyWith(color: AppColors.ink)
                            : AppTextStyles.label.copyWith(fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(n.body, style: AppTextStyles.bodySmall),
                    Text(Fmt.relative(n.createdAt, now), style: AppTextStyles.caption),
                  ]),
                ),
                if (!n.read)
                  Container(
                    margin: const EdgeInsets.only(top: 7, left: AppSpacing.sm),
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
