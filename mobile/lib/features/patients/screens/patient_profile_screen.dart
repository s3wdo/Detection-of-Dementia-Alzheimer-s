import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/data/repository_providers.dart';
import '../../../core/data/user_facing_error.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../../core/widgets/source_style.dart';
import '../../../core/widgets/state_views.dart';
import '../../appointments/appointments_providers.dart';
import '../../appointments/data/models/appointment.dart';
import '../../appointments/widgets/appointment_card.dart';
import '../../diagnosis/data/models/analysis.dart';
import '../../diagnosis/diagnosis_providers.dart';
import '../../diagnosis/widgets/analysis_widgets.dart';
import '../../diagnosis/widgets/result_widgets.dart';
import '../../timeline/timeline_providers.dart';
import '../../timeline/widgets/timeline_tile.dart';
import '../data/models/doctor_note.dart';
import '../data/models/patient.dart';
import '../patients_providers.dart';

/// A patient's clinical workspace for the doctor (design section 06).
class PatientProfileScreen extends ConsumerWidget {
  const PatientProfileScreen({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patient = ref.watch(patientProvider(patientId));
    final analyses = ref.watch(analysesProvider((patientId: patientId, patientView: false)));
    final now = ref.watch(clockProvider)();
    final list = analyses.value ?? const <AnalysisSummary>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient profile'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More actions',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (v) => context.push(v),
            itemBuilder: (_) => [
              PopupMenuItem(value: '/doctor/messages/$patientId', child: const Text('Message patient')),
              PopupMenuItem(value: Routes.doctorPatientTimeline(patientId), child: const Text('View timeline')),
              if (list.length > 1)
                PopupMenuItem(value: '/doctor/patients/$patientId/compare', child: const Text('Compare analyses')),
              if (list.isNotEmpty && list.first.status.isReviewed)
                PopupMenuItem(
                  value: '${Routes.doctorAnalysis(patientId, list.first.id)}/report',
                  child: const Text('View latest report'),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: AsyncValueView<Patient>(
        value: patient,
        onRetry: () => ref.invalidate(patientProvider(patientId)),
        data: (p) => ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xxl),
          children: [
            _Header(patient: p, now: now, analysisCount: analyses.value?.length),
            const SizedBox(height: AppSpacing.lg),
            AsyncValueView<List<AnalysisSummary>>(
              value: analyses,
              onRetry: () => ref.invalidate(analysesProvider((patientId: patientId, patientView: false))),
              data: (list) => _AnalysesSection(patientId: patientId, analyses: list),
            ),
            const SizedBox(height: AppSpacing.lg),
            _AppointmentsSection(patientId: patientId, now: now),
            const SizedBox(height: AppSpacing.lg),
            _NotesSection(patientId: patientId),
            const SizedBox(height: AppSpacing.lg),
            _TimelinePreview(patientId: patientId),
            const SizedBox(height: AppSpacing.lg),
            _PersonalInfo(patient: p),
          ],
        ),
      ),
    );
  }
}

