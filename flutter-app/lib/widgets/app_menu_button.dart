import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Overflow menu for the secondary destinations that no longer live in the
/// bottom navigation bar (Split-Ticket, Einstellungen, Debug-Log). Drop it into
/// the `actions:` of any core screen's AppBar.
class AppMenuButton extends StatelessWidget {
  const AppMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'Mehr',
      onSelected: (route) => context.push(route),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: '/split',
          child: ListTile(
            leading: Icon(Icons.call_split),
            title: Text('Split-Ticket'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: '/settings',
          child: ListTile(
            leading: Icon(Icons.settings),
            title: Text('Einstellungen'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: '/debug-log',
          child: ListTile(
            leading: Icon(Icons.bug_report_outlined),
            title: Text('Debug-Log'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
