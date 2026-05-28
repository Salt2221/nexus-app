// ════════════════════════════════════════════
// NEXUS Auth Service — Local (токен не нужен)
// ════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NexusAuthService extends ChangeNotifier {
  NexusAuthService._();
  static final NexusAuthService instance = NexusAuthService._();

  String? _userName;
  String? _userId;
  bool _isLoading = false;
  bool _initialized = false;

  String? get userName => _userName;
  String? get userId => _userId;
  bool get isSignedIn => _userName != null && _userName!.isNotEmpty;
  bool get isLoading => _isLoading;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _userName = prefs.getString('auth_user_name');
      _userId = prefs.getString('auth_user_id');
      if (_userId == null) _userId = DateTime.now().millisecondsSinceEpoch.toString();
      _initialized = true;
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> signIn(String name) async {
    if (name.trim().isEmpty) return false;
    _isLoading = true;
    notifyListeners();

    try {
      _userName = name.trim();
      _userId ??= DateTime.now().millisecondsSinceEpoch.toString();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_user_name', _userName!);
      await prefs.setString('auth_user_id', _userId!);

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (_) {
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void signOut() {
    _userName = null;
    notifyListeners();
  }
}
