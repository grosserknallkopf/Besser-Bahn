import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/reminder_provider.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'core/constants.dart';

class BessereBahnApp extends ConsumerWidget {
  const BessereBahnApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the trip-reminder scheduler alive: it watches saved trips + settings
    // and (re)schedules offline OS reminders whenever they change.
    ref.watch(reminderSchedulerProvider);
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}
