import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../../core/widgets/source_style.dart';
import '../../timeline/data/models/timeline_event.dart';
import '../../timeline/widgets/timeline_tile.dart';

/// Recent activity as plain divider rows. The icon colour marks the source
/// (AI / doctor / admin) the same way as the timeline.
class ActivityList extends StatelessWidget {
  const ActivityList({
    super.key,
    required this.events,
    required this.now,
    this.title,
    this.action,
    this.showPatientName = false,
    this.onTap,
  });

  final List<TimelineEvent> events;
  final DateTime now;
  final String? title;
  final Widget? action;
  final bool showPatientName;
  final void Function(TimelineEvent event)? onTap;

  @override
  Widget build(BuildContext context) {
    return RowGroup(
      title: title,
      action: action,
      children: [
        for (final e in events)
          ListRowTile(
            icon: timelineIcon(e.kind),
            iconColor: sourceStyle(e.source).color,
            title: showPatientName && e.patientName != null ? '${e.patientName} · ${e.title}' : e.title,
            subtitle: '${e.detail} · ${Fmt.relative(e.at, now)}',
            onTap: onTap == null ? null : () => onTap!(e),
            trailing: onTap == null ? SourceTag(e.source) : null,
          ),
      ],
    );
  }
}

/// Vertical gap between dashboard sections.
const dashboardSectionGap = SizedBox(height: AppSpacing.xxl);
