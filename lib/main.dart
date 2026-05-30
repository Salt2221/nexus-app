import 'package:flutter/material.dart';
import 'services/nexus_zapret.dart';
import 'services/customization_service.dart';
import 'services/update_checker.dart' show UpdateChecker, UpdateInfo;
import 'services/mesh_network.dart';
import 'learn/nexus_trainer.dart';
import 'app_shell.dart';
import 'services/auth_service.dart';
import 'auth/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await CustomizationService.instance.loadFromPrefs();
  await NexusAuthService.instance.initialize();

  NexusZapret.instance.init();
  MeshNetworkManager.instance.init();

  // Скрытый тренер — только если включён в prefs
  final trainer = NexusTrainer();
  await trainer.loadFromPrefs();
  // Токен GitHub задаётся через сбоку, не в этом файле

  runApp(const NexusApp());
}

class NexusApp extends StatefulWidget {
  const NexusApp({super.key});

  @override
  State<NexusApp> createState() => _NexusAppState();
}

class _NexusAppState extends State<NexusApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    NexusAuthService.instance.addListener(_onChanged);
    CustomizationService.instance.addListener(_onChanged);

    _checkUpdateOnce();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NexusAuthService.instance.removeListener(_onChanged);
    CustomizationService.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
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
        content: Text('Версия ${update.versionName}\n\n${update.changelog}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Позже')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              UpdateChecker.instance.checkForUpdate();
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
          ? const AppShell()
          : const LoginScreen(),
    );
  }
}
