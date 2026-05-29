import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class TelegramWebChat extends StatefulWidget {
  const TelegramWebChat({super.key});

  @override
  State<TelegramWebChat> createState() => _TelegramWebChatState();
}

class _TelegramWebChatState extends State<TelegramWebChat> {
  late final WebViewController _controller;
  bool _isReady = false;
  bool _canGoBack = false;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0D1117))
      ..setUserAgent('Mozilla/5.0 (Linux; Android 15; SM-S938B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.6422.165 Mobile Safari/537.36')
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) {
            setState(() {
              _isReady = true;
              _canGoBack = true;
            });
          }
        },
        onWebResourceError: (error) {
          // If Telegram blocked, try alternative URL
          if (!_isReady && _controller != null) {
            _controller.loadRequest(Uri.parse('https://web.telegram.org/k/'));
          }
        },
      ))
      ..loadRequest(Uri.parse('https://web.telegram.org/k/'));

    if (_controller.platform is AndroidWebViewController) {
      final android = _controller.platform as AndroidWebViewController;
      android.setOnShowFileSelector((_) async => []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.send, size: 20),
            SizedBox(width: 8),
            Text('Telegram',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                ],
              ),
            ),
        ],
      ),
    );
  }
}
