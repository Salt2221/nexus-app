import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ════════════════════════════════════════════
// NEXUS Customization Service — полная кастомизация с сохранением
// ════════════════════════════════════════════

class CustomizationService extends ChangeNotifier {
  CustomizationService._();
  static final CustomizationService instance = CustomizationService._();

  // Colors
  Color primaryColor = const Color(0xFF6C63FF);
  Color secondaryColor = const Color(0xFF03DAC6);

  // Background
  String? _backgroundImagePath;
  File? get backgroundImage => _backgroundImagePath != null ? File(_backgroundImagePath!) : null;
  List<Color>? backgroundGradient;
  double backgroundOpacity = 0.8;
  double backgroundBlur = 0;

  // Bubbles
  Color myBubbleColor = const Color(0xFF6C63FF);
  Color theirBubbleColor = Colors.grey;
  List<Color>? myBubbleGradient;
  List<Color>? theirBubbleGradient;
  Color? myBubbleShadow;
  Color? theirBubbleShadow;
  Color? myBubbleBorder;
  Color? theirBubbleBorder;

  // Font
  double messageFontSize = 16;
  String fontFamily = 'system';
  double appBarFontSize = 18;

  // UI
  bool showAvatars = true;
  bool showNames = true;
  bool showTimestamps = true;
  bool compactNav = false;
  String navIconStyle = 'filled';
  bool darkMode = true;
  double cornerRadius = 16;

  // Animation
  String messageAnimation = 'slide';
  String pageTransition = 'default';
  bool reducedMotion = false;

  // Sound
  bool notificationSounds = true;
  bool vibration = true;
  String notificationStyle = 'default';

  // Privacy
  bool appLock = false;
  bool hidePreview = false;

  // Language
  String language = 'ru';

  Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Тема
      darkMode = prefs.getBool('darkMode') ?? true;

      // Цвета
      final primaryInt = prefs.getInt('primaryColor');
      if (primaryInt != null) primaryColor = Color(primaryInt);

      // Чат
      messageFontSize = prefs.getDouble('messageFontSize') ?? 16;
      showAvatars = prefs.getBool('showAvatars') ?? true;
      showNames = prefs.getBool('showNames') ?? true;
      showTimestamps = prefs.getBool('showTimestamps') ?? true;

      // Навигация
      compactNav = prefs.getBool('compactNav') ?? false;
      reducedMotion = prefs.getBool('reducedMotion') ?? false;

      // Звуки
      notificationSounds = prefs.getBool('notificationSounds') ?? true;
      vibration = prefs.getBool('vibration') ?? true;

      // Приватность
      appLock = prefs.getBool('appLock') ?? false;
      hidePreview = prefs.getBool('hidePreview') ?? false;

      // Язык
      language = prefs.getString('language') ?? 'ru';

      // Скругление
      cornerRadius = prefs.getDouble('cornerRadius') ?? 16;
    } catch (_) {
      // defaults
    }
  }

  // ── Setters с сохранением ──

  Future<void> setDarkMode(bool value) async {
    darkMode = value;
    await _save('darkMode', value);
    notifyListeners();
  }

  Future<void> setPrimaryColor(Color value) async {
    primaryColor = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('primaryColor', value.value);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setMessageFontSize(double value) async {
    messageFontSize = value;
    await _save('messageFontSize', value);
    notifyListeners();
  }

  Future<void> setShowAvatars(bool value) async {
    showAvatars = value;
    await _save('showAvatars', value);
    notifyListeners();
  }

  Future<void> setShowNames(bool value) async {
    showNames = value;
    await _save('showNames', value);
    notifyListeners();
  }

  Future<void> setShowTimestamps(bool value) async {
    showTimestamps = value;
    await _save('showTimestamps', value);
    notifyListeners();
  }

  Future<void> setCompactNav(bool value) async {
    compactNav = value;
    await _save('compactNav', value);
    notifyListeners();
  }

  Future<void> setReducedMotion(bool value) async {
    reducedMotion = value;
    await _save('reducedMotion', value);
    notifyListeners();
  }

  Future<void> setNotificationSounds(bool value) async {
    notificationSounds = value;
    await _save('notificationSounds', value);
    notifyListeners();
  }

  Future<void> setVibration(bool value) async {
    vibration = value;
    await _save('vibration', value);
    notifyListeners();
  }

  Future<void> setAppLock(bool value) async {
    appLock = value;
    await _save('appLock', value);
    notifyListeners();
  }

  Future<void> setHidePreview(bool value) async {
    hidePreview = value;
    await _save('hidePreview', value);
    notifyListeners();
  }

  Future<void> setLanguage(String value) async {
    language = value;
    await _save('language', value);
    notifyListeners();
  }

  Future<void> setCornerRadius(double value) async {
    cornerRadius = value;
    await _save('cornerRadius', value);
    notifyListeners();
  }

  Future<void> resetAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}
    darkMode = true;
    primaryColor = const Color(0xFF6C63FF);
    messageFontSize = 16;
    showAvatars = true;
    showNames = true;
    showTimestamps = true;
    compactNav = false;
    reducedMotion = false;
    notificationSounds = true;
    vibration = true;
    appLock = false;
    hidePreview = false;
    language = 'ru';
    cornerRadius = 16;
    notifyListeners();
  }

  Future<void> _save(String key, dynamic value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      }
    } catch (_) {}
  }

  @override
  void dispose() {}
}

// ════════════════════════════════════════════
// CustomizationRoot — InheritedNotifier
// ════════════════════════════════════════════

class CustomizationRoot extends InheritedNotifier<CustomizationService> {
  const CustomizationRoot({
    super.key,
    required CustomizationService service,
    required super.child,
  }) : super(notifier: service);

  static CustomizationService of(BuildContext context) {
    final root = context.dependOnInheritedWidgetOfExactType<CustomizationRoot>();
    return root?.notifier ?? CustomizationService.instance;
  }

  @override
  bool updateShouldNotify(CustomizationRoot oldWidget) => true;
}
