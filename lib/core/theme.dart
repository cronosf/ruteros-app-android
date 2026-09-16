import 'package:flutter/material.dart';

/// Paleta de marca de Ruteros (moodboard: web/public/assets/tema_web_app.png).
/// Dark mode es el unico tema soportado por diseno (mejor lectura del mapa,
/// ahorra bateria en pantallas AMOLED).
class AppColors {
  static const verde = Color(0xFF00D26A);
  static const azul = Color(0xFF3B82F6);
  static const fondoOscuro = Color(0xFF0B1220);
  static const grisUI = Color(0xFF64748B);
  static const textoClaro = Color(0xFFF1F5F9);
}

final ThemeData ruterosDarkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: AppColors.fondoOscuro,
  colorScheme: const ColorScheme.dark(
    primary: AppColors.verde,
    secondary: AppColors.azul,
    surface: AppColors.fondoOscuro,
    onPrimary: AppColors.fondoOscuro,
    onSecondary: Colors.white,
    onSurface: AppColors.textoClaro,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.fondoOscuro,
    foregroundColor: AppColors.textoClaro,
    elevation: 0,
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: Color(0xFF111C30),
    selectedItemColor: AppColors.verde,
    unselectedItemColor: AppColors.grisUI,
    type: BottomNavigationBarType.fixed,
  ),
  cardColor: const Color(0xFF111C30),
  dividerColor: AppColors.grisUI,
  textTheme: const TextTheme(
    bodyLarge: TextStyle(color: AppColors.textoClaro),
    bodyMedium: TextStyle(color: AppColors.textoClaro),
  ).apply(bodyColor: AppColors.textoClaro, displayColor: AppColors.textoClaro),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFF111C30),
    labelStyle: const TextStyle(color: AppColors.grisUI),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.verde,
      foregroundColor: AppColors.fondoOscuro,
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.textoClaro,
      side: const BorderSide(color: AppColors.grisUI),
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: AppColors.azul,
    foregroundColor: Colors.white,
  ),
);
