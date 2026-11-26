import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/repository_providers.dart';
import '../../../core/data/user_facing_error.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../data/models/mri_file.dart';
import '../diagnosis_providers.dart';
import '../services/mri_services.dart';
import '../services/volume_picker.dart';
import '../widgets/patient_mini_header.dart';

/// Upload MRI Scan: pick an image, see the checks, send it.
///
/// Doctor: uploads for an assigned patient and goes on to the analysis progress.
/// Patient: sends their own scan to their doctor and sees a confirmation only.
/// Nothing about the analysis is shown to the patient until the doctor has
/// reviewed and released the result (the server enforces this).
class MriUploadScreen extends ConsumerStatefulWidget {
  const MriUploadScreen({super.key, required String this.patientId});

  /// The signed-in patient uploading their own scan.
  const MriUploadScreen.patient({super.key}) : patientId = null;

  /// The patient a doctor is uploading for; null in the patient's own flow.
  final String? patientId;

  bool get forPatient => patientId == null;

  @override
  ConsumerState<MriUploadScreen> createState() => _MriUploadScreenState();
}

class _MriUploadScreenState extends ConsumerState<MriUploadScreen> {
  bool _picking = false;
  bool _starting = false;

  /// Patient flow: the scan was received by the server.
  bool _sent = false;

  /// Doctor flow: a full MRI scan (.nii) picked instead of a single slice.
  VolumeFile? _volume;
  bool _pickingVolume = false;

  Future<void> _pickVolume() async {
    setState(() => _pickingVolume = true);
    try {
      final picked = await ref.read(volumePickerProvider)();
      if (picked != null && mounted) {
        ref.read(selectedMriProvider.notifier).select(null);
        setState(() => _volume = picked);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not open the file: ${userMessage(e)}')));
      }
    } finally {
      if (mounted) setState(() => _pickingVolume = false);
    }
  }

