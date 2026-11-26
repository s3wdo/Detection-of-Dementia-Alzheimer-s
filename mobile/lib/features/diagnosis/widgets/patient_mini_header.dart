import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../patients/patients_providers.dart';

/// "Selected patient" strip shown at the top of the diagnosis screens.
class PatientMiniHeader extends ConsumerWidget {
  const PatientMiniHeader({super.key, required this.patientId, this.label = 'Patient', this.badge});

  final String patientId;
  final String label;

  /// Optional green status pill on the right, e.g. "Assigned".
  final String? badge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patient = ref.watch(patientProvider(patientId)).value;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      child: Row(children: [
        AppAvatar(name: patient?.fullName ?? '…', size: 40),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: AppTextStyles.caption),
            patient == null
                ? const Text('Loading…', style: AppTextStyles.label)
                : Text.rich(TextSpan(children: [
                    TextSpan(text: '${patient.fullName}  ', style: AppTextStyles.label.copyWith(fontSize: 16)),
                    TextSpan(text: patient.mrn, style: AppTextStyles.mono.copyWith(color: AppColors.muted)),
                  ])),
          ]),
        ),
        if (badge != null)
          Flexible(
              child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: AppColors.successTint, borderRadius: BorderRadius.circular(AppRadii.pill)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_rounded, size: 16, color: AppColors.success),
              const SizedBox(width: 4),
              Flexible(
                  child: Text(badge!, style: AppTextStyles.label.copyWith(color: AppColors.success, fontSize: 13.5))),
            ]),
          )),
      ]),
    );
  }
}
