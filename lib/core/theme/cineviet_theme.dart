import 'package:flutter/material.dart';
import 'cineviet_colors.dart';
import 'cineviet_dimensions.dart';

class CineVietTheme {
  CineVietTheme._();

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: CineVietColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: CineVietColors.accent,
        secondary: CineVietColors.accentHover,
        surface: CineVietColors.card,
        error: CineVietColors.red,
        onPrimary: Colors.white,
        onSurface: CineVietColors.text,
      ),
      textTheme: base.textTheme.apply(
          bodyColor: CineVietColors.text,
        displayColor: CineVietColors.text,
      ),
      cardTheme: CardThemeData(
        color: CineVietColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CineVietRadius.lg),
          side: const BorderSide(color: CineVietColors.border),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: CineVietColors.card,
        selectedItemColor: CineVietColors.accent,
        unselectedItemColor: CineVietColors.muted,
        type: BottomNavigationBarType.fixed,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: CineVietColors.card,
        selectedIconTheme: IconThemeData(color: CineVietColors.accent),
        unselectedIconTheme: IconThemeData(color: CineVietColors.muted),
        selectedLabelTextStyle: TextStyle(color: CineVietColors.accent, fontWeight: FontWeight.w700),
        unselectedLabelTextStyle: TextStyle(color: CineVietColors.textSoft),
      ),
    );
  }
}
