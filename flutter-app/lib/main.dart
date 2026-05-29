import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/tile_cache.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Best-effort: persistent on-disk tile cache. Failure is non-fatal.
  await TileCache.init();
  runApp(
    const ProviderScope(
      child: BessereBahnApp(),
    ),
  );
}
