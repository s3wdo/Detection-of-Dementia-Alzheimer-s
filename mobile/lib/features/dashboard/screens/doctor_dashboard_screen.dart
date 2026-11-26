import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../../appointments/appointments_providers.dart';
import '../../appointments/data/models/appointment.dart';
import '../../diagnosis/data/models/upload_models.dart';
import '../../diagnosis/widgets/analysis_widgets.dart';
import '../../patients/data/models/patient.dart';
import '../../patients/patients_providers.dart';
import '../dashboard_providers.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/greeting_header.dart';

/// Doctor home, ordered by what needs the doctor's attention: results waiting
/// for review, then the schedule, then recent activity.
class DoctorDashboardScreen extends ConsumerWidget {
  const DoctorDashboardScreen({super.key});

  void _openPatients(BuildContext context, WidgetRef ref, PatientFilter filter) {
    ref.read(patientQueryProvider.notifier).setFilter(filter);
    context.go(Routes.doctorPatients);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    if (session == null) return const SizedBox.shrink();
    final dashboard = ref.watch(doctorDashboardProvider);
    final queue = ref.watch(reviewQueueProvider);
    final appointments = ref.watch(doctorAppointmentsProvider);
    final now = ref.watch(clockProvider)();
    final summary = dashboard.value;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(doctorAppointmentsProvider);
            ref.invalidate(doctorDashboardProvider);
            await ref.read(doctorDashboardProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.xl, AppSpacing.screen, AppSpacing.xxl),
            children: [
              GreetingHeader(
                  session: session,
                  notificationsRoute: Routes.doctorNotifications,
                  messagesRoute: Routes.doctorMessages),
              if (summary != null)
                Text(
                  '${summary.patientCount} patients · ${summary.upcomingAppointments} appointments this week',
                  style: AppTextStyles.bodySmall,
                ),
              dashboardSectionGap,
              AsyncValueView<List<ReviewQueueItem>>(
                value: queue,
                onRetry: () => ref.invalidate(doctorDashboardProvider),
                data: (items) => RowGroup(
                  title: 'Awaiting your review',
                  action: items.isEmpty
                      ? null
                      : TextButton(
                          key: const Key('reviewQueueAll'),
                          onPressed: () => _openPatients(context, ref, PatientFilter.needsReview),
                          child: const Text('View all'),
                        ),
                  children: [
                    if (items.isEmpty)
                      const GroupRow(
                        child: Text('Nothing is waiting for your review.', style: AppTextStyles.bodySmall),
                      )
                    else
                      for (final item in items.take(5))
                        _ReviewRow(
                          item: item,
                          now: now,
                          // A failed analysis has no result screen: open the patient instead.
                          onTap: () => context.push(item.failed
                              ? Routes.doctorPatient(item.patientId)
                              : Routes.doctorAnalysis(item.patientId, item.analysisId)),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: 'New MRI analysis',
                icon: Icons.upload_rounded,
                onPressed: () => _openPatients(context, ref, PatientFilter.all),
              ),
              dashboardSectionGap,
              AsyncValueView<List<Appointment>>(
                value: appointments,
                onRetry: () => ref.invalidate(doctorAppointmentsProvider),
                data: (all) => _Schedule(
                  appointments: all,
                  now: now,
                  onOpen: (a) => context.push('${Routes.doctorAppointments}/${a.id}'),
                  onAll: () => context.go(Routes.doctorAppointments),
                ),
              ),
              dashboardSectionGap,
              if (summary != null && summary.recentActivity.isNotEmpty)
                ActivityList(
                  title: 'Recent activity',
                  action: TextButton(
                      onPressed: () => context.push(Routes.doctorNotifications), child: const Text('View all')),
                  events: summary.recentActivity,
                  now: now,
                  showPatientName: true,
                  onTap: (e) => context.push(Routes.doctorPatient(e.patientId)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One analysis waiting for the doctor: patient, the AI result and how long it
/// has waited; or, for a failed analysis, that it needs a retry or a new upload.
class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.item, required this.now, required this.onTap});

  final ReviewQueueItem item;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = item.analysis;
    if (a == null) {
      return ListRowTile(
        title: item.patientName,
        subtitle: 'Analysis failed · ${Fmt.relative(item.uploadedAt, now)} · ask for a new upload',
        titleColor: AppColors.ink,
        iconColor: AppColors.error,
        icon: Icons.error_outline_rounded,
        onTap: onTap,
      );
    }
    return GroupRow(
      onTap: onTap,
      child: Row(children: [
          AppAvatar(name: item.patientName, size: 40),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.patientName, style: AppTextStyles.label.copyWith(fontSize: 16)),
              Text('${a.predicted.label} · ${Fmt.percent(a.confidence)} · ${Fmt.relative(a.createdAt, now)}',
                  style: AppTextStyles.caption.copyWith(fontSize: 14)),
              const SizedBox(height: AppSpacing.xs),
              AnalysisStatusBadge(a),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
      ]),
    );
  }
}

/// Today's appointments; when there are none it says so and lists the next few.
class _Schedule extends StatelessWidget {
  const _Schedule({required this.appointments, required this.now, required this.onOpen, required this.onAll});

  final List<Appointment> appointments;
  final DateTime now;
  final void Function(Appointment a) onOpen;
  final VoidCallback onAll;

  bool _today(DateTime d) => d.year == now.year && d.month == now.month && d.day == now.day;

  @override
  Widget build(BuildContext context) {
    final today = appointments
        .where((a) => _today(a.startsAt) && a.status != AppointmentStatus.cancelled)
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final next = appointments.where((a) => a.isUpcoming(now) && !_today(a.startsAt)).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return RowGroup(
      title: 'Schedule',
      action: TextButton(onPressed: onAll, child: const Text('All')),
      children: [
        if (today.isEmpty)
          const GroupRow(child: Text('No appointments today.', style: AppTextStyles.bodySmall)),
        for (final a in [...today, ...next.take(3)])
          ListRowTile(
            title: '${a.patientName} · ${a.title}',
            subtitle: _today(a.startsAt)
                ? 'Today · ${Fmt.time(a.startsAt)}'
                : '${Fmt.date(a.startsAt)} · ${Fmt.time(a.startsAt)}',
            trailing: a.status == AppointmentStatus.requested ? const StatusBadge(StatusKind.requested) : null,
            onTap: () => onOpen(a),
          ),
      ],
    );
  }
}
