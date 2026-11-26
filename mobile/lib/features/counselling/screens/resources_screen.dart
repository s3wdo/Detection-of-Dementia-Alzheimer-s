import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/layout_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../counselling_providers.dart';
import '../data/models/counselling_models.dart';

/// Educational Resources (design section 19): search and browse every article.
class ResourcesScreen extends ConsumerStatefulWidget {
  const ResourcesScreen({super.key});

  @override
  ConsumerState<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends ConsumerState<ResourcesScreen> {
  String _query = '';
  ResourceCategory? _category;

  bool _matches(Resource r) {
    final q = _query.trim().toLowerCase();
    final inCategory = _category == null || r.category == _category;
    final inText = q.isEmpty ||
        r.title.toLowerCase().contains(q) ||
        r.summary.toLowerCase().contains(q) ||
        r.keywords.any((k) => k.toLowerCase().contains(q));
    return inCategory && inText;
  }

  @override
  Widget build(BuildContext context) {
    final resources = ref.watch(resourcesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const PageTitle('Educational Resources', subtitle: 'General information · pending clinical review'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xxl),
        children: [
          TextField(
            key: const Key('resourceSearch'),
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(hintText: 'Search resources…', prefixIcon: Icon(Icons.search_rounded)),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 56,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              _chip(null, 'All'),
              for (final c in ResourceCategory.values) _chip(c, c.label),
            ]),
          ),
          const SizedBox(height: AppSpacing.sm),
          AsyncValueView<List<Resource>>(
            value: resources,
            onRetry: () => ref.invalidate(resourcesProvider),
            data: (all) {
              final list = all.where(_matches).toList();
              if (list.isEmpty) {
                return const EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No matching resources',
                  message: 'Try another word or category.',
                );
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Divider(),
                for (final r in list) ...[
                  InkWell(
                    onTap: () => context.push('/patient/counselling/resources/${r.slug}'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.title, style: AppTextStyles.headline),
                        const SizedBox(height: AppSpacing.xs),
                        Text(r.summary, style: AppTextStyles.bodySmall),
                        const SizedBox(height: AppSpacing.sm),
                        Text('${r.source} · ${r.minutes} min read', style: AppTextStyles.caption),
                      ]),
                    ),
                  ),
                  const Divider(),
                ],
              ]);
            },
          ),
        ],
      ),
    );
  }

  Widget _chip(ResourceCategory? c, String label) {
    final selected = _category == c;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _category = c),
        side: selected ? BorderSide.none : null,
      ),
    );
  }
}
