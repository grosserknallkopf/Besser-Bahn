import 'package:flutter/material.dart';

import 'app_nav_bar.dart';
import 'glass_panel.dart';

/// One segment of a [GlassSwitcher].
@immutable
class GlassSwitcherItem {
  const GlassSwitcherItem({
    required this.icon,
    required this.label,
    this.activeIcon,
  });

  /// Icon shown while the segment is not selected.
  final IconData icon;

  /// Icon shown while it is. Falls back to [icon].
  final IconData? activeIcon;

  /// The segment's name. Only rendered while the segment is selected — see
  /// [GlassSwitcher] for why — but always announced to a screen reader.
  final String label;
}

/// A slim floating pill that switches between a screen's *inner* views: the
/// top-of-screen counterpart to [AppNavBar]'s bottom pill, and deliberately its
/// twin.
///
/// Same glass ([GlassPanel] — the sanctioned bridge for everything that is not
/// the nav bar), same pill shape, same gliding [ColorScheme.primaryContainer]
/// highlight, same motion ([AppNavBar.motionDuration] / [AppNavBar.motionCurve]).
/// The app has one way of saying "you are here"; this is it, moved to the top.
///
/// **Only the selected segment is labelled.** Three icons with three labels is
/// a [TabBar] again, and a [TabBar] with icon *and* text is 72 px — the block
/// this replaces. The label the rider needs is the one under their thumb: the
/// others are named by their icon and by the highlight that is not on them. A
/// screen reader still gets every label (see [GlassSwitcherItem.label]).
///
/// It **floats**: put it in a [Stack] over the content and give the content
/// [insetOf] as top padding, the way a tab pads its scrollables by
/// [AppNavBar.insetOf].
class GlassSwitcher extends StatelessWidget {
  const GlassSwitcher({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
    this.trailing,
  });

  /// The segments, left to right.
  final List<GlassSwitcherItem> items;

  /// The selected segment.
  final int index;

  /// Called with the tapped segment's index.
  final ValueChanged<int> onChanged;

  /// One action pinned right of the pill, in a glass button of its own — the
  /// slot the AppBar's `actions:` used to be. Kept *outside* the pill so the
  /// highlight's slots stay equal-width and it can glide across them by
  /// fraction alone.
  final Widget? trailing;

  /// The pill's height. Sized for a 44 px tap target rather than the nav bar's
  /// 64: that one stacks a label under its icon, this one sets the label beside
  /// it, so the height buys nothing.
  static const _height = 44.0;

  /// The pill's margin — [_padBottom] is the larger of the two so the shadow
  /// has somewhere to fall and the content below does not appear glued on.
  static const _padTop = 6.0;
  static const _padBottom = 8.0;
  static const _sideMargin = 12.0;

  /// Gap between the pill and [trailing].
  static const _gap = 8.0;

  /// How much of the top of the screen the floating switcher covers.
  ///
  /// The pill hovers *over* the content, so whatever a screen puts at its top
  /// has to start below this or it sits under the glass forever. Includes the
  /// status bar: a screen with no AppBar keeps that inset in its body, and the
  /// switcher wears it via its own [SafeArea].
  ///
  /// A **constant**, not a measurement, and for the same reason
  /// [AppNavBar.insetOf] is: a padding that could be moved by what it pads is a
  /// layout driving its own input. Nothing here depends on the content — the
  /// pill is one fixed-height row whatever the selected segment is — so there
  /// is no height to measure that this cannot state outright, and stating it
  /// costs no frame of lag. `test/glass_switcher_test.dart` pins the number
  /// against the widget's real laid-out footprint, so a drift fails there
  /// rather than silently mis-padding every view on the screen.
  static double insetOf(BuildContext context) =>
      MediaQuery.paddingOf(context).top + _padTop + _height + _padBottom;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final n = items.length;
    // Slot-centre alignment for the sliding highlight: -1 (first) … 1 (last).
    // The nav bar's own arithmetic (`chuk_nav_bar.dart`), and it only works
    // because every slot is the same width — which is why [trailing] is not one.
    final alignX = n <= 1 ? 0.0 : -1 + 2 * index.clamp(0, n - 1) / (n - 1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _sideMargin,
        _padTop,
        _sideMargin,
        _padBottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: GlassPanel(
              radius: GlassPanel.pillRadius,
              child: SizedBox(
                height: _height,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedAlign(
                        alignment: Alignment(alignX, 0),
                        duration: AppNavBar.motionDuration,
                        curve: AppNavBar.motionCurve,
                        child: FractionallySizedBox(
                          widthFactor: 1 / n,
                          heightFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(
                                GlassPanel.pillRadius,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          for (var i = 0; i < n; i++)
                            Expanded(child: _segment(context, i)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: _gap),
            GlassPanel(
              radius: GlassPanel.pillRadius,
              child: SizedBox.square(
                dimension: _height,
                child: Center(child: trailing),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, int i) {
    final theme = Theme.of(context);
    final item = items[i];
    final active = i == index;
    final color = active
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: active,
        // While the label is on screen the Text supplies it; naming it here too
        // would make a reader say it twice.
        label: active ? null : item.label,
        child: GestureDetector(
          // Opaque: the whole slot is the target, not just the glyph in it.
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(i),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: AppNavBar.motionDuration,
                child: Icon(
                  active ? (item.activeIcon ?? item.icon) : item.icon,
                  key: ValueKey(active),
                  size: 20,
                  color: color,
                ),
              ),
              // Flexible, so a long label in a narrow slot fades out instead of
              // overflowing; AnimatedSize, so it grows and shrinks with the
              // highlight rather than popping in after it.
              Flexible(
                child: AnimatedSize(
                  duration: AppNavBar.motionDuration,
                  curve: AppNavBar.motionCurve,
                  child: active
                      ? Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            item.label,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.fade,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
