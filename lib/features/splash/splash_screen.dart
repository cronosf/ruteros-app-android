import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/update_service.dart';
import '../auth/auth_gate.dart';
import '../update/update_required_screen.dart';

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
    _init();
  }

  Future<void> _init() async {
    // El chequeo de actualizacion corre en paralelo al delay del splash (no
    // se suma tiempo de espera extra), y como es sin sesion (no depende de
    // Supabase Auth) se puede hacer antes que cualquier otra cosa.
    final results = await Future.wait([
      Future.delayed(const Duration(milliseconds: 1400)),
      UpdateService.checkForUpdate(),
    ]);
    if (!mounted) return;
    final updateInfo = results[1] as AppUpdateInfo?;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => updateInfo != null ? UpdateRequiredScreen(info: updateInfo) : const AuthGate(),
      ),
    );
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
