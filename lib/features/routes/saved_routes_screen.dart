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

  @override
  void initState() {
    super.initState();
    _load();
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
    MapCameraController.moveTo(LatLng(route.origenLat, route.origenLng));
    Navigator.of(context).pop();
    widget.onOpenOnMap();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis rutas')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _routes.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Todavia no guardaste ninguna ruta. Desde el mapa, manten presionado un punto y usa "Guardar ruta".',
                    style: TextStyle(color: AppColors.grisUI),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _routes.length,
                  itemBuilder: (context, i) {
                    final r = _routes[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.alt_route, color: AppColors.azul),
                        title: Text(r.nombre),
                        subtitle: Text(
                          '${r.origenLat.toStringAsFixed(4)}, ${r.origenLng.toStringAsFixed(4)} → '
                          '${r.destinoLat.toStringAsFixed(4)}, ${r.destinoLng.toStringAsFixed(4)}',
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
    );
  }
}
