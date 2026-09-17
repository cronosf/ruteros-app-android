import 'package:flutter/material.dart';
import '../auth/auth_service.dart';
import '../notifications/notification_service.dart';
import 'help_screen.dart';
import 'terms_screen.dart';
import 'user_manual_screen.dart';
import 'voice_guide_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _auth = AuthService();
  final _notifications = NotificationService();
  bool _notificationsEnabled = true;
  bool _loadingNotifSetting = true;

  @override
  void initState() {
    super.initState();
    NotificationService.isEnabled().then((enabled) {
      if (mounted) {
        setState(() {
          _notificationsEnabled = enabled;
          _loadingNotifSetting = false;
        });
      }
    });
  }

  Future<void> _onNotificationsChanged(bool value) async {
    setState(() => _notificationsEnabled = value);
    await _notifications.setEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuracion')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Notificaciones'),
            subtitle: const Text('Avisos de reportes cercanos (10km)'),
            value: _notificationsEnabled,
            onChanged: _loadingNotifSetting ? null : _onNotificationsChanged,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Guia de voz'),
            subtitle: const Text('Elegi el idioma/voz de la guia al navegar'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const VoiceGuideScreen()),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('Manual de usuario'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UserManualScreen()),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Ayuda'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HelpScreen()),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terminos y condiciones'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TermsScreen()),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Cerrar sesion'),
            onTap: () => _auth.signOut(),
          ),
        ],
      ),
    );
  }
}
