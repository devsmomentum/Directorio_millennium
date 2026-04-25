import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';

import 'screens/home_screen.dart';
import 'theme_manager.dart';
import 'services/telemetry_service.dart';
import 'widgets/emergency_wrapper.dart';

Future<void> main() async {
  // En release, si algo falla antes de runApp, la app suele quedarse “en blanco”.
  // Estos handlers fuerzan una UI de error visible para poder diagnosticar en el dispositivo.
  ErrorWidget.builder = (details) => _FatalErrorScreen(
        title: 'ErrorWidget',
        message: details.exceptionAsString(),
        stack: details.stack?.toString(),
      );

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    Zone.current.handleUncaughtError(
      details.exception,
      details.stack ?? StackTrace.current,
    );
  };

  await runZonedGuarded(() async {
    // CRÍTICO: ensureInitialized() debe correr dentro de la MISMA zona que
    // runApp(). Si se llama afuera (zona root) y runApp dentro de
    // runZonedGuarded, Flutter dispara "Zone mismatch" y el comportamiento
    // de los callbacks queda inconsistente.
    WidgetsFlutterBinding.ensureInitialized();

    // Inicializaciones específicas por plataforma.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      MediaKit.ensureInitialized();
      VideoPlayerMediaKit.ensureInitialized(linux: true);
    }

    // Inicializamos Hive y abrimos la caché
    await Hive.initFlutter();
    await Hive.openBox('kiosk_cache');

    // Inicialización de Supabase
    await Supabase.initialize(
      url: 'https://lrjgocjubpxruobshtoe.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxyamdvY2p1YnB4cnVvYnNodG9lIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyNTQwMTUsImV4cCI6MjA4ODgzMDAxNX0.hQrCDgMdhJ_B2ncjNhDBFetnnxhpbt7vP-EnzgKFT_I',
    );

    await ThemeManager().init();
    TelemetryService().start();

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    runApp(
      ChangeNotifierProvider(
        create: (_) => ThemeManager(),
        child: const MillenniumKioskApp(),
      ),
    );
  }, (error, stack) {
    runApp(
      _FatalErrorScreen(
        title: 'Unhandled exception',
        message: error.toString(),
        stack: stack.toString(),
      ),
    );
  });
}

class MillenniumKioskApp extends StatelessWidget {
  const MillenniumKioskApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeManager>(context);

    return MaterialApp(
      title: 'Millennium Mall Kiosco',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: theme.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: theme.primary,
          brightness: theme.isNeonTheme ? Brightness.dark : Brightness.light,
        ),
        textTheme: const TextTheme().apply(
          bodyColor: theme.text,
          displayColor: theme.text,
        ),
      ),
      builder: (context, child) {
        return EmergencyWrapper(
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const HomeScreen(),
    );
  }
}

class _FatalErrorScreen extends StatelessWidget {
  const _FatalErrorScreen({
    required this.title,
    required this.message,
    required this.stack,
  });

  final String title;
  final String message;
  final String? stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0B0B0B),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                height: 1.35,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(message),
                  if (stack != null) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Stack',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(stack!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