/// Section with a top divider, a title row and an optional text action.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.action, this.onAction});

  final String title;
  final Widget child;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Divider(),
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTouch + 8),
        child: Row(children: [
          Expanded(child: Semantics(header: true, child: Text(title, style: AppTextStyles.headline))),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ]),
      ),
      child,
      const SizedBox(height: AppSpacing.md),
    ]);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.patient, required this.now, this.analysisCount});

  final Patient patient;
  final DateTime now;
  final int? analysisCount;

  @override
  Widget build(BuildContext context) {
    final details = [
      '${patient.sex.label} · ${Fmt.age(patient.dateOfBirth, now)} yrs',
      if (analysisCount != null) '$analysisCount MRI ${analysisCount == 1 ? 'analysis' : 'analyses'}',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          AppAvatar(name: patient.fullName, size: 52),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(patient.fullName, style: AppTextStyles.title),
              Text(patient.mrn, style: AppTextStyles.mono.copyWith(color: AppColors.muted, fontWeight: FontWeight.w400)),
              Text(details, style: AppTextStyles.bodySmall),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpacing.lg),
        Row(children: [
          Expanded(
            child: AppButton(
              label: 'Upload MRI',
              icon: Icons.upload_rounded,
              onPressed: () => context.push(Routes.doctorPatientUpload(patient.id)),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          IconButton.outlined(
            tooltip: 'Message patient',
            style: IconButton.styleFrom(minimumSize: const Size(54, 54)),
            onPressed: () => context.push('/doctor/messages/${patient.id}'),
            icon: const Icon(Icons.mail_outline_rounded),
          ),
        ]),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

class _AnalysesSection extends StatelessWidget {
  const _AnalysesSection({required this.patientId, required this.analyses});

  final String patientId;
  final List<AnalysisSummary> analyses;

  @override
  Widget build(BuildContext context) {
    if (analyses.isEmpty) {
      return _SectionCard(
        title: 'MRI Analyses',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('No MRI analyses yet. Upload a scan to run the first AI-assisted analysis.',
              style: AppTextStyles.bodySmall),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Upload MRI',
            icon: Icons.upload_rounded,
            variant: AppButtonVariant.secondary,
            onPressed: () => context.push(Routes.doctorPatientUpload(patientId)),
          ),
        ]),
      );
    }
    final latest = analyses.first;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _SectionCard(
        title: 'Latest Result',
        action: 'Open',
        onAction: () => context.push(Routes.doctorAnalysis(patientId, latest.id)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SourceBadge(InfoSource.ai),
          const SizedBox(height: AppSpacing.sm),
          Text(latest.predicted.label, style: AppTextStyles.headline.copyWith(fontSize: 19)),
          ConfidenceText(latest.confidence, suffix: ' · ${Fmt.date(latest.createdAt)}'),
          const SizedBox(height: AppSpacing.lg),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          if (latest.status.isReviewed)
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                SourceBadge(InfoSource.doctor, doctorName: latest.reviewedBy),
                if (latest.reviewedAt != null) Text(Fmt.shortDate(latest.reviewedAt!), style: AppTextStyles.caption),
              ],
            )
          else
            Row(children: [
              AnalysisStatusBadge(latest),
              const Spacer(),
              TextButton(
                onPressed: () => context.push(Routes.doctorReview(patientId, latest.id)),
                child: const Text('Review'),
              ),
            ]),
        ]),
      ),
      const SizedBox(height: AppSpacing.lg),
      _SectionCard(
        title: 'MRI Analysis History',
        action: analyses.length > 1 ? 'Compare' : null,
        onAction: () => context.push('/doctor/patients/$patientId/compare'),
        child: Column(children: [
          for (final (i, a) in analyses.indexed) ...[
            if (i > 0) const Divider(),
            InkWell(
              onTap: () => context.push(Routes.doctorAnalysis(a.patientId, a.id)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 64,
                    child: Text(Fmt.date(a.createdAt),
                        style: AppTextStyles.mono.copyWith(fontWeight: FontWeight.w400, color: AppColors.muted)),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.predicted.label, style: AppTextStyles.label.copyWith(fontSize: 16)),
                      Text(Fmt.percent(a.confidence), style: AppTextStyles.mono.copyWith(fontSize: 15)),
                      const SizedBox(height: AppSpacing.xs),
                      AnalysisStatusBadge(a),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                ]),
              ),
            ),
          ],
        ]),
      ),
    ]);
  }
}

class _AppointmentsSection extends ConsumerWidget {
  const _AppointmentsSection({required this.patientId, required this.now});

  final String patientId;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(doctorAppointmentsProvider);
    final all = async.value ?? const <Appointment>[];
    final upcoming = all.where((a) => a.patientId == patientId && a.isUpcoming(now)).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return _SectionCard(
      title: 'Appointments',
      action: 'All',
      onAction: () => context.go(Routes.doctorAppointments),
      child: !async.hasValue
          ? const _Loading()
          : upcoming.isEmpty
              ? const Text('No upcoming appointments.', style: AppTextStyles.bodySmall)
              : Column(children: [
                  for (final a in upcoming)
                    InkWell(
                      onTap: () => context.push('${Routes.doctorAppointments}/${a.id}'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          DateTile(date: a.startsAt),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(a.title, style: AppTextStyles.label.copyWith(fontSize: 16)),
                              Text('${Fmt.time(a.startsAt)}${a.location == null ? '' : ' · ${a.location}'}',
                                  style: AppTextStyles.caption.copyWith(fontSize: 14)),
                              const SizedBox(height: AppSpacing.xs),
                              StatusBadge(appointmentStatusKind(a.status)),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                ]),
    );
  }
}

class _NotesSection extends ConsumerWidget {
  const _NotesSection({required this.patientId});

