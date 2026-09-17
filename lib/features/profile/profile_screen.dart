import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../admin/manage_business_pins_screen.dart';
import '../auth/auth_service.dart';
import '../reports/my_reports_screen.dart';
import '../routes/saved_routes_screen.dart';
import '../settings/edit_profile_screen.dart';
import '../settings/settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  /// Cambia de pestana en el RootShell (0=Mapa, 1=Reportes, 2=Amigos, 3=Perfil).
  final void Function(int index) onNavigateTab;

  const ProfileScreen({super.key, required this.onNavigateTab});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _supabase = Supabase.instance.client;
  final _auth = AuthService();
  Profile? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final data = await _supabase.from('profiles').select().eq('id', userId).maybeSingle();
    if (mounted && data != null) setState(() => _profile = Profile.fromJson(data));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Iniciales estilo Google (nunca la foto de Google ni de
                  // ningun otro proveedor) para que todos los avatares se
                  // vean iguales sin depender de una imagen externa.
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.verde,
                    child: Text(
                      _profile?.initials ?? '?',
                      style: const TextStyle(
                        color: AppColors.fondoOscuro,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _profile?.displayName ?? 'Usuario',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(color: AppColors.verde, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 6),
                            Text(_profile?.email ?? '', style: const TextStyle(color: AppColors.grisUI, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                          ).then((_) => _load()),
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('Editar perfil'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            minimumSize: Size.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.home, color: AppColors.verde),
                  title: const Text('Inicio'),
                  onTap: () => widget.onNavigateTab(0),
                ),
                ListTile(
                  leading: const Icon(Icons.alt_route),
                  title: const Text('Mis rutas'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SavedRoutesScreen(onOpenOnMap: () => widget.onNavigateTab(0)),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.warning_amber),
                  title: const Text('Reportar incidente'),
                  onTap: () => widget.onNavigateTab(1),
                ),
                ListTile(
                  leading: const Icon(Icons.list_alt),
                  title: const Text('Mis reportes'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MyReportsScreen()),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.people),
                  title: const Text('Amigos'),
                  onTap: () => widget.onNavigateTab(2),
                ),
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('Configuracion'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
                if (_profile?.isAdmin == true)
                  ListTile(
                    leading: const Icon(Icons.star, color: Colors.amber),
                    title: const Text('Gestionar negocios'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ManageBusinessPinsScreen()),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _auth.signOut(),
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            label: const Text('Cerrar sesion', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}
