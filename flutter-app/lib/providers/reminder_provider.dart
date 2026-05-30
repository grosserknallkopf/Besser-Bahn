import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/trip_reminder_scheduler.dart';
import 'library_provider.dart';
import 'settings_provider.dart';

/// Keeps the OS-scheduled trip reminders in sync with the user's saved trips
/// and notification settings. Watch it once high in the tree (see [app.dart])
/// to keep it alive; it re-runs [TripReminderScheduler.sync] whenever the saved
/// journeys or the reminder settings change — and once on startup.
final reminderSchedulerProvider = Provider<void>((ref) {
  final journeys = ref.watch(libraryProvider).upcomingJourneys;
  final settings = ref.watch(settingsProvider);
  // Fire-and-forget: reconciles the OS pending list, safe to call on every
  // rebuild. The watched lists settle quickly after the async _load().
  TripReminderScheduler.sync(
    journeys,
    enabled: settings.remindersEnabled,
    leadMinutes: settings.reminderLeadMinutes,
    transferAlerts: settings.transferAlerts,
  );
});
