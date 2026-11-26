import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/clock.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../data/models/patient.dart';
import '../patients_providers.dart';
import '../widgets/patient_row.dart';

/// Doctor's assigned patients with search and filters (design section 05).
class PatientListScreen extends ConsumerStatefulWidget {
  const PatientListScreen({super.key});

  @override
  ConsumerState<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends ConsumerState<PatientListScreen> {
  late final TextEditingController _search = TextEditingController(text: ref.read(patientQueryProvider).text);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Patients are created and assigned by the clinic (no self-registration).
  void _addPatient() => showAppBottomSheet<void>(
        context,
        title: 'Add a patient',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text(
            'New patients are registered by the clinic administrator and then assigned to you, so every record '
            'is verified. Once a patient is assigned, they appear in this list automatically.',
            style: AppTextStyles.body,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(label: 'OK', onPressed: () => Navigator.of(context).pop()),
        ]),
      );

  void _openFilters(PatientFilter current, Map<PatientFilter, int>? counts) => showAppBottomSheet<void>(
        context,
        title: 'Filter patients',
        child: RadioGroup<PatientFilter>(
          groupValue: current,
          onChanged: (f) {
            if (f != null) ref.read(patientQueryProvider.notifier).setFilter(f);
            Navigator.of(context).pop();
          },
          child: Column(children: [
            for (final f in PatientFilter.values)
              RadioListTile<PatientFilter>(
                value: f,
                contentPadding: EdgeInsets.zero,
                title: Text(f.label, style: AppTextStyles.label.copyWith(fontSize: 16)),
                secondary: counts == null ? null : Text('${counts[f]}', style: AppTextStyles.mono),
              ),
            const SizedBox(height: AppSpacing.sm),
            const Text('Sorted by most recent analysis.', style: AppTextStyles.caption),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(patientQueryProvider);
    final patients = ref.watch(patientListProvider);
    final counts = ref.watch(patientCountsProvider).value;
    final now = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(
        title: PageTitle('Patients',
            subtitle: counts == null ? 'Assigned to you' : '${counts[PatientFilter.all]} assigned to you'),
        actions: [
          IconButton(tooltip: 'Add patient', onPressed: _addPatient, icon: const Icon(Icons.add_rounded)),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.sm),
            child: Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('patientSearch'),
                  controller: _search,
                  onChanged: ref.read(patientQueryProvider.notifier).setText,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search patients…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: query.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _search.clear();
                              ref.read(patientQueryProvider.notifier).setText('');
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Tooltip(
                message: 'Filter patients',
                child: Material(
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.input),
                    side: const BorderSide(color: AppColors.borderStrong, width: 1.3),
                  ),
                  child: InkWell(
                    onTap: () => _openFilters(query.filter, counts),
                    customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.input)),
                    child: const SizedBox(width: 56, height: 56, child: Icon(Icons.tune_rounded)),
                  ),
                ),
              ),
            ]),
          ),
          SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
              children: [
                for (final f in PatientFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: ChoiceChip(
                      label: Text(counts == null ? f.label : '${f.label}  ${counts[f]}'),
                      selected: query.filter == f,
                      onSelected: (_) => ref.read(patientQueryProvider.notifier).setFilter(f),
                      side: query.filter == f ? BorderSide.none : null,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncValueView<List<Patient>>(
              value: patients,
              onRetry: () => ref.invalidate(patientListProvider),
              isEmpty: (list) => list.isEmpty,
              empty: const EmptyState(
                icon: Icons.person_search_outlined,
                title: 'No patients found',
                message: 'Try a different name or patient ID, or change the filter.',
              ),
              data: (list) => ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.xs, AppSpacing.screen, AppSpacing.xxl),
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text('Sorted by most recent analysis', style: AppTextStyles.caption),
                  ),
                  RowGroup(children: [
                    for (final p in list)
                      PatientRow(patient: p, now: now, onTap: () => context.push(Routes.doctorPatient(p.id))),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
