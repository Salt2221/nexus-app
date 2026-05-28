import 'package:flutter/material.dart';
import 'services/nexus_zapret.dart';
import 'services/mtproto_proxy.dart';
import 'services/transport_layer.dart';
import 'services/mesh_network.dart';
import 'services/customization_service.dart';
import 'services/update_checker.dart' show UpdateChecker, UpdateInfo;
import 'auth/login_screen.dart';
import 'services/auth_service.dart';
import 'home/home_screen.dart';
import 'chat/chat_screen.dart';
import 'vpn/vpn_screen.dart';
import 'settings/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Init services
  NexusZapret.instance.init();
  NexusMtprotoProxy.instance.init();
  CustomizationService.instance.loadFromPrefs();
  NexusAuthService.instance.initialize();

  runApp(const NexusApp());
}

/// Проверка обновлений при первом запуске (вызывается из _NexusAppState)
Future<bool> checkForUpdate() async {
  final update = await UpdateChecker.instance.checkForUpdate();
  return update != null;
}

class NexusApp extends StatefulWidget {
  const NexusApp({super.key});

  @override
  State<NexusApp> createState() => _NexusAppState();
}

class _NexusAppState extends State<NexusApp> with WidgetsBindingObserver {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    HomeScreen(),
    VpnScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Start background services
    NexusTransportManager.instance.init();
    MeshNetworkManager.instance.init();

    // Check for updates after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final update = await UpdateChecker.instance.checkForUpdate();
      if (update != null && context.mounted) {
        _showUpdateDialog(context, update);
      }
    });
  }

  void _showUpdateDialog(BuildContext context, UpdateInfo update) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Доступно обновление'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Версия: ${update.versionName}'),
            const SizedBox(height: 8),
            const Text('Что нового:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(update.changelog, style: const TextStyle(fontSize: 13)),
            if (update.downloadUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Скачать: ${update.downloadUrl}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Позже')),
          if (update.downloadUrl.isNotEmpty)
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Обновить')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MeshNetworkManager.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CustomizationService.instance,
      builder: (context, _) {
        final isDark = CustomizationService.instance.darkMode;
        return MaterialApp(
          title: 'NEXUS',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.light,
            colorSchemeSeed: CustomizationService.instance.primaryColor,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            colorSchemeSeed: CustomizationService.instance.primaryColor,
            useMaterial3: true,
          ),
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          home: ListenableBuilder(
            listenable: NexusAuthService.instance,
            builder: (context, _) {
              if (!NexusAuthService.instance.isSignedIn) {
                return const LoginScreen();
              }
              return Scaffold(
                body: IndexedStack(
                  index: _currentIndex,
                  children: _pages,
                ),
                bottomNavigationBar: NavigationBar(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: (i) => setState(() => _currentIndex = i),
                  backgroundColor: isDark ? const Color(0xFF161B22) : Colors.white,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: 'Чаты',
                    ),
                    NavigationDestination(
                      icon: ImageIcon(AssetImage('assets/vpn_icon.jpg'), size: 24),
                      selectedIcon: ImageIcon(AssetImage('assets/vpn_icon.jpg'), size: 24),
                      label: 'VPN',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.person_outline),
                      selectedIcon: Icon(Icons.person),
                      label: 'Профиль',
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