  Future<void> _startVolume(String patientId, VolumeFile volume) async {
    setState(() => _starting = true);
    try {
      final id = await ref
          .read(analysesRepositoryProvider)
          .startVolumeAnalysis(patientId: patientId, filename: volume.name, bytes: volume.bytes);
      if (mounted) context.pushReplacement(Routes.doctorAnalysisProgress(patientId, id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: ${userMessage(e)}')));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _pick() async {
    setState(() => _picking = true);
    try {
      final file = await ref.read(mriPickerProvider).pick();
      if (file != null && mounted) ref.read(selectedMriProvider.notifier).select(file);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not open the image: ${userMessage(e)}')));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _start(MriFile file, List<MriCheck> checks) async {
    if (checks.any((c) => c.status == CheckStatus.warning)) {
      final go = await showConfirmDialog(
        context,
        title: widget.forPatient ? 'Send anyway?' : 'Analyze anyway?',
        message: widget.forPatient
            ? 'This image may not be an MRI slice. Send it only if it is the brain MRI image your clinic gave you.'
            : 'This image may not be a suitable MRI slice. The result may be meaningless. '
                'Continue only if you are sure it is an axial brain MRI.',
        confirmLabel: widget.forPatient ? 'Send anyway' : 'Analyze anyway',
      );
      if (!go || !mounted) return;
    }
    setState(() => _starting = true);
    try {
      final repository = ref.read(analysesRepositoryProvider);
      final patientId = widget.patientId;
      if (patientId == null) {
        await repository.uploadForReview(file);
        ref.read(selectedMriProvider.notifier).select(null);
        ref.invalidate(myUploadsProvider);
        if (mounted) setState(() => _sent = true);
        return;
      }
      final id = await repository.startAnalysis(patientId: patientId, file: file);
      ref.read(selectedMriProvider.notifier).select(null);
      if (mounted) context.pushReplacement(Routes.doctorAnalysisProgress(patientId, id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: ${userMessage(e)}')));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = ref.watch(selectedMriProvider);
    final inspection = ref.watch(selectedMriInspectionProvider);

    final patientId = widget.patientId;
    if (_sent) return const _SentToDoctor();

    return Scaffold(
      appBar: AppBar(
        title: PageTitle('Upload MRI Scan', subtitle: patientId == null ? 'For your doctor to review' : 'Step 1 of 2'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xxl),
        children: [
          if (patientId != null) ...[
            PatientMiniHeader(patientId: patientId, label: 'Selected patient', badge: 'Assigned'),
            const SizedBox(height: AppSpacing.lg),
          ] else ...[
            const Text(
              'Your doctor will review the scan. You will see the result here only after your doctor has '
              'reviewed and released it.',
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (patientId != null && _volume != null)
            _VolumeCard(
              volume: _volume!,
              starting: _starting,
              onRemove: () => setState(() => _volume = null),
              onStart: () => _startVolume(patientId, _volume!),
            )
          else
            _DropZone(picking: _picking, hasFile: file != null, onTap: _picking ? null : _pick),
          if (patientId != null && _volume != null)
            const SizedBox.shrink()
          else if (file != null) ...[
            const SizedBox(height: AppSpacing.xxl),
            const SectionHeader('Selected file'),
            const SizedBox(height: AppSpacing.md),
            inspection.when(
              loading: () => const AppCard(
                child: Row(children: [
                  SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
                  SizedBox(width: AppSpacing.md),
                  Text('Checking the image…', style: AppTextStyles.bodySmall),
                ]),
              ),
              error: (e, _) => AppCard(child: Text(userMessage(e), style: AppTextStyles.bodySmall)),
              data: (result) {
                final checks = MriRules.check(file, result);
                final ok = MriRules.canAnalyze(checks);
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _SelectedFileCard(
                    file: file,
                    inspection: result,
                    checks: checks,
                    onRemove: () => ref.read(selectedMriProvider.notifier).select(null),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.lock_outline_rounded, size: 20, color: AppColors.doctor),
                    SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                                text: 'Your scan is stored privately.\n',
                                style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
                            TextSpan(text: 'Only you and your care team can open it · file metadata removed.'),
                          ]),
                          style: AppTextStyles.bodySmall),
                    ),
                  ]),
                  const SizedBox(height: AppSpacing.xl),
                  AppButton(
                    key: const Key('startAnalysis'),
                    label: patientId == null ? 'Send to my doctor' : 'Analyze MRI',
                    icon: patientId == null ? Icons.send_outlined : Icons.filter_center_focus_rounded,
                    loading: _starting,
                    onPressed: ok ? () => _start(file, checks) : null,
                  ),
                  if (!ok) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const Text('Fix the failed checks by choosing another image.',
                        style: AppTextStyles.caption, textAlign: TextAlign.center),
                  ],
                ]);
              },
            ),
          ] else ...[
            if (patientId != null) ...[
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                key: const Key('pickVolume'),
                label: 'Upload a full MRI scan (.nii)',
                icon: Icons.view_in_ar_outlined,
                variant: AppButtonVariant.secondary,
                loading: _pickingVolume,
                onPressed: _pickingVolume ? null : _pickVolume,
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            _SliceGuide(forDoctor: patientId != null),
          ],
        ],
      ),
    );
  }
}

/// Patient confirmation after an upload. It says the scan arrived and what
/// happens next, and nothing about the analysis.
class _SentToDoctor extends StatelessWidget {
  const _SentToDoctor();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload MRI Scan')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.xl, AppSpacing.screen, AppSpacing.xxl),
        children: [
          const Icon(Icons.check_circle_outline_rounded, size: 48, color: AppColors.success),
          const SizedBox(height: AppSpacing.lg),
          const Text('Sent to your doctor', style: AppTextStyles.title, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Your scan was received. Your doctor will review it, and you will get a notification when the '
            'result is released to you.',
            style: AppTextStyles.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          const InfoNote('For anything urgent, contact your clinic directly. In an emergency, call your local '
              'emergency number.'),
          const SizedBox(height: AppSpacing.xl),
          AppButton(key: const Key('uploadDone'), label: 'Done', onPressed: () => context.pop()),
        ],
      ),
    );
  }
}

class _DropZone extends StatelessWidget {
  const _DropZone({required this.picking, required this.hasFile, required this.onTap});

  final bool picking;
  final bool hasFile;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: hasFile ? 'Choose a different MRI image' : 'Choose an MRI image',
      excludeSemantics: true,
      child: CustomPaint(
        foregroundPainter: _DashedBorder(),
        child: Material(
          color: AppColors.primaryTint,
          borderRadius: BorderRadius.circular(AppRadii.card),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const Key('pickMri'),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 200),
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: picking
                      ? const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2.4))
                      : const Icon(Icons.upload_rounded, size: 30, color: AppColors.primary),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(hasFile ? 'Choose a different image' : 'Tap to upload MRI',
                    style: AppTextStyles.headline, textAlign: TextAlign.center),
                const SizedBox(height: 4),
                const Text('PNG or JPG · Maximum size: 10 MB',
                    style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
                const SizedBox(height: 4),
                const Text('One axial slice · face pointing up · brain tissue visible',
                    style: AppTextStyles.caption, textAlign: TextAlign.center),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Which slice to upload (review comment 7). The model was trained on axial
/// slices taken through the brain, rotated so the face points up; other slices
/// are outside what it has seen.
class _SliceGuide extends StatelessWidget {
  const _SliceGuide({required this.forDoctor});

  final bool forDoctor;

  static const _points = [
    'An axial (horizontal) slice of the brain.',
    'Face pointing up: the front of the head at the top of the image.',
    'From the middle of the brain, with brain tissue filling most of the image. '
        'Not a slice from the top of the head or below the brain.',
    'PNG if you have it. JPEG compression changes the image slightly.',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Overline('Which slice to upload'),
      const SizedBox(height: AppSpacing.sm),
      for (final p in _points)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(top: 3),
              child: Icon(Icons.check_rounded, size: 16, color: AppColors.muted),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(p, style: AppTextStyles.bodySmall)),
          ]),
        ),
      const SizedBox(height: AppSpacing.md),
      InfoNote(forDoctor
          ? 'Other images (photos, documents, other body parts) give meaningless results. With a full MRI '
              'scan (.nii), the server picks the slices itself.'
          : 'Other images (photos, documents, other body parts) give meaningless results.'),
    ]);
  }
}

