import 'package:flutter/material.dart';
import 'app_sidebar.dart';
import '../../features/overview/overview_screen.dart';
import '../../features/applications/applications_screen.dart';
import '../../features/focus/focus_screen.dart';
import '../../features/insights/insights_screen.dart';
import '../../features/limits/limits_screen.dart';
import '../../features/settings/settings_screen.dart';

class AppNavigation extends InheritedWidget {
  final void Function(int) navigateTo;

  const AppNavigation({
    super.key,
    required this.navigateTo,
    required super.child,
  });

  static AppNavigation of(BuildContext context) {
    final nav = context.dependOnInheritedWidgetOfExactType<AppNavigation>();
    assert(nav != null, 'No AppNavigation found in context');
    return nav!;
  }

  @override
  bool updateShouldNotify(covariant AppNavigation oldWidget) => false;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const OverviewScreen(),
    const ApplicationsScreen(),
    const FocusScreen(),
    const InsightsScreen(),
    const LimitsScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return AppNavigation(
      navigateTo: (index) {
        if (index >= 0 && index < _screens.length) {
          setState(() {
            _selectedIndex = index;
          });
        }
      },
      child: Scaffold(
        body: Row(
          children: [
            AppSidebar(
              selectedIndex: _selectedIndex,
              onItemSelected: (index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.02, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey<int>(_selectedIndex),
                  child: _screens[_selectedIndex],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
