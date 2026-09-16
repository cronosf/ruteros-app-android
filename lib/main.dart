import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/env.dart';
import 'core/theme.dart';
import 'features/splash/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );
  runApp(const RuterosApp());
}

class RuterosApp extends StatelessWidget {
  const RuterosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ruteros',
      theme: ruterosDarkTheme,
      darkTheme: ruterosDarkTheme,
      themeMode: ThemeMode.dark,
      home: const SplashScreen(),
    );
  }
}
