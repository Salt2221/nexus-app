import 'package:flutter/material.dart';
import 'services/nexus_zapret.dart';
import 'services/customization_service.dart';
import 'services/update_checker.dart' show UpdateChecker, UpdateInfo;
import 'services/mtproto_proxy.dart';
import 'services/mesh_network.dart';
import 'services/auth_service.dart';
import 'auth/login_screen.dart';
import 'home/home_screen.dart';
import 'chat/deepseek_screen.dart';
import 'vpn/vpn_screen.dart';
import 'settings/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load all services BEFORE runApp
  await CustomizationService.instance.loadFromPrefs();
  await NexusAuthService.instance.initialize();

  NexusZapret.instance.init();
  NexusMtprotoProxy.instance.init();
  MeshNetworkManager.instance.init();

  runApp(const NexusApp());
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
    DeepSeekChatScreen(),
    VpnScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    NexusAuthService.instance.addListener(_onAuthChanged);
    CustomizationService.instance.addListener(_onCustomChanged);

    // Auto-check update
    _checkUpdateOnce();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NexusAuthService.instance.removeListener(_onAuthChanged);
    CustomizationService.instance.removeListener(_onCustomChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  void _onCustomChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _checkUpdateOnce() async {
    try {
      final update = await UpdateChecker.instance.checkForUpdate();
      if (update != null && mounted) {
        _showUpdateAvailable(update);
      }
    } catch (_) {}
  }

  void _showUpdateAvailable(UpdateInfo update) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Доступно обновление'),
        content: Text('Версия ${update.versionName} (${update.versionCode})\n\n${update.changelog}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Позже')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              UpdateChecker.instance.applyUpdate();
            },
            child: const Text('Обновить'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CustomizationService.instance.darkMode;
    final primary = CustomizationService.instance.primaryColor;
    final useMaterial3 = !CustomizationService.instance.reducedMotion;

    final theme = ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F2F5),
      colorSchemeSeed: primary,
      useMaterial3: useMaterial3,
    );

    return MaterialApp(
      title: 'NEXUS',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: NexusAuthService.instance.isSignedIn
          ? _buildMainScaffold(primary)
          : const LoginScreen(),
    );
  }

  Widget _buildMainScaffold(Color primary) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF161B22)
            : Colors.white,
        indicatorColor: primary.withValues(alpha: 0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Главная',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.shield_outlined),
            selectedIcon: Icon(Icons.shield),
            label: 'VPN',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Профиль',
          ),
        ],
      ),
    );
  }
}
