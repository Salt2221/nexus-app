// ════════════════════════════════════════════
// NEXUS Login / Register — Google Sign-In
// ════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = NexusAuthService.instance;

  @override
  void initState() {
    super.initState();
    _auth.trySilentSignIn();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF161B22), const Color(0xFF0D1117)]
                : [const Color(0xFF6C63FF), const Color(0xFF5A52D5)],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // Logo / иконка
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Icon(Icons.shield,
                  size: 56, color: Colors.white),
              ),
              const SizedBox(height: 24),

              Text(
                'NEXUS',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.white,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Безопасный мессенджер',
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.grey[400] : Colors.white.withOpacity(0.85),
                ),
              ),

              const Spacer(flex: 1),

              // Кнопка входа через Google
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: ListenableBuilder(
                  listenable: _auth,
                  builder: (context, _) {
                    return SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _auth.isLoading ? null : _auth.signInWithGoogle,
                        icon: _auth.isLoading
                            ? const SizedBox(
                                width: 24, height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white,
                                ),
                              )
                            : Image.network(
                                'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                                width: 24, height: 24,
                                errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata, size: 28),
                              ),
                        label: Text(
                          _auth.isLoading ? 'Вход...' : 'Войти через Google',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 2,
                        ),
                      ),
                    );
                  },
                ),
              ),

              if (_auth.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16, left: 40, right: 40),
                  child: Text(
                    _auth.error!,
                    style: TextStyle(color: Colors.red[300], fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),

              const Spacer(flex: 2),

              // Нижний текст
              Text(
                'Входя в приложение, вы соглашаетесь\nс условиями использования',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.grey[600] : Colors.white.withOpacity(0.6),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
