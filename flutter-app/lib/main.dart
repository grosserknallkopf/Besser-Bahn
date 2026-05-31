import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/app_log.dart';
import 'core/tile_cache.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Collapse the endless identical map-tile error dumps into one counted line
  // so the console/debug-log stays readable (must run before the first map).
  AppLog.installErrorCollapsing();
  // Best-effort: persistent on-disk tile cache. Failure is non-fatal.
  await TileCache.init();
  // Warm the vector basemap style in the background NOW, so the first map the
  // rider opens already has it ready (the ~5 s style fetch was the main "takes
  // a bit to open" — paid on first map, not after). Fire-and-forget.
  TileCache.warmStyle();
  // Best-effort: local notifications (Split-Ticket-Ergebnis). Non-fatal.
  await NotificationService.init();
  runApp(
    const ProviderScope(
      child: BessereBahnApp(),
    ),
  );
}
