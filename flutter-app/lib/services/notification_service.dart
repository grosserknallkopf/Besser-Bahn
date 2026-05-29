import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/app_log.dart';

/// Thin wrapper around flutter_local_notifications for the few one-shot OS
/// notifications the app fires (e.g. "Split-Ticket-Analyse fertig"). Android +
/// iOS only; every call is best-effort and never throws into app code.
class NotificationService {
  NotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Android notification channel for finished background analyses.
  static const _channel = AndroidNotificationChannel(
    'split_ticket',
    'Split-Ticket',
    description: 'Ergebnis der Split-Ticket-Analyse',
    importance: Importance.high,
  );

  /// Initialise the plugin and create the Android channel. Call once at startup.
  /// Permission is requested lazily on first [showSplitResult].
  static Future<void> init() async {
    if (_ready) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      // iOS perms are requested on demand (below), not at init.
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(const InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
      ));
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
      _ready = true;
    } catch (e) {
      AppLog.log('notification init failed ($e)', tag: 'notify');
    }
  }

  /// Ask the OS for permission to post notifications (Android 13+ / iOS). Safe
  /// to call repeatedly — the OS only prompts the first time.
  static Future<void> _ensurePermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        await android.requestNotificationsPermission();
        return;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      AppLog.log('notification permission request failed ($e)', tag: 'notify');
    }
  }

  /// Fire the "analysis finished" notification. [title] is the route
  /// ("Kiel Hbf → Berlin Hbf"), [body] the result line.
  static Future<void> showSplitResult({
    required String title,
    required String body,
  }) async {
    if (!_ready) await init();
    await _ensurePermission();
    try {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'split_ticket',
          'Split-Ticket',
          channelDescription: 'Ergebnis der Split-Ticket-Analyse',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      );
      // Stable id → a fresh result replaces the previous notification rather
      // than stacking.
      await _plugin.show(1001, title, body, details);
    } catch (e) {
      AppLog.log('notification show failed ($e)', tag: 'notify');
    }
  }
}
