import '../core/app_log.dart';
import '../core/extensions.dart';
import '../models/journey.dart';
import '../models/library_models.dart';
import 'notification_service.dart';

/// Turns the user's saved upcoming trips into OS-scheduled local reminders —
/// the offline, infinitely-scaling half of the notification feature. Nothing
/// here touches the network: every time is read straight from the saved
/// timetable, so 100k users scheduling their own trips put zero load on DB and
/// no server in the loop. Live delay-aware alerts are a separate, foreground
/// concern (see the live-tracking controller).
///
/// For each trip we plan up to three kinds of pings:
///  - **Bereit machen** — [leadMinutes] before departure ("In 30 Min fährt …").
///  - **Boarding** — 5 min before departure, with the platform.
///  - **Umstieg** — 5 min before each connecting train leaves, with platform
///    and the real transfer gap.
///
/// [sync] is idempotent: it reconciles the OS's pending list, so calling it on
/// every library/settings change (or app start) converges without piling up.
class TripReminderScheduler {
  TripReminderScheduler._();

  /// iOS caps an app at 64 pending notifications; stay well under across all
  /// trips so the soonest ones never get dropped.
  static const int _maxReminders = 56;

  static Future<void> sync(
    List<SavedJourney> upcoming, {
    required bool enabled,
    required int leadMinutes,
    required bool transferAlerts,
  }) async {
    // Toggle off → clear everything we scheduled and stop.
    if (!enabled) {
      await NotificationService.cancelReminders();
      return;
    }

    final now = DateTime.now();
    final reminders = <_Reminder>[];
    for (final saved in upcoming) {
      reminders.addAll(_remindersFor(saved.journey, leadMinutes, transferAlerts));
    }

    // Only future pings, soonest first, capped.
    reminders
      ..removeWhere((r) => !r.when.isAfter(now))
      ..sort((a, b) => a.when.compareTo(b.when));
    final planned = reminders.take(_maxReminders).toList();

    await NotificationService.cancelReminders();
    var id = NotificationService.reminderIdBase;
    for (final r in planned) {
      await NotificationService.scheduleReminder(
        id: id++,
        when: r.when,
        title: r.title,
        body: r.body,
      );
    }
    AppLog.log('reminders synced (${planned.length} scheduled)', tag: 'notify');
  }

  static List<_Reminder> _remindersFor(
      Journey journey, int leadMinutes, bool transferAlerts) {
    final out = <_Reminder>[];
    final transit = journey.legs.where((l) => !l.isWalking).toList();
    if (transit.isEmpty) return out;

    final first = transit.first;
    final dep = first.plannedDeparture ?? first.departure;
    if (dep == null) return out;
    final line = first.line?.displayName ?? 'Zug';
    final origin = first.origin.name;
    final plat = first.departurePlatform ?? first.plannedDeparturePlatform;

    // Bereit machen — lead minutes before departure.
    out.add(_Reminder(
      when: dep.subtract(Duration(minutes: leadMinutes)),
      title: 'In $leadMinutes Min: $line',
      body: 'ab $origin um ${dep.hhmm}'
          '${plat != null ? ' · Gleis $plat' : ''} — mach dich bereit.',
    ));

    // Boarding — 5 min before. Skipped if the lead is already ≤5 (would dupe).
    if (leadMinutes > 5) {
      out.add(_Reminder(
        when: dep.subtract(const Duration(minutes: 5)),
        title: 'Gleich Abfahrt: $line',
        body: '${dep.hhmm} ab $origin'
            '${plat != null ? ' · Gleis $plat' : ' — zum Gleis'}.',
      ));
    }

    // Umstiege — one ping shortly before each connecting train departs.
    if (transferAlerts) {
      for (var i = 1; i < transit.length; i++) {
        final next = transit[i];
        final nextDep = next.plannedDeparture ?? next.departure;
        if (nextDep == null) continue;
        final station = next.origin.name;
        final nextLine = next.line?.displayName ?? 'Anschluss';
        final nextPlat =
            next.departurePlatform ?? next.plannedDeparturePlatform;
        final prevArr = transit[i - 1].plannedArrival ?? transit[i - 1].arrival;
        final gap = prevArr != null
            ? nextDep.difference(prevArr).inMinutes
            : null;
        out.add(_Reminder(
          when: nextDep.subtract(const Duration(minutes: 5)),
          title: 'Umstieg in $station',
          body: '$nextLine um ${nextDep.hhmm}'
              '${nextPlat != null ? ' · Gleis $nextPlat' : ''}'
              '${gap != null ? ' · Übergang $gap Min' : ''}.',
        ));
      }
    }
    return out;
  }
}

class _Reminder {
  final DateTime when;
  final String title;
  final String body;
  const _Reminder({required this.when, required this.title, required this.body});
}
