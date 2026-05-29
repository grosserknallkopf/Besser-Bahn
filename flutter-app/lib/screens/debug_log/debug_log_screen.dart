import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/app_log.dart';

/// Live debug log — shows what the API layer is doing (vendo / bahn.de / HAFAS),
/// so issues like "search returns 500" can be diagnosed on-device.
class DebugLogScreen extends StatelessWidget {
  const DebugLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug-Log'),
        actions: [
          IconButton(
            tooltip: 'Kopieren',
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(
                  ClipboardData(text: AppLog.messages.value.join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Log kopiert')),
              );
            },
          ),
          IconButton(
            tooltip: 'Leeren',
            icon: const Icon(Icons.delete_outline),
            onPressed: AppLog.clear,
          ),
        ],
      ),
      body: ValueListenableBuilder<List<String>>(
        valueListenable: AppLog.messages,
        builder: (context, lines, _) {
          if (lines.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Noch keine Log-Einträge.\n'
                  'Führe eine Suche oder Abfrage aus.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: lines.length,
            itemBuilder: (context, i) {
              final line = lines[lines.length - 1 - i]; // newest first
              final isError = line.contains('FAILED') ||
                  line.contains('failed') ||
                  line.contains('HTTP 5') ||
                  line.contains('HTTP 4');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: SelectableText(
                  line,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: isError ? Colors.redAccent : null,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
