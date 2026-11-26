import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/clock.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../appointment_actions.dart';
import '../appointments_providers.dart';
import '../data/models/appointment.dart';
import '../widgets/appointment_card.dart';

/// Appointments (design section 21) with Upcoming / Past tabs and actions on each card.
/// Doctors confirm, reschedule or cancel; patients cancel and book.
class AppointmentsScreen extends ConsumerWidget {
  const AppointmentsScreen({super.key, required this.forDoctor});

  final bool forDoctor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = forDoctor ? doctorAppointmentsProvider : patientAppointmentsProvider;
    final list = ref.watch(provider);
    final now = ref.watch(clockProvider)();
    final base = forDoctor ? '/doctor/appointments' : '/patient/appointments';

    List<Widget> actionsFor(Appointment a) {
      if (!a.isUpcoming(now)) return const [];
      // Compact text actions: the row itself opens the details, so there is no "View" button.
      final cancel = TextButton(
        key: Key('cancel_${a.id}'),
        style: TextButton.styleFrom(foregroundColor: AppColors.error),
        onPressed: () => AppointmentActions.cancel(context, ref, a),
        child: const Text('Cancel'),
      );
      if (forDoctor && a.status == AppointmentStatus.requested) {
        return [
          TextButton(
            key: Key('confirm_${a.id}'),
            style: TextButton.styleFrom(foregroundColor: AppColors.success),
            onPressed: () => AppointmentActions.confirm(context, ref, a),
            child: const Text('Confirm'),
          ),
          TextButton(
            onPressed: () => AppointmentActions.reschedule(context, ref, a),
            child: const Text('Reschedule'),
          ),
          cancel,
        ];
      }
      return [cancel];
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Appointments'),
          actions: [
            if (!forDoctor)
              IconButton(
                key: const Key('bookAppointment'),
                tooltip: 'Book appointment',
                onPressed: () => context.push('$base/new'),
                icon: const Icon(Icons.add_rounded),
              ),
            const SizedBox(width: AppSpacing.sm),
          ],
          bottom: const PillTabBar(labels: ['Upcoming', 'Past']),
        ),
        body: AsyncValueView<List<Appointment>>(
          value: list,
          onRetry: () => ref.invalidate(provider),
          data: (all) {
            final upcoming = all.where((a) => a.isUpcoming(now)).toList();
            final past = all.where((a) => !a.isUpcoming(now)).toList().reversed.toList();
            Widget listOf(List<Appointment> items, String emptyTitle) => items.isEmpty
                ? EmptyState(
                    icon: Icons.event_busy_outlined,
                    title: emptyTitle,
                    action: forDoctor
                        ? null
                        : AppButton(
                            label: 'Book appointment',
                            icon: Icons.add_rounded,
                            expand: false,
                            onPressed: () => context.push('$base/new'),
                          ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.screen),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (_, i) => AppointmentCard(
                      appointment: items[i],
                      forDoctor: forDoctor,
                      actions: actionsFor(items[i]),
                      onTap: () => context.push('$base/${items[i].id}'),
                    ),
                  );
            return TabBarView(children: [
              listOf(upcoming, 'No upcoming appointments'),
              listOf(past, 'No past appointments'),
            ]);
          },
        ),
      ),
    );
  }
}
