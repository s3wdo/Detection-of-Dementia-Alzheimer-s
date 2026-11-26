import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Section title with an optional action on the right ("See all").
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Semantics(header: true, child: Text(title, style: AppTextStyles.headline.copyWith(fontSize: 17))),
        ),
        if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

/// Circle with initials. Photos of people are not used (no licensed images).
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.name,
    this.size = 44,
    this.background = AppColors.primaryTint,
    this.foreground = AppColors.navy,
  });

  final String name;
  final double size;
  final Color background;
  final Color foreground;

  String get initials {
    final parts = name.replaceAll('Dr.', '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: name,
      excludeSemantics: true,
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: background,
        child: Text(
          initials,
          style: TextStyle(color: foreground, fontWeight: FontWeight.w600, fontSize: size * 0.36),
        ),
      ),
    );
  }
}

/// Settings-style row: leading icon on a tinted tile, title, quiet subtitle, chevron or trailing widget.
class ListRowTile extends StatelessWidget {
  const ListRowTile({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor = AppColors.muted,
    this.titleColor,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color iconColor;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    // The default icon is teal on the light teal tile; a source colour keeps its own tint.
    final plain = iconColor == AppColors.muted;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTouch + 8),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: RowGroup.insetOf(context)),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: plain ? AppColors.primaryTint : iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 22, color: plain ? AppColors.primaryDark : iconColor),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.label.copyWith(fontSize: 16, color: titleColor)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: AppTextStyles.caption.copyWith(fontSize: 14)),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.4),
                  child: trailing,
                )
              else if (onTap != null)
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// A group of rows in one white rounded card, with an optional spaced-capitals
/// heading above it. Rows are separated by hairline dividers.
///
/// Rows read their side padding from [insetOf], so a tap highlight runs to the
/// card's edges. Use [ListRowTile] or [GroupRow] for the children.
class RowGroup extends StatelessWidget {
  const RowGroup({super.key, this.title, this.action, required this.children});

  static const _inset = AppSpacing.lg;

  /// Side padding a row should use: the card's inset inside a group, 0 elsewhere.
  static double insetOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RowGroupScope>() == null ? 0 : _inset;

  final String? title;

  /// Optional text button on the heading line, e.g. "View all".
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (title != null)
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTouch),
          child: Row(children: [
            Expanded(child: Overline(title!)),
            if (action != null) action!,
          ]),
        ),
      if (children.isNotEmpty)
        Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: _RowGroupScope(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: _inset, endIndent: _inset),
                children[i],
              ],
            ]),
          ),
        ),
    ]);
  }
}

class _RowGroupScope extends InheritedWidget {
  const _RowGroupScope({required super.child});

  @override
  bool updateShouldNotify(_RowGroupScope oldWidget) => false;
}

/// A custom row inside a [RowGroup]. It takes the group's side padding, so the
/// tap highlight runs edge to edge.
class GroupRow extends StatelessWidget {
  const GroupRow({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final padded = Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: RowGroup.insetOf(context)),
      child: child,
    );
    return onTap == null ? padded : InkWell(onTap: onTap, child: padded);
  }
}

/// Label on the left, value on the right — for read-only detail lists.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: AppTextStyles.caption)),
          const SizedBox(width: AppSpacing.md),
          Expanded(flex: 3, child: Text(value, style: AppTextStyles.label, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

/// App-bar title from the design: serif title with an optional grey subtitle.
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: AppTextStyles.screenTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        // The subtitle is dropped at very large text sizes so the title still fits the app bar.
        if (subtitle != null && MediaQuery.textScalerOf(context).scale(10) <= 13)
          Text(subtitle!,
              style: AppTextStyles.caption.copyWith(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

/// Small spaced-capitals label above a group, e.g. "1 · AI OUTPUT".
class Overline extends StatelessWidget {
  const Overline(this.text, {super.key, this.color = AppColors.muted});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Semantics(header: true, child: Text(text.toUpperCase(), style: AppTextStyles.overline.copyWith(color: color)));
}

/// Two or three tabs in a beige track with a white selected pill, as in the design
/// (Upcoming / Past, Original / Heatmap / Overlay). Use as `AppBar.bottom`.
class PillTabBar extends StatelessWidget implements PreferredSizeWidget {
  const PillTabBar({super.key, required this.labels});

  final List<String> labels;

  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadii.button)),
        child: TabBar(
          tabs: [for (final l in labels) Tab(height: 48, text: l)],
          indicator: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadii.button - 3)),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: AppColors.navy,
          unselectedLabelColor: AppColors.muted,
          labelStyle: AppTextStyles.label.copyWith(fontSize: 16),
          unselectedLabelStyle: AppTextStyles.label.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
          splashBorderRadius: BorderRadius.circular(AppRadii.button - 3),
        ),
      ),
    );
  }
}

/// Quiet information line with an (i) icon. No box, so it never competes with content.
class InfoNote extends StatelessWidget {
  const InfoNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(top: 1),
        child: Icon(Icons.info_outline_rounded, size: 18, color: AppColors.muted),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(child: Text(text, style: AppTextStyles.bodySmall)),
    ]);
  }
}

/// Technical details: spaced-capitals title and mono label/value rows between dividers.
class TechPanel extends StatelessWidget {
  const TechPanel({super.key, required this.title, required this.rows, this.locked = false});

  final String title;
  final List<(String, String)> rows;

  /// Shows a lock icon: clinician-only information.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final mono = AppTextStyles.mono.copyWith(fontSize: 14);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border), bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Overline(title)),
          if (locked) const Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.muted),
        ]),
        const SizedBox(height: AppSpacing.sm),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(label, style: mono.copyWith(color: AppColors.muted, fontWeight: FontWeight.w400))),
              const SizedBox(width: AppSpacing.md),
              Flexible(child: Text(value, style: mono, textAlign: TextAlign.right)),
            ]),
          ),
      ]),
    );
  }
}
