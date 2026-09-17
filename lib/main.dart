import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/env.dart';
import 'core/theme.dart';
import 'features/auth/auth_service.dart';
import 'features/splash/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );
  // Supabase ya restauro la sesion persistida (si habia). Si la ultima vez
  // que alguien inicio sesion dejo destildado "Recordar sesion", la cerramos
  // aca, en frio, antes de que la UI llegue a mostrar nada -- asi se
  // comporta como una sesion que "no se recuerda" en el siguiente arranque.
  if (!await AuthService.getRememberSession()) {
    await Supabase.instance.client.auth.signOut();
  }
  // Sin google-services.json (no todos los entornos de desarrollo lo tienen
  // configurado) esto tira, asi que se ignora el error y la app sigue
  // funcionando sin notificaciones push en vez de no arrancar.
  try {
    await Firebase.initializeApp();
  } catch (_) {}
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
