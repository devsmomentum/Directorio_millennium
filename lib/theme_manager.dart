// lib/theme_manager.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeManager with ChangeNotifier {
  static final ThemeManager _instance = ThemeManager._internal();
  factory ThemeManager() => _instance;
  ThemeManager._internal();

  bool _isNeonTheme = true; // Por defecto neón

  bool get isNeonTheme => _isNeonTheme;

  // --- 🔴 PALETA 1: NEÓN CYBERPUNK (La actual) ---
  static const Color neonPrimary = Color(0xFFFF007A); // Rosa Neón
  static const Color neonSecondary = Color(0xFFFF5900); // Naranja Neón
  static const Color neonAccent = Color(0xFF00FFFF); // Cian Neón
  static const Color neonBackground = Color(0xFF0D0D0D); // Negro Profundo
  static const Color neonCard = Color(0xFF1A1A1A); // Gris Oscuro Card
  static const Color neonText = Colors.white;
  static const Color neonTextDim = Colors.white54;

  // --- 🔵 PALETA 2: CORPORATIVA (Millennium Mall) ---
  // Basada en el logo proporcionado
  static const Color corpPrimary = Color(
    0xFF001F3F,
  ); // Azul Marino Profundo (Logo)
  static const Color corpSecondary = Color(
    0xFFD4AF37,
  ); // Dorado/Arena (Acento Elegante)
  static const Color corpAccent = Color(0xFF003366); // Azul Marino Medio
  static const Color corpBackground = Color(
    0xFFF5F5F7,
  ); // Blanco Humo / Gris Muy Claro
  static const Color corpCard = Colors.white; // Tarjetas Blancas puras
  static const Color corpText = Color(0xFF1A1A1A); // Texto Negro Suave
  static const Color corpTextDim = Colors.black45; // Texto Gris Dim

  // Getters dinámicos que devuelven el color según el tema activo
  Color get primary => _isNeonTheme ? neonPrimary : corpPrimary;
  Color get secondary => _isNeonTheme ? neonSecondary : corpSecondary;
  Color get accent => _isNeonTheme ? neonAccent : corpAccent;
  Color get background => _isNeonTheme ? neonBackground : corpBackground;
  Color get card => _isNeonTheme ? neonCard : corpCard;
  Color get text => _isNeonTheme ? neonText : corpText;
  Color get textDim => _isNeonTheme ? neonTextDim : corpTextDim;

  // Degradado principal (usado en cabeceras y botones)
  LinearGradient get mainGradient => _isNeonTheme
      ? const LinearGradient(
          colors: [neonPrimary, neonSecondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )
      : const LinearGradient(
          colors: [corpPrimary, corpAccent], // Degradado de azules
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );

  // Carga la preferencia guardada al iniciar la app
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isNeonTheme = prefs.getBool('is_neon_theme') ?? true;
    notifyListeners();
  }

  // Cambia el tema y guarda la preferencia
  Future<void> toggleTheme() async {
    _isNeonTheme = !_isNeonTheme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_neon_theme', _isNeonTheme);
    notifyListeners(); // 🚀 ¡Esto avisa a toda la app que se repinte!
  }
}
