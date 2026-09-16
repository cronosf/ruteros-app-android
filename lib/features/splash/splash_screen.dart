import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../auth/auth_gate.dart';

/// Pantalla de marca mostrada al abrir la app, antes de resolver la sesion.
/// El splash nativo de Android (flutter_native_splash) ya se ve un instante
/// antes de esto; esta pantalla replica el mockup completo (logo + wordmark +
/// tagline) porque el splash nativo no soporta ese nivel de detalle.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthGate()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fondoOscuro,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset('assets/branding/logo_icon.png', width: 140, height: 140),
            ),
            const SizedBox(height: 24),
            RichText(
              text: const TextSpan(
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900),
                children: [
                  TextSpan(text: 'Rute', style: TextStyle(color: Colors.white)),
                  TextSpan(text: 'ros', style: TextStyle(color: AppColors.verde)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Mejores rutas, juntos',
              style: TextStyle(color: AppColors.grisUI, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
