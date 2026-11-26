import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/models/info_source.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../../core/widgets/source_style.dart';
import '../../../core/widgets/state_views.dart';
import '../../patients/patients_providers.dart';
import '../data/models/timeline_event.dart';
import '../timeline_providers.dart';
import '../widgets/timeline_tile.dart';

/// Patient timeline (design screen 9) for the doctor. The patient sees the
/// same content inside the History tab via [TimelineBody].
class TimelineScreen extends ConsumerWidget {
  const TimelineScreen.doctor({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(
          title: PageTitle('Patient Timeline', subtitle: ref.watch(patientProvider(patientId)).value?.fullName),
        ),
        body: TimelineBody(patientId: patientId, patientView: false),
      );
}

/// Filter chips + month-grouped events. [patientId] null = the signed-in patient.
class TimelineBody extends ConsumerStatefulWidget {
  const TimelineBody({super.key, required this.patientId, required this.patientView});

  final String? patientId;
  final bool patientView;

  @override
  ConsumerState<TimelineBody> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineBody> {
  InfoSource? _filter; // null = all

  @override
  Widget build(BuildContext context) {
    final patientId = widget.patientId ?? ref.watch(sessionControllerProvider)?.patientId;
    if (patientId == null) return const SizedBox.shrink();
    final args = (patientId: patientId, patientView: widget.patientView);
    final events = ref.watch(timelineProvider(args));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
            children: [
              _chip(null, 'All'),
              for (final s in InfoSource.values) _chip(s, sourceStyle(s).label),
            ],
          ),
        ),
        if (widget.patientView)
          const Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.sm),
            child: Text('Results appear here after your doctor has reviewed and released them.',
                style: AppTextStyles.caption),
          ),
        Expanded(
          child: AsyncValueView<List<TimelineEvent>>(
            value: events,
            onRetry: () => ref.invalidate(timelineProvider(args)),
            data: (all) {
              final list = _filter == null ? all : all.where((e) => e.source == _filter).toList();
              if (list.isEmpty) {
                return const EmptyState(icon: Icons.timeline_rounded, title: 'Nothing here yet');
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.xxl),
                children: _withMonthHeaders(list),
              );
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _withMonthHeaders(List<TimelineEvent> list) {
    final out = <Widget>[];
    String? month;
    for (var i = 0; i < list.length; i++) {
      final m = Fmt.monthYear(list[i].at);
      if (m != month) {
        month = m;
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md, top: AppSpacing.xs),
          child: Semantics(
              header: true, child: Text(m.toUpperCase(), style: AppTextStyles.overline.copyWith(fontSize: 15))),
        ));
      }
      final nextIsSameMonth = i + 1 < list.length && Fmt.monthYear(list[i + 1].at) == m;
      out.add(TimelineTile(event: list[i], isLast: !nextIsSameMonth));
    }
    return out;
  }

  Widget _chip(InfoSource? source, String label) {
    final selected = _filter == source;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filter = source),
        showCheckmark: false,
        side: selected ? BorderSide.none : null,
      ),
    );
  }
}
