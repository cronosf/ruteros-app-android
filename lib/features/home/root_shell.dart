import 'package:flutter/material.dart';
import '../friends/friends_screen.dart';
import '../map/map_screen.dart';
import '../profile/profile_screen.dart';
import '../reports/reports_list_screen.dart';

/// Shell con bottom nav de 4 pestanas (Mapa/Reportes/Amigos/Perfil). Usa
/// IndexedStack para mantener el estado de cada pestana (ej. el stream de GPS
/// del mapa) al cambiar entre ellas.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  void _goToTab(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const MapScreen(),
          const ReportsListScreen(),
          const FriendsScreen(),
          ProfileScreen(onNavigateTab: _goToTab),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: _goToTab,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Mapa'),
          BottomNavigationBarItem(icon: Icon(Icons.report), label: 'Reportes'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Amigos'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}
