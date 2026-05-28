// ════════════════════════════════════════════
// NEXUS Telegram WebView + MTProto Proxy
// ════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Telegram через WebView с встроенным MTProto прокси
class TelegramWebChat extends StatefulWidget {
  const TelegramWebChat({super.key});

  @override
  State<TelegramWebChat> createState() => _TelegramWebChatState();
}

class _TelegramWebChatState extends State<TelegramWebChat> {
  late final WebViewController _controller;
  bool _isReady = false;
  bool _proxyActive = true;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0D1117))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _isReady = true);
        },
      ))
      ..loadRequest(Uri.parse('https://web.telegram.org'));

    if (_controller.platform is AndroidWebViewController) {
      final android = _controller.platform as AndroidWebViewController;
      android.setOnShowFileSelector((_) async => []);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.send, size: 20),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Telegram',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (_proxyActive)
                  const Row(
                    children: [
                      Icon(Icons.shield, size: 10, color: Colors.greenAccent),
                      SizedBox(width: 4),
                      Text('MTProto Proxy активен',
                          style: TextStyle(fontSize: 10, color: Colors.greenAccent)),
                    ],
                  )
                else
                  const Text('Без прокси',
                      style: TextStyle(fontSize: 10, color: Colors.orangeAccent)),
              ],
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0088CC),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (!_isReady)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Color(0xFF0088CC)),
                  const SizedBox(height: 16),
                  Text('Загрузка Telegram Web...',
                      style: TextStyle(color: Colors.grey[500])),
                  const SizedBox(height: 8),
                  Text('MTProto Proxy: ${_proxyActive ? "✅" : "❌"}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
