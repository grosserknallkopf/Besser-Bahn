import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Deutsche Bahn Brand Colors
  static const dbRed = Color(0xFFEC0016);
  static const dbRedDark = Color(0xFFC50014);

  /// DB "Verkehrsblau" — the blue used for station-map POI markers on
  /// bahnhof.de (lifts, stairs, exits, bus …).
  static const dbBlue = Color(0xFF1455C0);

  // Functional colors
  static const delay = Color(0xFFE74C3C);
  static const onTime = Color(0xFF27AE60);
  static const cancelled = Color(0xFF95A5A6);
  static const warning = Color(0xFFF39C12);

  // Coach sequence
  static const firstClass = Color(0xFFFFD700);
  static const secondClass = Color(0xFF3498DB);
  static const restaurant = Color(0xFFE67E22);
  static const locomotive = Color(0xFF7F8C8D);
  static const closedCoach = Color(0xFFBDC3C7);
}
