import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

extension DateTimeFormatting on DateTime {
  String get hhmm => DateFormat('HH:mm').format(this);

  String get dayMonthYear => DateFormat('dd.MM.yyyy').format(this);

  String get isoDate => DateFormat('yyyy-MM-dd').format(this);

  String get fullDateTime => DateFormat('dd.MM.yyyy HH:mm').format(this);
}

extension DelayFormatting on int {
  /// Format delay in seconds to human-readable string
  String get delayString {
    final minutes = this ~/ 60;
    if (minutes == 0) return '';
    return '+$minutes';
  }

  Color get delayColor {
    final minutes = this ~/ 60;
    if (minutes <= 0) return const Color(0xFF27AE60);
    if (minutes <= 5) return const Color(0xFFF39C12);
    return const Color(0xFFE74C3C);
  }
}

extension NullableDelayFormatting on int? {
  String get delayString => this?.delayString ?? '';
  Color get delayColor => this?.delayColor ?? const Color(0xFF27AE60);
}

extension StringCapitalize on String {
  String get capitalize =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
