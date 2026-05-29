import 'package:flutter/material.dart';

/// A slim, right-aligned strip of icon actions shown at the top of a screen's
/// body when that screen is embedded inside the combined "Bahnhof" tab screen
/// (which owns the real AppBar + tab bar). Mirrors the actions a screen would
/// otherwise place in its own AppBar.
class EmbeddedActionBar extends StatelessWidget {
  final List<Widget> actions;

  const EmbeddedActionBar({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ...actions,
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}