/// A full MRI scan picked by the doctor, with what the server will do with it.
class _VolumeCard extends StatelessWidget {
  const _VolumeCard({required this.volume, required this.starting, required this.onRemove, required this.onStart});

  final VolumeFile volume;
  final bool starting;
  final VoidCallback onRemove;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final problem = VolumeRules.problem(volume);
    final mb = (volume.sizeBytes / (1024 * 1024)).toStringAsFixed(1);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        key: const Key('volumeCard'),
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.view_in_ar_outlined, size: 28, color: AppColors.primary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(volume.name, style: AppTextStyles.mono.copyWith(fontSize: 15), overflow: TextOverflow.ellipsis),
                Text('$mb MB · Full MRI scan (NIfTI)', style: AppTextStyles.caption.copyWith(fontSize: 14)),
                if (problem != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(problem, style: AppTextStyles.caption.copyWith(color: AppColors.error)),
                ],
              ]),
            ),
            IconButton(tooltip: 'Remove file', onPressed: onRemove, icon: const Icon(Icons.close_rounded)),
          ]),
          const SizedBox(height: AppSpacing.lg),
          const Divider(),
          const SizedBox(height: AppSpacing.lg),
          const Overline('What the server does'),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            '1. Takes every axial slice and turns it so the face points up.\n'
            '2. Keeps the slices the brain detector accepts.\n'
            '3. Masks each slice as in training and leaves out the last 15 (top of the head).\n'
            '4. Runs the model on each slice and averages the scores.',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('This takes about a minute.', style: AppTextStyles.caption),
        ]),
      ),
      const SizedBox(height: AppSpacing.xl),
      AppButton(
        key: const Key('startVolumeAnalysis'),
        label: 'Analyze full scan',
        icon: Icons.filter_center_focus_rounded,
        loading: starting,
        onPressed: problem == null ? onStart : null,
      ),
    ]);
  }
}

class _DashedBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF8FBDB6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(AppRadii.card)));
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SelectedFileCard extends StatelessWidget {
  const _SelectedFileCard({required this.file, required this.inspection, required this.checks, required this.onRemove});

  final MriFile file;
  final MriInspection? inspection;
  final List<MriCheck> checks;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final mb = (file.sizeBytes / (1024 * 1024)).toStringAsFixed(1);
    final dims = inspection == null ? '' : ' · ${inspection!.width} × ${inspection!.height}';
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 72,
              height: 72,
              color: Colors.black,
              child: inspection == null
                  ? const Icon(Icons.broken_image_outlined, color: Colors.white54)
                  : Image.memory(file.bytes, fit: BoxFit.cover, semanticLabel: 'Selected MRI image'),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(file.name, style: AppTextStyles.mono.copyWith(fontSize: 15), overflow: TextOverflow.ellipsis),
              Text('$mb MB$dims · ${file.format.label}', style: AppTextStyles.caption.copyWith(fontSize: 14)),
              const SizedBox(height: AppSpacing.sm),
              const Text('Ready to upload', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
            ]),
          ),
          IconButton(tooltip: 'Remove image', onPressed: onRemove, icon: const Icon(Icons.close_rounded)),
        ]),
        const SizedBox(height: AppSpacing.lg),
        const Divider(),
        const SizedBox(height: AppSpacing.lg),
        const Overline('Validation'),
        const SizedBox(height: AppSpacing.sm),
        for (final c in checks) _CheckRow(check: c),
      ]),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});

  final MriCheck check;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (check.status) {
      CheckStatus.passed => (Icons.check_rounded, AppColors.success),
      CheckStatus.warning => (Icons.priority_high_rounded, AppColors.pending),
      CheckStatus.failed => (Icons.close_rounded, AppColors.error),
    };
    final passed = check.status == CheckStatus.passed;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: Colors.white, semanticLabel: check.status.name),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(check.label, style: AppTextStyles.body.copyWith(color: AppColors.ink)),
            if (!passed) Text(check.detail, style: AppTextStyles.caption.copyWith(color: color)),
          ]),
        ),
        if (passed)
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.sm, top: 2),
            child: Text(check.detail,
                style: AppTextStyles.mono.copyWith(fontWeight: FontWeight.w400, color: AppColors.muted, fontSize: 13)),
          ),
      ]),
    );
  }
}
