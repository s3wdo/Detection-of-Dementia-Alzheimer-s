import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AppNavItem {
  const AppNavItem({required this.label, required this.icon, required this.selectedIcon});

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// White bottom bar with icon + label, active item in primary blue (as in the design).
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.items, required this.currentIndex, required this.onTap});

  final List<AppNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    // Colours, height and label styles come from the app theme.
    return DecoratedBox(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      child: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: onTap,
        destinations: [
          for (final item in items)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: item.label,
            ),
        ],
      ),
    );
  }
}
