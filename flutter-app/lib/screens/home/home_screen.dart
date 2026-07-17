import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:go_router/go_router.dart';

import '../../router/tab_slide.dart';
import '../../vendor/chuk_ui/chuk_nav_bar.dart';
import '../../widgets/app_nav_bar.dart';
import '../../widgets/offline_banner.dart';

class HomeScreen extends StatefulWidget {
  final Widget child;

  const HomeScreen({super.key, required this.child});

  /// How long a tab slide takes. Literally the motion the nav bar's highlight
  /// glides and its labels collapse with — the bar and the page are one
  /// movement, and two curves would read as two separate things happening at
  /// once.
  static const slideDuration = AppNavBar.motionDuration;
  static const slideCurve = AppNavBar.motionCurve;

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
  /// The tab we are showing. Which way the slide runs is [TabSlide]'s job —
  /// the pages animate themselves inside the router's Navigator, because the
  /// shell may not hold on to an outgoing page: go_router hands the shell the
  /// same GlobalKey'd child every time, and keeping the old one alive for the
  /// length of an animation puts that key in the tree twice. The framework
  /// then hands the element to the newcomer and the page sliding out renders
  /// empty.
  int _index = 0;

  /// What the bar is showing, and what the user's last drag asked for. They
  /// differ on purpose: [_wantCollapsed] is the intent ("I scrolled down"),
  /// [_collapsed] is what survives the guards in [_onScroll] — a page that
  /// can't scroll never gets to hide its own labels.
  bool _collapsed = false;
  bool _wantCollapsed = false;

  /// How far down a page must be before the labels may go. Under this the bar
  /// stays open, so the top of a page always shows the full bar and a stray
  /// pixel of drag there can't make it flinch.
  static const _collapseAfter = 24.0;

  /// Collapses the bar while the user reads down a tab and gives the labels
  /// back on the way up.
  ///
  /// One listener in the shell, wrapped around the body: every scrollable a tab
  /// builds bubbles its notifications up through here on its way to nowhere, so
  /// all four tabs get this for free and none of them has to grow a controller,
  /// a callback, or its own idea of "far enough". That also covers the lists
  /// nested inside a tab (the Bahnhof tab's TabBarView children), which a
  /// controller wired per screen would have missed.
  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis == Axis.horizontal) {
      // A sideways drag is a swipe to another page (the Bahnhof tab's inner
      // TabBarView), not reading. The page it lands on starts at its own top
      // and may not scroll at all, and it won't say so — it never moves, so it
      // never notifies. Treat the swipe like a shell tab change and hand the
      // labels back, or they'd stay hidden over, say, the station map forever.
      if (n is UserScrollNotification && n.direction != ScrollDirection.idle) {
        _wantCollapsed = false;
        _setCollapsed(false);
      }
      return false;
    }
    if (n is UserScrollNotification) {
      switch (n.direction) {
        // Content sliding up under the finger = reading further down.
        case ScrollDirection.reverse:
          _wantCollapsed = true;
        case ScrollDirection.forward:
          _wantCollapsed = false;
        // Let go, fling settled: keep the last intent. The bar must stay small
        // while you read, not spring open the moment you stop moving.
        case ScrollDirection.idle:
          break;
      }
    }
    // Re-checked on every notification, not just on the one that set the
    // intent: a drag that starts at the top reports "reverse" exactly once,
    // while pixels is still 0 and the guard below still says no. Only the
    // update notifications that follow carry it past the threshold.
    final scrollable = n.metrics.maxScrollExtent > 0;
    final atTop = n.metrics.pixels <= _collapseAfter;
    _setCollapsed(_wantCollapsed && scrollable && !atTop);
    return false;
  }

  void _setCollapsed(bool value) {
    if (value == _collapsed) return;
    setState(() => _collapsed = value);
  }

  @override
  Widget build(BuildContext context) {
    final index = HomeScreen.indexOfLocation(GoRouterState.of(context).uri.path);
    // Read during build on purpose: the rebuild is already happening (the
    // route changed), and the direction must be known for THIS frame — a
    // setState here would be a frame late and slide the wrong way.
    if (index != _index) {
      // Hand the direction to the pages before the Navigator builds them:
      // they run the slide, we only know which way it goes.
      TabSlide.to(index, from: _index);
      _index = index;
      // The tab we're leaving may have been scrolled deep; the one arriving
      // starts at its own top and might not scroll at all — and a page with no
      // scrollable never sends a notification, so nothing else would ever open
      // the bar again. Reset with the slide.
      _collapsed = false;
      _wantCollapsed = false;
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
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: widget.child,
            ),
          ),
        ],
      ),
      bottomNavigationBar: AppNavBar(
        collapsed: _collapsed,
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
