// The tab slide runs on the router's pages, never in the shell around them.
//
// REGRESSION: it first lived in the shell (an AnimatedSwitcher holding the
// outgoing child for 260 ms). go_router hands the shell the same GlobalKey'd
// child every build, so that put one key in the tree twice on EVERY tab
// switch; the framework then gave the element to the newcomer and the page
// sliding out rendered empty — an animation that animated nothing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:besser_bahn/screens/home/home_screen.dart';
import 'package:besser_bahn/router/tab_slide.dart';

void main() {
  testWidgets('switching tabs must not duplicate a GlobalKey', (tester) async {
    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        ShellRoute(
          navigatorKey: GlobalKey<NavigatorState>(),
          builder: (c, s, child) => HomeScreen(child: child),
          routes: [
            GoRoute(
                path: '/search',
                pageBuilder: (c, s) => CustomTransitionPage(
                    key: s.pageKey,
                    transitionDuration: TabSlide.duration,
                    reverseTransitionDuration: TabSlide.duration,
                    transitionsBuilder: (c, a, _, child) =>
                        TabSlide.build(0, a, child),
                    child: const _Page('SUCHE'))),
            GoRoute(
                path: '/journeys',
                pageBuilder: (c, s) => CustomTransitionPage(
                    key: s.pageKey,
                    transitionDuration: TabSlide.duration,
                    reverseTransitionDuration: TabSlide.duration,
                    transitionsBuilder: (c, a, _, child) =>
                        TabSlide.build(1, a, child),
                    child: const _Page('REISEN'))),
          ],
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();

    router.go('/journeys');
    await tester.pump();            // mid-slide: both pages alive
    await tester.pump(const Duration(milliseconds: 130));

    expect(tester.takeException(), isNull,
        reason: 'the outgoing tab must survive the slide');
    // Mid-slide BOTH pages are on screen — that is the pan.
    expect(find.text('SUCHE'), findsOneWidget);
    expect(find.text('REISEN'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('SUCHE'), findsNothing);
  });
}

class _Page extends StatelessWidget {
  final String label;
  const _Page(this.label);
  @override
  Widget build(BuildContext context) =>
      SizedBox.expand(child: Center(child: Text(label)));
}
