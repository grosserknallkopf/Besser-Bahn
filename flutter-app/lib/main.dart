import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/tile_cache.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Best-effort: persistent on-disk tile cache. Failure is non-fatal.
  await TileCache.init();
  // Best-effort: local notifications (Split-Ticket-Ergebnis). Non-fatal.
  await NotificationService.init();
  runApp(
    const ProviderScope(
      child: BessereBahnApp(),
    ),
  );
}
