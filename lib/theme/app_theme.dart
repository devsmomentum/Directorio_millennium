import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color background = Colors.black;
  static const Color surface = Color(0xFF111111);
  static const Color surfaceLight = Color(0xFF1A1A1A);

  static const Color primary = Color.fromARGB(255, 7, 7, 221);
  static const Color secondary = Color.fromARGB(255, 116, 189, 38);

  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Colors.white70;
  static const Color textSecondaryMuted = Colors.white54;
  static const Color textHint = Color(0x4DFFFFFF);
  static const Color textTertiary = Color(0x61FFFFFF);

  static const Color divider = Colors.white10;

  static const Color warning = Color(0xFFFFC107);
  static const Color success = Colors.green;
  static const Color error = Colors.red;

  static const Color transparent = Colors.transparent;

  static const Color overlaySoft = Color(0x66000000);
  static const Color overlayStrong = Color(0xD9000000);
  static const Color chipBackground = Color(0x61000000);
  static const Color badgeBackground = Color(0x8A000000);
  static const Color qrBackground = Colors.white;
  static const Color shadow = Color(0x4D000000);
  static const Color subtleBorder = Color(0x0DFFFFFF);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [primary, secondary],
  );
}

class AppTextStyles {
  AppTextStyles._();

  static const TextStyle h1 = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 32,
    fontWeight: FontWeight.w900,
  );

  static const TextStyle buttonText = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 18,
    fontWeight: FontWeight.w900,
    letterSpacing: 1,
  );

  static const TextStyle body = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 14,
  );

  static const TextStyle caption = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 12,
  );

  static const TextStyle badge = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 10,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle footer = TextStyle(
    color: AppColors.textTertiary,
    fontSize: 9,
  );

  static const TextStyle navLabel = TextStyle(
    color: AppColors.textSecondaryMuted,
    fontSize: 12,
  );

  static const TextStyle dialogTitle = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 18,
    fontWeight: FontWeight.bold,
  );
}
