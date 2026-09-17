import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/env.dart';
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

  Future<void> _editRoute(SavedRoute route) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditRouteForm(route: route),
    );
    if (saved == true) _load();
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
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, color: AppColors.grisUI),
                                  onPressed: () => _editRoute(r),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  onPressed: () => _delete(r.id),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _EditRouteForm extends StatefulWidget {
  final SavedRoute route;

  const _EditRouteForm({required this.route});

  @override
  State<_EditRouteForm> createState() => _EditRouteFormState();
}

class _EditRouteFormState extends State<_EditRouteForm> {
  final _supabase = Supabase.instance.client;
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _direccionCtrl;
  late final TextEditingController _direccionExactaCtrl;

  double? _newDestinoLat;
  double? _newDestinoLng;
  Timer? _searchDebounce;
  List<GeoSuggestion> _suggestions = [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(text: widget.route.nombre);
    _direccionCtrl = TextEditingController(
      text: 'Ubicacion actual (${widget.route.destinoLat.toStringAsFixed(4)}, '
          '${widget.route.destinoLng.toStringAsFixed(4)})',
    );
    _direccionExactaCtrl = TextEditingController(text: widget.route.direccionExacta ?? '');
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _direccionCtrl.dispose();
    _direccionExactaCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onAddressChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () => _fetchSuggestions(query));
  }

  Future<void> _fetchSuggestions(String query) async {
    if (Env.maptilerKey.isEmpty) return;
    try {
      final uri = Uri.parse(
        'https://api.maptiler.com/geocoding/${Uri.encodeComponent(query)}.json'
        '?key=${Env.maptilerKey}&language=es&limit=5',
      );
      final res = await http.get(uri);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final features = (data['features'] as List?) ?? [];
      if (!mounted) return;
      setState(() {
        _suggestions = features.map((f) {
          final coords = f['geometry']['coordinates'] as List;
          return GeoSuggestion(
            placeName: f['place_name'] as String,
            lat: (coords[1] as num).toDouble(),
            lng: (coords[0] as num).toDouble(),
          );
        }).toList();
      });
    } catch (_) {
      // sin sugerencias si falla la red
    }
  }

  void _selectSuggestion(GeoSuggestion s) {
    setState(() {
      _newDestinoLat = s.lat;
      _newDestinoLng = s.lng;
      _direccionCtrl.text = s.placeName;
      _suggestions = [];
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _submit() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'El nombre es requerido.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payload = <String, dynamic>{
        'nombre': nombre,
        'direccion_exacta': _direccionExactaCtrl.text.trim().isEmpty ? null : _direccionExactaCtrl.text.trim(),
      };
      if (_newDestinoLat != null && _newDestinoLng != null) {
        payload['destino_lat'] = _newDestinoLat;
        payload['destino_lng'] = _newDestinoLng;
      }
      await _supabase.from('saved_routes').update(payload).eq('id', widget.route.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // viewInsets.bottom cubre el teclado; padding.bottom cubre la barra de
      // gestos del sistema -- sin este ultimo el boton de guardar quedaba
      // pegado/tapado por la barra de navegacion del telefono.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.fondoOscuro,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Editar ruta', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre (ej. Casa - Trabajo)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _direccionCtrl,
                onChanged: _onAddressChanged,
                decoration: const InputDecoration(
                  labelText: 'Ubicacion / Coordenadas',
                  helperText: 'Busca y elegi una direccion para cambiar el destino',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _direccionExactaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Direccion exacta',
                  helperText: 'Numero de casa/local, referencia, etc (la busqueda no siempre lo trae)',
                ),
              ),
              if (_suggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111C30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    itemBuilder: (context, i) {
                      final s = _suggestions[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.place, size: 18),
                        title: Text(s.placeName, style: const TextStyle(fontSize: 13)),
                        onTap: () => _selectSuggestion(s),
                      );
                    },
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Guardar cambios'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
