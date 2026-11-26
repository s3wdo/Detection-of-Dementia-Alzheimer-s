import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/app_bottom_nav.dart';

/// Bottom-nav shell for doctors. Each tab keeps its own navigation stack.
class DoctorShell extends StatelessWidget {
  const DoctorShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const items = [
    AppNavItem(label: 'Dashboard', icon: Icons.grid_view_outlined, selectedIcon: Icons.grid_view_outlined),
    AppNavItem(label: 'Patients', icon: Icons.people_outline_rounded, selectedIcon: Icons.people_outline_rounded),
    AppNavItem(label: 'Appointments', icon: Icons.calendar_today_outlined, selectedIcon: Icons.calendar_today_outlined),
    AppNavItem(label: 'Profile', icon: Icons.person_outline_rounded, selectedIcon: Icons.person_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) => _RoleShell(shell: shell, items: items);
}

/// Bottom-nav shell for patients.
class PatientShell extends StatelessWidget {
  const PatientShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const items = [
    AppNavItem(label: 'Home', icon: Icons.home_outlined, selectedIcon: Icons.home_outlined),
    AppNavItem(label: 'History', icon: Icons.schedule_rounded, selectedIcon: Icons.schedule_rounded),
    AppNavItem(
        label: 'Counselling', icon: Icons.chat_bubble_outline_rounded, selectedIcon: Icons.chat_bubble_outline_rounded),
    AppNavItem(label: 'Profile', icon: Icons.person_outline_rounded, selectedIcon: Icons.person_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) => _RoleShell(shell: shell, items: items);
}

class _RoleShell extends StatelessWidget {
  const _RoleShell({required this.shell, required this.items});

  final StatefulNavigationShell shell;
  final List<AppNavItem> items;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: AppBottomNav(
        items: items,
        currentIndex: shell.currentIndex,
        // Tapping the active tab again returns it to its first screen.
        onTap: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
      ),
    );
  }
}