  final String patientId;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final saved = await showAppBottomSheet<bool>(
      context,
      title: 'Add note',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.admin),
          SizedBox(width: 6),
          Flexible(child: Text('Visible to clinicians only', style: AppTextStyles.caption)),
        ]),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const Key('noteInput'),
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(hintText: 'Write a clinical note…'),
        ),
        const SizedBox(height: AppSpacing.lg),
        Builder(
          builder: (sheet) => AppButton(
            key: const Key('saveNote'),
            label: 'Save note',
            onPressed: () => Navigator.of(sheet).pop(true),
          ),
        ),
      ]),
    );
    if (saved != true || !context.mounted) return;
    try {
      final author = ref.read(sessionControllerProvider)?.fullName ?? 'Doctor';
      await ref.read(patientsRepositoryProvider).addNote(patientId, body: controller.text, author: author);
      ref.invalidate(patientNotesProvider(patientId));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(userMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(patientNotesProvider(patientId));
    final notes = async.value ?? const <DoctorNote>[];
    return _SectionCard(
      title: 'Doctor Notes',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.admin),
          SizedBox(width: 6),
          Flexible(child: Text('Visible to clinicians only', style: AppTextStyles.label)),
        ]),
        const SizedBox(height: AppSpacing.md),
        if (!async.hasValue)
          const _Loading()
        else if (notes.isEmpty)
          const Text('No notes yet.', style: AppTextStyles.bodySmall),
        for (final n in notes.take(3)) ...[
          Text(n.body, style: AppTextStyles.body.copyWith(color: AppColors.ink)),
          const SizedBox(height: AppSpacing.xs),
          Text('${n.author} · ${Fmt.date(n.createdAt)}', style: AppTextStyles.caption),
          const SizedBox(height: AppSpacing.md),
        ],
        AppButton(
          key: const Key('addNote'),
          label: 'Add note',
          icon: Icons.edit_outlined,
          variant: AppButtonVariant.secondary,
          onPressed: () => _add(context, ref),
        ),
      ]),
    );
  }
}

class _TimelinePreview extends ConsumerWidget {
  const _TimelinePreview({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(timelineProvider((patientId: patientId, patientView: false)));
    final events = async.value ?? const [];
    return _SectionCard(
      title: 'Timeline',
      action: 'View full timeline',
      onAction: () => context.push(Routes.doctorPatientTimeline(patientId)),
      child: !async.hasValue
          ? const _Loading()
          : events.isEmpty
              ? const Text('No events yet.', style: AppTextStyles.bodySmall)
              : Column(children: [
                  for (final e in events.take(3))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                      child: Row(children: [
                        Builder(builder: (_) {
                          final s = sourceStyle(e.source);
                          return Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(color: s.tint, borderRadius: BorderRadius.circular(10)),
                            child: Icon(timelineIcon(e.kind), size: 18, color: s.color),
                          );
                        }),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: Text(e.title, style: AppTextStyles.body.copyWith(color: AppColors.ink))),
                        Text(Fmt.shortDate(e.at), style: AppTextStyles.caption.copyWith(fontSize: 14)),
                      ]),
                    ),
                ]),
    );
  }
}

class _PersonalInfo extends ConsumerWidget {
  const _PersonalInfo({required this.patient});

  final Patient patient;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final phone = TextEditingController(text: patient.phone);
    final contact = TextEditingController(text: patient.emergencyContact);
    final saved = await showAppBottomSheet<bool>(
      context,
      title: 'Edit contact details',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(controller: contact, decoration: const InputDecoration(labelText: 'Emergency contact')),
        const SizedBox(height: AppSpacing.sm),
        const Text('Name, date of birth and patient ID are managed by the clinic administrator.',
            style: AppTextStyles.caption),
        const SizedBox(height: AppSpacing.lg),
        Builder(builder: (sheet) => AppButton(label: 'Save', onPressed: () => Navigator.of(sheet).pop(true))),
      ]),
    );
    if (saved != true || !context.mounted) return;
    try {
      await ref
          .read(patientsRepositoryProvider)
          .updateContact(patient.id, phone: phone.text, emergencyContact: contact.text);
      ref.invalidate(patientProvider(patient.id));
      ref.invalidate(patientListProvider);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(userMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget cell(String label, String value, {bool mono = false}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption.copyWith(fontSize: 14)),
            Text(value,
                style: mono ? AppTextStyles.mono.copyWith(fontSize: 15) : AppTextStyles.label.copyWith(fontSize: 16)),
          ],
        );
    final cells = [
      cell('Date of birth', Fmt.date(patient.dateOfBirth)),
      cell('Sex', patient.sex.label),
      cell('Phone', patient.phone, mono: true),
      cell('Emergency contact', patient.emergencyContact),
      cell('Email', patient.email),
    ];
    return _SectionCard(
      title: 'Personal Information',
      action: 'Edit',
      onAction: () => _edit(context, ref),
      child: LayoutBuilder(
        builder: (context, c) => Wrap(
          runSpacing: AppSpacing.md,
          children: [for (final w in cells) SizedBox(width: c.maxWidth > 300 ? c.maxWidth / 2 : c.maxWidth, child: w)],
        ),
      ),
    );
  }
}

/// Small inline loading line used inside the section cards.
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Row(children: [
        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: AppSpacing.md),
        Text('Loading…', style: AppTextStyles.bodySmall),
      ]);
}
