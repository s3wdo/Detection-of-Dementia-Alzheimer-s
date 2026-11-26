import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../notifications/notifications_providers.dart';

/// Dashboard header from the design: date line, serif "Good morning, Sarah",
/// messages, notification bell and the user's initials.
class GreetingHeader extends ConsumerWidget {
  const GreetingHeader({
    super.key,
    required this.session,
    required this.notificationsRoute,
    required this.messagesRoute,
  });

  final Session session;
  final String notificationsRoute;
  final String messagesRoute;

  static String greetingFor(DateTime now) {
    final h = now.hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  /// "Sarah Johnson" → "Sarah", "Dr. Ahmed Khan" → "Dr. Ahmed".
  static String shortName(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length > 1 && parts.first.toLowerCase().startsWith('dr')) return '${parts[0]} ${parts[1]}';
    return parts.first;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    final now = ref.watch(clockProvider)();
    final doctor = session.role == UserRole.doctor;
    final dateLine =
        doctor && session.subtitle.isNotEmpty ? '${Fmt.weekday(now)} · ${session.subtitle}' : Fmt.weekday(now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(dateLine, style: AppTextStyles.caption.copyWith(fontSize: 15))),
            IconButton(
              tooltip: 'Messages',
              onPressed: () => context.push(messagesRoute),
              icon: const Icon(Icons.mail_outline_rounded, color: AppColors.navy),
            ),
            IconButton(
              tooltip: unread == 0 ? 'Notifications' : 'Notifications, $unread unread',
              onPressed: () => context.push(notificationsRoute),
              icon: Badge(
                isLabelVisible: unread > 0,
                backgroundColor: AppColors.error,
                smallSize: 10,
                child: const Icon(Icons.notifications_none_rounded, color: AppColors.navy),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            doctor
                ? AppAvatar(
                    name: session.fullName,
                    size: 48,
                    background: AppColors.doctorTint,
                    foreground: AppColors.doctor,
                  )
                : AppAvatar(name: session.fullName, size: 48),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          header: true,
          child: Text('${greetingFor(now)}, ${shortName(session.fullName)}', style: AppTextStyles.display),
        ),
      ],
    );
  }
}
