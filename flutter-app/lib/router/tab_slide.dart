import 'package:flutter/widgets.dart';

import '../widgets/app_nav_bar.dart';

/// The horizontal slide between the four tabs.
///
/// The tabs lie side by side, so switching pans the strip: pick a tab to the
/// right and it comes in from the right while the old one leaves to the left.
/// Both pages move at once and in opposite directions — animating only the
/// arriving page reads as a card dropped on top, not as a strip being panned.
///
/// This lives on the *router's* pages, not in the shell around them. The shell
/// gets handed the same GlobalKey'd child on every build, so holding an
/// outgoing page there for the length of an animation puts one key in the tree
/// twice; the framework then gives the element to the newcomer and the page
/// sliding out renders empty. Inside the Navigator, both pages are real routes
/// and animating them is what it is built for.
class TabSlide {
  const TabSlide._();

  /// Same motion the nav bar's highlight glides with, so the bar and the page
  /// are one movement instead of two things happening at once.
  static const duration = AppNavBar.motionDuration;
  static const curve = AppNavBar.motionCurve;

  /// The tab being shown, and which way we got there: +1 = the new tab sits to
  /// the right of the old one.
  static int _index = 0;
  static double _dir = 1;

  /// Told by the shell before the Navigator builds its pages.
  static void to(int index, {required int from}) {
    _dir = index > from ? 1 : -1;
    _index = index;
  }

  /// The transition for the tab at [myIndex].
  ///
  /// Whichever page is the current tab is arriving (its animation runs 0 → 1);
  /// any other page with a live transition is on its way out, and its animation
  /// runs in reverse (1 → 0). That is why both can share one
  /// "begin → Offset.zero" tween and still travel opposite ways: the arriving
  /// page starts one screen over on the side it comes from, the leaving one
  /// ends up one screen over on the other side.
  static Widget build(int myIndex, Animation<double> animation, Widget child) {
    final arriving = myIndex == _index;
    final begin = Offset(arriving ? _dir : -_dir, 0);
    return SlideTransition(
      position: Tween<Offset>(begin: begin, end: Offset.zero).animate(
        CurvedAnimation(parent: animation, curve: curve, reverseCurve: curve),
      ),
      child: child,
    );
  }
}
