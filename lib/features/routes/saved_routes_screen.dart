import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/map_camera_controller.dart';
import '../../core/models.dart';
import '../../core/theme.dart';

class SavedRoutesScreen extends StatefulWidget {
  /// Cambia a la pestana Mapa (index 0) en el RootShell despues de abrir una ruta.
  final VoidCallback onOpenOnMap;

  const SavedRoutesScreen({super.key, required this.onOpenOnMap});

  @override
  State<SavedRoutesScreen> createState() => _SavedRoutesScreenState();
}

class _SavedRoutesScreenState extends State<SavedRoutesScreen> {
  final _supabase = Supabase.instance.client;
  List<SavedRoute> _routes = [];
  bool _loading = true;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    // Ahora que esta pantalla es una pestana fija del bottom nav (queda
    // montada desde que arranca la app, IndexedStack), sin esto una ruta
    // guardada desde el Mapa no aparecia aca sin salir y volver a entrar.
    _channel = _supabase
        .channel('public:ruteros-saved-routes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'saved_routes',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _supabase.from('saved_routes').select().order('created_at', ascending: false);
    if (!mounted) return;
    setState(() {
      _routes = (data as List).map((e) => SavedRoute.fromJson(e as Map<String, dynamic>)).toList();
      _loading = false;
    });
  }

  Future<void> _delete(String id) async {
    await _supabase.from('saved_routes').delete().eq('id', id);
    _load();
  }

  void _openOnMap(SavedRoute route) {
    // Reabre como destino pendiente (no solo centra la camara): asi aparece
    // el pin y el boton "Iniciar ruta" para retomarla desde donde estes ahora.
    MapCameraController.openSavedRoute(LatLng(route.destinoLat, route.destinoLng));
    // Esta pantalla se llega tanto empujada desde Perfil (hay que hacer pop)
    // como siendo una pestana propia del bottom nav (no hay nada que popear).
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    widget.onOpenOnMap();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis rutas')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _routes.isEmpty
                  ? ListView(
                      children: const [
                        Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'Todavia no guardaste ninguna ruta. Desde el mapa, manten presionado un punto y usa "Guardar ruta".',
                            style: TextStyle(color: AppColors.grisUI),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _routes.length,
                      itemBuilder: (context, i) {
                        final r = _routes[i];
                        final metrics = [r.distanceLabel, r.durationLabel]
                            .whereType<String>()
                            .join(' · ');
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              r.recorded ? Icons.fiber_manual_record : Icons.alt_route,
                              color: r.recorded ? Colors.redAccent : AppColors.azul,
                            ),
                            title: Text(r.nombre),
                            subtitle: Text(
                              metrics.isNotEmpty
                                  ? '${r.recorded ? 'Grabado' : 'Guardado'} · $metrics'
                                  : (r.recorded ? 'Grabado' : 'Guardado'),
                            ),
                            onTap: () => _openOnMap(r),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              onPressed: () => _delete(r.id),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
