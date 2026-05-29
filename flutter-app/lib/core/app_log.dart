import 'package:flutter/foundation.dart';

/// Lightweight global debug log.
///
/// Both prints to the console (visible in `flutter run` / logcat) and keeps a
/// ring buffer that the in-app Debug-Log screen renders live. No Riverpod ref
/// needed, so services can log too.
class AppLog {
  AppLog._();

  static const _max = 400;

  /// Live buffer the debug screen listens to.
  static final ValueNotifier<List<String>> messages =
      ValueNotifier<List<String>>(const []);

  static void log(String message, {String tag = ''}) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final ts = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    final line = tag.isEmpty ? '$ts  $message' : '$ts  [$tag] $message';
    debugPrint(line);
    final next = [...messages.value, line];
    messages.value =
        next.length > _max ? next.sublist(next.length - _max) : next;
  }

  static void clear() => messages.value = const [];
}
