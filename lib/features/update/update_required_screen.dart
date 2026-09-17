import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../core/update_service.dart';

/// Pantalla de bloqueo total (igual de estricta que CreateUsernameGate): se
/// muestra en vez del resto de la app cuando hay una version mas nueva
/// publicada. Ruteros no esta en Play Store, asi que no hay forma de
/// actualizar sola -- el usuario tiene que tocar el boton, descargar el .apk
/// nuevo desde el navegador, e instalarlo a mano.
class UpdateRequiredScreen extends StatelessWidget {
  final AppUpdateInfo info;

  const UpdateRequiredScreen({super.key, required this.info});

  Future<void> _download() async {
    final uri = Uri.parse(info.apkUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/branding/logo_icon.png', width: 96, height: 96),
                  const SizedBox(height: 24),
                  const Icon(Icons.system_update, size: 48, color: AppColors.verde),
                  const SizedBox(height: 16),
                  const Text(
                    'Hay una nueva version de Ruteros',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Version ${info.version} disponible. Actualiza para seguir usando la app.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.grisUI),
                  ),
                  if (info.notes != null && info.notes!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(info.notes!, textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: _download,
                    icon: const Icon(Icons.download),
                    label: const Text('Descargar actualizacion'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
