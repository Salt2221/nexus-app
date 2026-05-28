import 'package:flutter/material.dart';
import 'services/nexus_zapret.dart';
import 'services/mtproto_proxy.dart';
import 'services/transport_layer.dart';
import 'services/mesh_network.dart';
import 'services/customization_service.dart';
import 'services/update_checker.dart';
import 'auth/login_screen.dart';
import 'services/auth_service.dart';
import 'home/home_screen.dart';
import 'vpn/vpn_screen.dart';
import 'settings/settings_screen.dart';
import 'chat/deepseek_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load all services BEFORE runApp
  await CustomizationService.instance.loadFromPrefs();
  await NexusAuthService.instance.initialize();

  NexusZapret.instance.init();
  NexusMtprotoProxy.instance.init();
  NexusTransportManager.instance.init();
  MeshNetworkManager.instance.init();

  // Listen for customization changes to hot-reload app
  CustomizationService.instance.addListener(_rebuildApp);

  runApp(const NexusApp());
}

void _rebuildApp() {
  // Force MaterialApp rebuild when theme changes
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

    // Listen for auth and customization changes
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
    final update = await UpdateChecker.instance.checkForUpdate();
    if (update != null && mounted) {
      _showUpdateAvailable(update);
    }
  }

  void _showUpdateAvailable(update) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Доступно обновление'),
        content: Text('Версия ${update.versionName} доступна.\n${update.changelog.length > 200 ? update.changelog.substring(0, 200) + '...' : update.changelog}'),
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
    final theme = isDark ? _darkTheme(primary) : _lightTheme(primary);

    return MaterialApp(
      title: 'NEXUS',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: _darkTheme(primary),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      home: NexusAuthService.instance.isSignedIn
          ? _buildMainScaffold(primary)
          : LoginScreen(),
    );
  }

  ThemeData _darkTheme(Color primary) {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0D1117),
      colorSchemeSeed: primary,
      useMaterial3: true,
    );
  }

  ThemeData _lightTheme(Color primary) {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF0F2F5),
      colorSchemeSeed: primary,
      useMaterial3: true,
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
        indicatorColor: primary.withOpacity(0.2),
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
