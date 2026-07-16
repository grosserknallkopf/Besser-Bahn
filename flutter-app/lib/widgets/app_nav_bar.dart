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
  });

  /// The destinations, left to right.
  final List<ChukNavItem> items;

  /// The selected destination.
  final int index;

  /// Called with the tapped destination's index.
  final ValueChanged<int> onChanged;

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
        navStyle: ChukNavStyle(
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
      child: ChukNavBar(items: items, index: index, onChanged: onChanged),
    );
  }
}
