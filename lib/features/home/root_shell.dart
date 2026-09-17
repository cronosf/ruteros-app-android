import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/create_username_screen.dart';
import '../friends/friends_screen.dart';
import '../map/map_screen.dart';
import '../notifications/notification_service.dart';
import '../profile/profile_screen.dart';
import '../reports/reports_list_screen.dart';
import '../routes/saved_routes_screen.dart';

/// Shell con bottom nav de 5 pestanas (Mapa/Reportes/Amigos/Mis rutas/Perfil).
/// Usa IndexedStack para mantener el estado de cada pestana (ej. el stream de
/// GPS del mapa) al cambiar entre ellas.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  // Cuentas creadas con Google Sign-In nunca pasan por register_screen.dart,
  // asi que pueden quedar sin "usuario". Se bloquea toda la app (mapa
  // incluido) con CreateUsernameScreen hasta que se complete.
  bool _checkingUsername = true;
  bool _needsUsername = false;

  @override
  void initState() {
    super.initState();
    // Se pide el permiso de notificaciones y se registra el token FCM recien
    // aca, ya con sesion activa (el token se guarda contra el user_id).
    NotificationService().init();
    _checkUsername();
  }

  Future<void> _checkUsername() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _checkingUsername = false);
      return;
    }
    final data = await Supabase.instance.client
        .from('profiles')
        .select('usuario')
        .eq('id', userId)
        .maybeSingle();
    if (!mounted) return;
    final usuario = data?['usuario'] as String?;
    setState(() {
      _needsUsername = usuario == null || usuario.isEmpty;
      _checkingUsername = false;
    });
  }

  void _goToTab(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    if (_checkingUsername) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_needsUsername) {
      return CreateUsernameScreen(onCreated: () => setState(() => _needsUsername = false));
    }
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const MapScreen(),
          const ReportsListScreen(),
          const FriendsScreen(),
          SavedRoutesScreen(onOpenOnMap: () => _goToTab(0)),
          ProfileScreen(onNavigateTab: _goToTab),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: _goToTab,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Mapa'),
          BottomNavigationBarItem(icon: Icon(Icons.report), label: 'Reportes'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Amigos'),
          BottomNavigationBarItem(icon: Icon(Icons.alt_route), label: 'Mis rutas'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}
