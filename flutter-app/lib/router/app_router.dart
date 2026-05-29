import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/home/home_screen.dart';
import '../screens/train_lookup/train_lookup_screen.dart';
import '../screens/connection_search/connection_search_screen.dart';
import '../screens/departure_board/departure_board_screen.dart';
import '../screens/station_map/station_map_screen.dart';
import '../screens/connection_search/connection_detail_screen.dart';
import '../models/journey.dart';
import '../screens/split_ticket/split_ticket_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/debug_log/debug_log_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/train',
  routes: [
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => HomeScreen(child: child),
      routes: [
        GoRoute(
          path: '/train',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: TrainLookupScreen(),
          ),
        ),
        GoRoute(
          path: '/search',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ConnectionSearchScreen(),
          ),
        ),
        GoRoute(
          path: '/departures',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: DepartureBoardScreen(),
          ),
        ),
        GoRoute(
          path: '/map',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: StationMapScreen(),
          ),
        ),
        GoRoute(
          path: '/split',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SplitTicketScreen(),
          ),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SettingsScreen(),
          ),
        ),
        GoRoute(
          path: '/debug-log',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: DebugLogScreen(),
          ),
        ),
      ],
    ),
    // Full-screen station map pushed from a journey/stop. Lives on the root
    // navigator (above the tab shell) so it gets a real back button, system
    // back and swipe-back — unlike the /map tab which just switches tabs.
    GoRoute(
      path: '/station-map',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const StationMapScreen(),
    ),
    // Full multi-leg connection detail (pushed from a search result).
    GoRoute(
      path: '/connection',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) =>
          ConnectionDetailScreen(journey: state.extra as Journey),
    ),
    // A single train's run, pushed (with back button) from a connection leg
    // or anywhere — renders the same train view as the tab.
    GoRoute(
      path: '/train-run',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const TrainLookupScreen(),
    ),
  ],
);
