// Vendored from chuk_ui — git@github.com:chukfinley/chuk_ui.git
// Source: lib/src/shape/chuk_glass.dart @ commit 3ae5a1e (v0.4.2).
//
// COPIED, NOT A DEPENDENCY: the IzzyOnDroid reproducible build must not gain a
// new external (Git) dependency — see BUILDING.md. Only the slice the nav bar
// needs is vendored, not the whole package.
//
// Edits here are LOCAL and do NOT flow back to chuk_ui. Re-sync by hand against
// upstream and re-apply the deltas noted below.
//
// Delta vs upstream: the `@experimental` annotation and its `package:meta`
// import are dropped (meta is not a declared dependency of this app). The
// experimental status is unchanged — see the doc comment below: light-mode
// glass is the experimental path, dark is the maintained one.

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// A frosted-glass surface: whatever is behind it is blurred, then a translucent
/// fill, a bright edge highlight and an optional shadow are laid on top, all
/// clipped to [shape].
///
/// The blur only shows against content behind it, so place glass over a gradient
/// or scenic background for the full effect. A low [fill] alpha plus a strong
/// [blurSigma] and the [highlight] edge are what make the glass read clearly.
///
/// **Experimental.** The frosted-glass / light-mode look is still being explored
/// (a real shader-based "liquid glass" treatment is a candidate). The supported,
/// stable path is the **dark** theme; this API may change or be replaced.
class ChukGlass extends StatelessWidget {
  const ChukGlass({
    super.key,
    required this.shape,
    required this.child,
    this.fill = const Color(0x24FFFFFF),
    this.highlight = const Color(0x73FFFFFF),
    this.blurSigma = 30,
    this.shadow,
  });

  /// The clip + border shape (e.g. a `SquircleBorder`).
  final OutlinedBorder shape;

  /// Content laid over the glass.
  final Widget child;

  /// Translucent fill tint over the blur. Keep the alpha low (~0.3–0.45) so the
  /// blurred backdrop stays visible.
  final Color fill;

  /// Bright hairline edge that gives the glass its rim of light.
  final Color highlight;

  /// Gaussian blur radius applied to the backdrop. Higher = frostier.
  final double blurSigma;

  /// Optional drop shadow (drawn unclipped, behind the glass).
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      // Shadow only — drawn outside the clip so it isn't cut away.
      decoration: ShapeDecoration(shape: shape, shadows: shadow),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        // A save layer is required so the backdrop blur is bounded to this
        // shape instead of bleeding to the full screen width.
        clipBehavior: Clip.antiAliasWithSaveLayer,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: DecoratedBox(
            // Translucent fill + a bright edge highlight on top of the blur.
            decoration: ShapeDecoration(
              color: fill,
              shape: shape.copyWith(
                side: BorderSide(color: highlight, width: 1),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
