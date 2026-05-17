import 'package:flutter/material.dart';

class AppTheme {
  // ── 다크 네이비/골드 테마 팔레트 ──
  static const Color navyDeep    = Color(0xFF0A0E1A);
  static const Color navyDark    = Color(0xFF0D1321);
  static const Color navyMid     = Color(0xFF141B2D);
  static const Color navyCard    = Color(0xFF1A2340);
  static const Color navyBorder  = Color(0xFF243050);

  static const Color goldPrimary  = Color(0xFFFFD700);
  static const Color goldLight    = Color(0xFFFFE55C);
  static const Color goldDark     = Color(0xFFB8960C);
  static const Color goldAccent   = Color(0xFFF0C040);

  static const Color blueAccent  = Color(0xFF2979FF);
  static const Color blueLight   = Color(0xFF448AFF);
  static const Color tealAccent  = Color(0xFF00BCD4);

  static const Color textWhite   = Color(0xFFFFFFFF);
  static const Color textLight   = Color(0xFFE0E6FF);
  static const Color textMuted   = Color(0xFF7A8AB5);
  static const Color textDisable = Color(0xFF3A4560);

  static const Color greenWin    = Color(0xFF00E676);
  static const Color redAlert    = Color(0xFFFF1744);
  static const Color orangeWarn  = Color(0xFFFF6D00);

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: navyDeep,
      colorScheme: const ColorScheme.dark(
        primary: goldPrimary,
        secondary: blueAccent,
        surface: navyCard,
        onPrimary: navyDeep,
        onSecondary: textWhite,
        onSurface: textWhite,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: navyDark,
        foregroundColor: textWhite,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: navyCard,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: navyBorder, width: 1),
        ),
      ),
      fontFamily: 'Pretendard',
    );
  }

  // 그라데이션
  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFFFD700), Color(0xFFF0C040), Color(0xFFB8960C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient navyGradient = LinearGradient(
    colors: [Color(0xFF0D1321), Color(0xFF141B2D)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF1A2340), Color(0xFF141B2D)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient venueGradient(Color accent) => LinearGradient(
    colors: [accent.withValues(alpha: 0.3), navyCard],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
