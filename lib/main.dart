import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'screens/home_screen.dart';
import 'theme_manager.dart';
import 'services/telemetry_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializamos Hive y abrimos la caché en RAM
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

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeManager(),
      child: const MillenniumKioskApp(),
    ),
  );
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
      home: const HomeScreen(),
    );
  }
}
