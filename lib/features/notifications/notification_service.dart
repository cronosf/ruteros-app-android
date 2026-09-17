import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _notificationsEnabledKey = 'notifications_enabled';

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

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationsEnabledKey) ?? true;
  }

  Future<void> init() async {
    if (!await isEnabled()) return;
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

  /// Se llama desde Configuracion al togglear el switch. Al desactivar se
  /// borra el token guardado (asi la Edge Function ya no encuentra a donde
  /// mandarle el push) y se pide borrar el token del lado de FCM; al activar
  /// se vuelve a pedir permiso y registrar, igual que en init().
  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsEnabledKey, value);
    if (value) {
      await init();
      return;
    }
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) {
      await _supabase.from('device_tokens').delete().eq('user_id', userId);
    }
    await _messaging.deleteToken();
  }
}
