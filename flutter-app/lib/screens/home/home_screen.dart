import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../vendor/chuk_ui/chuk_nav_bar.dart';
import '../../widgets/app_nav_bar.dart';
import '../../widgets/offline_banner.dart';

class HomeScreen extends StatelessWidget {
  final Widget child;

  const HomeScreen({super.key, required this.child});

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/search')) return 0;
    if (location.startsWith('/journeys')) return 1;
    if (location.startsWith('/nearby')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Don't lift the bottom nav bar above the soft keyboard — it should sit
      // behind it. Per-tab scaffolds keep their own resize behaviour.
      resizeToAvoidBottomInset: false,
      // The glass bar floats *over* the content instead of taking layout space
      // — that's the whole point of the blur. In exchange, Flutter reports the
      // bar's height as the body's bottom padding, which the tabs pad their
      // scrollables and bottom-anchored overlays by (AppNavBar.insetOf).
      extendBody: true,
      // Offline strip sits above the active tab (collapses to nothing online),
      // so the user always knows when they're on cached data.
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: AppNavBar(
        index: _currentIndex(context),
        onChanged: (index) {
          switch (index) {
            case 0:
              context.go('/search');
            case 1:
              context.go('/journeys');
            case 2:
              context.go('/nearby');
            case 3:
              context.go('/profile');
          }
        },
        items: const [
          ChukNavItem(
            icon: Icons.search_outlined,
            activeIcon: Icons.search,
            label: 'Suche',
          ),
          ChukNavItem(
            icon: Icons.bookmark_border,
            activeIcon: Icons.bookmark,
            label: 'Reisen',
          ),
          ChukNavItem(
            icon: Icons.train_outlined,
            activeIcon: Icons.train,
            label: 'Bahnhof',
          ),
          ChukNavItem(
            icon: Icons.account_circle_outlined,
            activeIcon: Icons.account_circle,
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
