// ════════════════════════════════════════════
// NEXUS Auth Service — Google Sign-In (API v7)
// ════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class NexusAuthService extends ChangeNotifier {
  NexusAuthService._();
  static final NexusAuthService instance = NexusAuthService._();

  GoogleSignInAccount? _currentUser;
  bool _isLoading = false;
  String? _error;
  bool _initialized = false;

  GoogleSignInAccount? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Инициализация — вызывается один раз при старте
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final signIn = GoogleSignIn.instance;
      await signIn.initialize();
      signIn.authenticationEvents
          .listen(_onAuthEvent)
          .onError(_onAuthError);
      _initialized = true;
    } catch (e) {
      debugPrint('GoogleSignIn init error: $e');
    }
  }

  void _onAuthEvent(GoogleSignInAuthenticationEvent event) {
    final user = switch (event) {
      GoogleSignInAuthenticationEventSignIn() => event.user,
      GoogleSignInAuthenticationEventSignOut() => null,
      _ => null,
    };
    _currentUser = user;
    _isLoading = false;
    notifyListeners();
  }

  void _onAuthError(Object e) {
    _currentUser = null;
    _isLoading = false;
    _error = 'Auth error: $e';
    notifyListeners();
  }

  /// Тихий вход — пытается восстановить сессию
  Future<void> trySilentSignIn() async {
    if (!_initialized) await initialize();
    _isLoading = true;
    notifyListeners();

    try {
      await GoogleSignIn.instance.attemptLightweightAuthentication();
    } catch (_) {
      // Не страшно — пользователь зайдёт вручную
    }
  }

  /// Явная авторизация через Google
  Future<bool> signInWithGoogle() async {
    if (!_initialized) await initialize();
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await GoogleSignIn.instance.authenticate(
        scopeHint: ['email', 'profile'],
      );
      // Результат придёт через authenticationEvents — ждём
      final completer = Completer<GoogleSignInAccount?>();
      late StreamSubscription<GoogleSignInAuthenticationEvent> sub;
      sub = GoogleSignIn.instance.authenticationEvents.listen((event) {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          completer.complete(event.user);
          sub.cancel();
        } else if (event is GoogleSignInAuthenticationEventSignOut) {
          completer.complete(null);
          sub.cancel();
        }
      });
      final user = await completer.future.timeout(const Duration(seconds: 15));
      _currentUser = user;
      _isLoading = false;
      notifyListeners();
      return user != null;
    } catch (e) {
      _error = 'Ошибка входа: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Выход
  void signOut() {
    _currentUser = null;
    notifyListeners();
  }
}
