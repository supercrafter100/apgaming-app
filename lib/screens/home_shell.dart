import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../theme.dart';
import '../widgets/motion.dart';
import 'account_screen.dart';
import 'admin/admin_reservations_screen.dart';
import 'my_reservations_screen.dart';

/// Bottom-tab layout. Staff with `reservations.manage` get an extra "Beheer" tab.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final profile = AppScope.authOf(context).profile!;
    final isStaff = profile.canManageReservations;

    final tabs = <({Widget screen, NavigationDestination destination})>[
      (
        screen: const MyReservationsScreen(),
        destination: const NavigationDestination(
          icon: Icon(Icons.event_note_outlined),
          selectedIcon: Icon(Icons.event_note_rounded),
          label: 'Reservaties',
        ),
      ),
      if (isStaff)
        (
          screen: const AdminReservationsScreen(),
          destination: const NavigationDestination(
            icon: Icon(Icons.admin_panel_settings_outlined),
            selectedIcon: Icon(Icons.admin_panel_settings_rounded),
            label: 'Beheer',
          ),
        ),
      (
        screen: const AccountScreen(),
        destination: const NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded),
          label: 'Account',
        ),
      ),
    ];
    final index = _index.clamp(0, tabs.length - 1);

    return Scaffold(
      // Content scrolls underneath the translucent tab bar.
      extendBody: true,
      body: Stack(
        children: [for (var i = 0; i < tabs.length; i++) _FadeThroughTab(active: i == index, child: tabs[i].screen)],
      ),
      bottomNavigationBar: Frosted(
        color: const Color(0xCC0A0F25),
        border: const Border(top: BorderSide(color: HubColors.border)),
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          height: 68,
          selectedIndex: index,
          animationDuration: const Duration(milliseconds: 400),
          onDestinationSelected: (i) {
            if (i == index) return;
            HapticFeedback.selectionClick();
            setState(() => _index = i);
          },
          destinations: [for (final t in tabs) t.destination],
        ),
      ),
    );
  }
}

/// Keeps every tab alive (scroll position, loaded data); the incoming tab fades and settles in.
class _FadeThroughTab extends StatelessWidget {
  const _FadeThroughTab({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Offstage(
      offstage: !active,
      child: AnimatedOpacity(
        opacity: active ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: AnimatedScale(
          scale: active ? 1 : 0.985,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          // Pause animations (skeletons, spinners) in hidden tabs.
          child: TickerMode(enabled: active, child: child),
        ),
      ),
    );
  }
}
