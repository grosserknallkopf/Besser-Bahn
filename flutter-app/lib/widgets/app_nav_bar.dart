import 'package:flutter/material.dart';

import '../vendor/chuk_ui/chuk_nav_bar.dart';
import '../vendor/chuk_ui/chuk_nav_style.dart';
import '../vendor/chuk_ui/chuk_nav_theme.dart';

/// The app's bottom navigation: the floating glass pill vendored from chuk_ui
/// (`lib/vendor/chuk_ui/`), wired into *this* app's theme.
///
/// The bar itself is deliberately Material-free and resolves its look from
/// chuk_ui tokens, which we did not vendor — Besser-Bahn already has a palette.
/// This widget is that bridge: it maps the Material [ColorScheme] (which
/// `AppTheme` seeds from `AppColors.dbRed`) onto a [ChukNavStyle], so every
/// colour still comes from the single source in `lib/theme/`. No colour is
/// defined twice.
class AppNavBar extends StatelessWidget {
  const AppNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
    this.collapsed = false,
  });

  /// The destinations, left to right.
  final List<ChukNavItem> items;

  /// The selected destination.
  final int index;

  /// Called with the tapped destination's index.
  final ValueChanged<int> onChanged;

  /// Whether the bar is shrunk to icons only — the shell sets this while the
  /// user scrolls down through a tab's content, so reading gets the screen and
  /// the labels come back on the way up. The tabs stay untouched by it: only
  /// the pill inside [insetOf]'s reserved footprint moves (see there).
  final bool collapsed;

  /// Motion of everything the bar animates: the gliding highlight, the icon
  /// swap, and the collapse.
  ///
  /// The shell slides its tabs on exactly these values (`HomeScreen`'s
  /// `slideDuration` / `slideCurve` are defined as these) — the bar and the
  /// page are one movement, and two curves would read as two separate things
  /// happening at once. Overrides the vendored default (220 ms).
  static const motionDuration = Duration(milliseconds: 260);
  static const motionCurve = Curves.easeOutCubic;

  /// The pill's height with labels, and shrunk to icons only.
  ///
  /// Passed to the vendored bar explicitly rather than left to its defaults,
  /// because [insetOf]'s reserved footprint is measured off [_height] and a
  /// silent default change there would move the tabs' padding.
  static const _height = 64.0;
  static const _collapsedHeight = 52.0;

  /// The vendored bar's own bottom margin (`chuk_nav_bar.dart`'s outer
  /// `Padding`, which is not exposed as a style token). Mirrored here to
  /// reserve the footprint; `test/app_nav_bar_test.dart` pins the resulting
  /// total, so a drift in the vendored value fails there rather than silently
  /// mis-padding every list in the app.
  static const _barMargin = 6.0;

  /// Opacity of the bar's chrome tint over the blurred backdrop — chuk_ui's
  /// `ChukColors.surfaceOpacity` (0.58 dark / 0.30 light). Low enough that the
  /// content scrolling underneath stays visible, high enough that labels read.
  static const _tintOpacityDark = 0.58;
  static const _tintOpacityLight = 0.30;

  /// Drop-shadow opacity that lifts the floating bar — chuk_ui's nav shadow
  /// (0x57000000 dark / 0x1A000000 light), expressed via [ColorScheme.shadow].
  static const _shadowOpacityDark = 0.34;
  static const _shadowOpacityLight = 0.10;

  /// How much of the bottom of the screen the floating bar covers.
  ///
  /// The bar hovers *over* the content (`Scaffold.extendBody`), so anything
  /// bottom-anchored inside a shell tab — the last row of a list, a map
  /// overlay — has to add this or it sits under the glass forever. Flutter
  /// reports the bar's measured height (its own [SafeArea] included) as the
  /// body's bottom padding, so this is exactly the bar's footprint. Outside the
  /// shell there is no bar and this is the plain system inset — still the right
  /// number to pad by.
  ///
  /// **This number does not move when the bar collapses**, and that is load
  /// bearing. Every tab pads its scrollables by it, so a footprint that shrank
  /// mid-scroll would shorten the content, which moves `maxScrollExtent`, which
  /// changes what the scroll position reports, which decides whether the bar is
  /// collapsed — a layout that drives its own input. At the margin (a list
  /// barely longer than the viewport) that settles into a twitch: collapse
  /// frees 12 px, the list no longer overflows, so it must expand again.
  /// [build] therefore reserves the *expanded* footprint permanently and lets
  /// only the pill shrink inside it, bottom-aligned. The pill's bottom edge
  /// stays exactly where it was, the tabs' padding is a constant, and the loop
  /// has no way to close. The cost is ~12 px of dead space under a collapsed
  /// pill — invisible, since the glass floats over the content anyway.
  static double insetOf(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;

    return ChukNavTheme(
      data: ChukNavThemeData(
        isLight: isLight,
        labelStyle: theme.textTheme.labelSmall ?? const TextStyle(),
        motion: const ChukNavMotion(
          medium: motionDuration,
          standard: motionCurve,
        ),
        navStyle: ChukNavStyle(
          height: _height,
          collapsedHeight: _collapsedHeight,
          // Translucent chrome over the blur — the scenic content behind the
          // bar genuinely shows through.
          trackColor: colors.surfaceContainerHigh.withValues(
            alpha: isLight ? _tintOpacityLight : _tintOpacityDark,
          ),
          // The gliding highlight keeps the DB-red identity of the Material
          // indicator it replaces (`primaryContainer`), so the active tab is
          // branded, not just tinted glass.
          highlightColor: colors.primaryContainer,
          activeColor: colors.onPrimaryContainer,
          inactiveColor: colors.onSurfaceVariant,
          shadow: [
            BoxShadow(
              color: colors.shadow.withValues(
                alpha: isLight ? _shadowOpacityLight : _shadowOpacityDark,
              ),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
      ),
      // Reserve the expanded footprint whatever the pill is doing — this box is
      // what the Scaffold measures and hands the body as its bottom padding
      // (AppNavBar.insetOf), and it must not move while the user scrolls. Align
      // is what makes the shrink visible: it loosens the constraints again (a
      // bare SizedBox would force its tight height straight through the glass
      // and nothing would collapse) and pins the pill to the bottom, so it
      // shrinks upward from a fixed edge instead of drifting.
      child: SizedBox(
        height: _height + _barMargin + MediaQuery.paddingOf(context).bottom,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ChukNavBar(
            items: items,
            index: index,
            onChanged: onChanged,
            collapsed: collapsed,
          ),
        ),
      ),
    );
  }
}
