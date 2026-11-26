import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../../appointments/data/models/appointment.dart';
import '../../diagnosis/data/models/upload_models.dart';
import '../../diagnosis/diagnosis_providers.dart';
import '../dashboard_providers.dart';
import '../data/models/dashboards.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/greeting_header.dart';
import '../widgets/latest_analysis_card.dart';

/// Patient home: the latest released result, the next appointment, the care
/// team and education. Shows only results the doctor has released.
class PatientDashboardScreen extends ConsumerWidget {
  const PatientDashboardScreen({super.key});

  /// What the patient is told about their latest upload: that it arrived, or
  /// that it must be sent again. Never anything about the analysis.
  static String _uploadLine(List<PatientUpload>? uploads) {
    final latest = uploads == null || uploads.isEmpty ? null : uploads.first;
    return switch (latest?.state) {
      UploadState.received => 'Sent ${Fmt.date(latest!.uploadedAt)} · waiting for your doctor to review it',
      UploadState.needsReupload => 'Your last scan could not be processed. Please upload it again.',
      _ => 'Your doctor reviews it before you see any result.',
    };
  }

  /// Where the latest scan is on the way to a result: 0 nothing sent (or it
  /// must be sent again), 1 with the doctor, 2 result released.
  static int _uploadStep(List<PatientUpload>? uploads) {
    final latest = uploads == null || uploads.isEmpty ? null : uploads.first;
    return switch (latest?.state) {
      UploadState.received => 1,
      UploadState.released => 2,
      _ => 0,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    if (session == null) return const SizedBox.shrink();
    final dashboard = ref.watch(patientDashboardProvider);
    // Fetched together with the dashboard, so both arrive in one loading state.
    final uploads = ref.watch(myUploadsProvider).value;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () {
            ref.invalidate(myUploadsProvider);
            return ref.refresh(patientDashboardProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.xl, AppSpacing.screen, AppSpacing.xxl),
            children: [
              GreetingHeader(
                  session: session,
                  notificationsRoute: Routes.patientNotifications,
                  messagesRoute: Routes.patientMessages),
              dashboardSectionGap,
              AsyncValueView<PatientDashboard>(
                value: dashboard,
                onRetry: () => ref.invalidate(patientDashboardProvider),
                data: (d) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _UploadCard(
                      line: _uploadLine(uploads),
                      step: _uploadStep(uploads),
                      onUpload: () => context.push(Routes.patientUpload),
                    ),
                    dashboardSectionGap,
                    const Overline('Latest result'),
                    const SizedBox(height: AppSpacing.sm),
                    LatestAnalysisCard(
                      analysis: d.latestReleased,
                      onView: () => context.push(Routes.patientResult(d.latestReleased!.id)),
                    ),
                    dashboardSectionGap,
                    RowGroup(
                      title: 'Next appointment',
                      action: TextButton(
                          onPressed: () => context.push(Routes.patientAppointments), child: const Text('All')),
                      children: [_NextAppointment(appointment: d.nextAppointment)],
                    ),
                    dashboardSectionGap,
                    RowGroup(title: 'Your care team', children: [
                      ListRowTile(
                        icon: Icons.mail_outline_rounded,
                        title: 'Message your doctor',
                        subtitle: 'Secure message to your care team',
                        onTap: () => context.push(Routes.patientMessages),
                      ),
                    ]),
                    dashboardSectionGap,
                    RowGroup(title: 'Learn and prepare', children: [
                      ListRowTile(
                        icon: Icons.menu_book_outlined,
                        title: 'Education & support',
                        subtitle: 'Understanding MRI results, dementia and caregiving',
                        onTap: () => context.go(Routes.patientCounselling),
                      ),
                      ListRowTile(
                        icon: Icons.description_outlined,
                        title: 'My reports',
                        onTap: () => context.push(Routes.patientReports),
                      ),
                      ListRowTile(
                        icon: Icons.history_rounded,
                        title: 'My history',
                        onTap: () => context.go(Routes.patientHistory),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NextAppointment extends StatelessWidget {
  const _NextAppointment({required this.appointment});

  final Appointment? appointment;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    if (a == null) {
      return ListRowTile(
        icon: Icons.event_outlined,
        title: 'No upcoming appointments',
        subtitle: 'Request an appointment with your doctor',
        onTap: () => context.push('${Routes.patientAppointments}/new'),
      );
    }
    return ListRowTile(
      icon: Icons.event_outlined,
      title: '${a.title} · ${a.doctorName}',
      subtitle: '${Fmt.dateTime(a.startsAt)}${a.location == null ? '' : ' · ${a.location}'}',
      trailing: StatusBadge(a.status == AppointmentStatus.confirmed ? StatusKind.confirmed : StatusKind.requested),
      onTap: () => context.push('${Routes.patientAppointments}/${a.id}'),
    );
  }
}

/// The main action on the patient home: send a scan to the doctor. The line
/// under the title says only whether the last scan arrived, never a result.
class _UploadCard extends StatelessWidget {
  const _UploadCard({required this.line, required this.step, required this.onUpload});

  final String line;
  final int step;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(AppRadii.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Send a scan to your doctor', style: AppTextStyles.headline.copyWith(color: Colors.white)),
          const SizedBox(height: AppSpacing.xs),
          Text(line, style: AppTextStyles.bodySmall.copyWith(color: Colors.white)),
          const SizedBox(height: AppSpacing.lg),
          _Steps(current: step),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            key: const Key('patientUpload'),
            onPressed: onUpload,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primaryDark,
              minimumSize: const Size.fromHeight(AppSpacing.minTouch),
            ),
            icon: const Icon(Icons.upload_rounded, size: 20),
            label: const Text('Upload MRI scan'),
          ),
        ],
      ),
    );
  }
}

/// The three stages a scan goes through, with the current one marked. It says
/// where the scan is, never anything about the analysis.
class _Steps extends StatelessWidget {
  const _Steps({required this.current});

  final int current;

  static const _labels = ['You upload', 'Doctor reviews', 'Result ready'];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step ${current + 1} of 3: ${_labels[current]}',
      child: ExcludeSemantics(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < _labels.length; i++)
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i <= current ? Colors.white : Colors.transparent,
                      border: Border.all(color: i <= current ? Colors.white : AppColors.onNavyAccent, width: 1.5),
                    ),
                    child: i < current
                        ? const Icon(Icons.check_rounded, size: 15, color: AppColors.primaryDark)
                        : Text('${i + 1}',
                            style: AppTextStyles.caption.copyWith(
                                fontSize: 12,
                                height: 1,
                                fontWeight: FontWeight.w700,
                                color: i == current ? AppColors.primaryDark : AppColors.onNavyMuted)),
                  ),
                  Expanded(
                    child: Container(
                      height: 1.5,
                      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                      color: i == _labels.length - 1
                          ? Colors.transparent
                          : (i < current ? Colors.white : AppColors.onNavyAccent),
                    ),
                  ),
                ]),
                const SizedBox(height: AppSpacing.xs),
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: Text(_labels[i],
                      style: AppTextStyles.caption.copyWith(
                          color: i <= current ? Colors.white : AppColors.onNavyMuted,
                          fontWeight: i == current ? FontWeight.w700 : FontWeight.w400)),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
