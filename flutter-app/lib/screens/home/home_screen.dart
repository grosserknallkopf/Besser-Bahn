import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../vendor/chuk_ui/chuk_nav_bar.dart';
import '../../widgets/app_nav_bar.dart';
import '../../widgets/offline_banner.dart';

class HomeScreen extends StatefulWidget {
  final Widget child;

  const HomeScreen({super.key, required this.child});

  /// How long a tab slide takes. Same 260 ms / easeOutCubic the nav bar's
  /// highlight glides with — the bar and the page are one movement, and two
  /// curves would read as two separate things happening at once.
  static const slideDuration = Duration(milliseconds: 260);
  static const slideCurve = Curves.easeOutCubic;

  static int indexOfLocation(String location) {
    if (location.startsWith('/search')) return 0;
    if (location.startsWith('/journeys')) return 1;
    if (location.startsWith('/nearby')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0;
  }

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// The tab we are showing, and which way the last change went: +1 = the new
  /// tab sits to the RIGHT, so it comes in from the right and the old one
  /// leaves to the left. −1 mirrors that. This is what sells "the tabs lie
  /// side by side" instead of a cross-fade.
  int _index = 0;
  double _dir = 1;

  /// Slides the outgoing tab out and the incoming one in, in the direction the
  /// tabs actually sit — left tab leaves to the right, right tab comes from the
  /// right. Both move at once and in opposite directions; animating only the
  /// incoming page would read as a card dropped on top, not as a strip of
  /// pages being panned.
  Widget _slide(Widget child) {
    return ClipRect(
      child: AnimatedSwitcher(
        duration: HomeScreen.slideDuration,
        switchInCurve: HomeScreen.slideCurve,
        switchOutCurve: HomeScreen.slideCurve,
        // Default centres the children and sizes to the biggest; tabs must
        // simply fill the body, both during the slide and after.
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.expand,
          children: [...previous, ?current],
        ),
        transitionBuilder: (child, animation) {
          // The incoming child is the one carrying the current tab's key; the
          // other is on its way out with a reversed animation (1 → 0), which is
          // why both can use the same "begin → Offset.zero" tween and still
          // travel opposite ways.
          final incoming = (child.key as ValueKey<int>?)?.value == _index;
          final begin = Offset(incoming ? _dir : -_dir, 0);
          return SlideTransition(
            position: Tween<Offset>(begin: begin, end: Offset.zero)
                .animate(animation),
            child: child,
          );
        },
        child: KeyedSubtree(key: ValueKey<int>(_index), child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final index = HomeScreen.indexOfLocation(GoRouterState.of(context).uri.path);
    // Read during build on purpose: the rebuild is already happening (the
    // route changed), and the direction must be known for THIS frame — a
    // setState here would be a frame late and slide the wrong way.
    if (index != _index) {
      _dir = index > _index ? 1 : -1;
      _index = index;
    }
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
          Expanded(child: _slide(widget.child)),
        ],
      ),
      bottomNavigationBar: AppNavBar(
        index: _index,
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
