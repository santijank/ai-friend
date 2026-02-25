/// theme_service.dart — จัดการธีมสีแอป
import 'package:flutter/material.dart';
import 'local_storage.dart';

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._();
  factory ThemeService() => _instance;
  ThemeService._();

  static const _themeColors = {
    'blue': Color(0xFF6C9BCF),
    'purple': Color(0xFF9B72CF),
    'green': Color(0xFF4CAF50),
    'pink': Color(0xFFE91E63),
    'orange': Color(0xFFFF9800),
    'teal': Color(0xFF009688),
  };

  Color get primaryColor =>
      _themeColors[LocalStorage.themeColor] ?? const Color(0xFF6C9BCF);

  bool get isDarkMode => LocalStorage.darkMode;

  ThemeData get theme {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: isDarkMode ? Brightness.dark : Brightness.light,
      ),
      useMaterial3: true,
      fontFamily: 'Sarabun',
    );
  }

  Future<void> setColor(String colorName) async {
    await LocalStorage.saveSetting('themeColor', colorName);
    notifyListeners();
  }

  Future<void> toggleDarkMode() async {
    await LocalStorage.saveSetting('darkMode', !isDarkMode);
    notifyListeners();
  }

  static Map<String, Color> get availableColors => _themeColors;
}
