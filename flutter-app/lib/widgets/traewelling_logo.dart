import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The official Träwelling logo (their `images/icons/logo.svg`), bundled as an
/// asset. Use this instead of a generic Material icon wherever we represent the
/// Träwelling brand (settings tile, connect prompt).
class TraewellingLogo extends StatelessWidget {
  final double size;

  const TraewellingLogo({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/traewelling/traewelling_logo.svg',
      width: size,
      height: size,
      // The mark fails to a transparent box rather than throwing if the asset
      // is ever missing.
      placeholderBuilder: (_) => SizedBox(width: size, height: size),
    );
  }
}
