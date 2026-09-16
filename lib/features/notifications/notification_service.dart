import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Registra el token FCM del dispositivo en `device_tokens` para que la Edge
/// Function `notify-nearby-report` pueda avisarle a este usuario cuando
/// alguien reporte algo dentro de un radio de 10km.
///
/// No hay una notificacion visual propia en foreground en este MVP: cuando
/// la app esta en background o cerrada, Android muestra la notificacion de
/// sistema automaticamente (FCM manda un payload "notification", no solo
/// "data"), que es el caso mas comun para este tipo de alerta.
class NotificationService {
  final _messaging = FirebaseMessaging.instance;
  final _supabase = Supabase.instance.client;

  Future<void> init() async {
    final settings = await _messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await _messaging.getToken();
    if (token != null) await _saveToken(token);

    _messaging.onTokenRefresh.listen(_saveToken);
  }

  Future<void> _saveToken(String token) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    await _supabase.from('device_tokens').upsert({
      'user_id': userId,
      'token': token,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}
