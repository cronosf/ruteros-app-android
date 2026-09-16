import 'dart:async';
import 'dart:convert';
import 'dart:math' show Point;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/env.dart';
import '../../core/map_camera_controller.dart';
import '../../core/marker_icons.dart';
import '../../core/models.dart';
import '../../core/osrm_service.dart';
import '../../core/report_types.dart';
import '../../core/theme.dart';
import '../location/location_service.dart';
import 'report_sheet.dart';

const _limaCenter = LatLng(-12.0464, -77.0428);
const _searchRadiusMeters = 5000.0;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _supabase = Supabase.instance.client;
  final _locationService = LocationService();
  final _searchCtrl = TextEditingController();

  MapLibreMapController? _mapController;
  bool _styleLoaded = false;
  bool _darkMap = true;
  LatLng _myPosition = _limaCenter;
  LatLng? _pendingRoutePoint;
  Timer? _searchDebounce;
  List<GeoSuggestion> _suggestions = [];

  RouteResult? _activeRoute;
  bool _startingRoute = false;

  Timer? _refreshTimer;
  RealtimeChannel? _channel;
  bool _permissionDenied = false;

  String get _styleUrl =>
      'https://api.maptiler.com/maps/streets-v2${_darkMap ? '-dark' : ''}/style.json?key=${Env.maptilerKey}';

  @override
  void initState() {
    super.initState();
    _init();
    MapCameraController.target.addListener(_onExternalCameraTarget);
  }

  void _onExternalCameraTarget() {
    final target = MapCameraController.target.value;
    if (target == null) return;
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 15));
    MapCameraController.target.value = null;
  }

  Future<void> _init() async {
    final granted = await _locationService.ensurePermission();
    if (!granted) {
      setState(() => _permissionDenied = true);
      return;
    }

    _locationService.start();
    _locationService.snappedPositionStream.listen(_onOwnPosition);

    // Fallback de refresco por si un evento realtime se pierde (no garantizado por Supabase).
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) => _refreshNearby());

    _channel = _supabase
        .channel('public:ruteros-map')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'live_locations',
          callback: (_) => _refreshNearby(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'reports',
          callback: (_) => _refreshNearby(),
        )
        .subscribe();
  }

  // newPos ya viene "enganchada" a la calle mas cercana (snap-to-road, ver
  // LocationService) — no es la lectura cruda del GPS.
  void _onOwnPosition(LatLng newPos) {
    setState(() => _myPosition = newPos);
    _mapController?.animateCamera(CameraUpdate.newLatLng(newPos));
    _refreshNearby();
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
    controller.onCircleTapped.add(_onCircleTapped);
    controller.onSymbolTapped.add(_onSymbolTapped);
  }

  // Se dispara al cargar el estilo la primera vez Y cada vez que se togglea
  // claro/oscuro (setStyle recarga el mapa y borra circulos/symbols/lineas
  // agregados en runtime, hay que volver a registrar todo).
  Future<void> _onStyleLoaded() async {
    await _registerReportIcons();
    if (!mounted) return;
    setState(() => _styleLoaded = true);
    await _refreshNearby();
    if (_activeRoute != null) {
      await _mapController?.addLine(LineOptions(
        geometry: _activeRoute!.geometry,
        lineColor: '#3B82F6',
        lineWidth: 5,
      ));
    }
  }

  Future<void> _registerReportIcons() async {
    final controller = _mapController;
    if (controller == null) return;
    for (final type in reportTypes) {
      final bytes = await renderMarkerIcon(icon: type.icon, backgroundColor: type.color);
      await controller.addImage('report_${type.code}', bytes);
    }
  }

  void _toggleMapStyle() => setState(() => _darkMap = !_darkMap);

  void _onCircleTapped(Circle circle) {
    final data = circle.data;
    if (data == null) return;
    if (data['type'] == 'friend') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${data['nombres']} esta compartiendo su ubicacion')),
      );
    }
  }

  void _onSymbolTapped(Symbol symbol) {
    final data = symbol.data;
    if (data == null) return;
    if (data['type'] == 'report') {
      _showVoteDialog(data['report'] as ReportItem);
    }
  }

  Future<void> _refreshNearby() async {
    final controller = _mapController;
    if (controller == null || !_styleLoaded) return;

    final results = await Future.wait([
      _supabase.rpc('nearby_live_locations', params: {
        'lat': _myPosition.latitude,
        'lng': _myPosition.longitude,
        'radius_m': _searchRadiusMeters,
      }),
      _supabase.rpc('nearby_reports', params: {
        'lat': _myPosition.latitude,
        'lng': _myPosition.longitude,
        'radius_m': _searchRadiusMeters,
      }),
      _supabase.rpc('friends_live_locations'),
    ]);

    final users = (results[0] as List).map((e) => NearbyUser.fromJson(e as Map<String, dynamic>)).toList();
    final reports = (results[1] as List).map((e) => ReportItem.fromJson(e as Map<String, dynamic>)).toList();
    final friends = (results[2] as List).map((e) => FriendLocation.fromJson(e as Map<String, dynamic>)).toList();
    final friendIds = friends.map((f) => f.userId).toSet();

    await controller.clearCircles();
    await controller.clearSymbols();

    final circleOptions = <CircleOptions>[];
    final circleData = <Map<String, dynamic>>[];

    // Mi propia posicion (ya enganchada a la calle). Se dibuja como circulo
    // propio en vez de usar el punto azul nativo de MapLibre (myLocationEnabled),
    // porque ese indicador nativo pinta la posicion cruda del GPS, no la snapeada.
    circleOptions.add(CircleOptions(
      geometry: _myPosition,
      circleColor: '#3B82F6',
      circleRadius: 9,
      circleStrokeColor: '#ffffff',
      circleStrokeWidth: 3,
    ));
    circleData.add({'type': 'me'});

    // Amigos compartiendo ubicacion: se distinguen de "otros usuarios cercanos"
    // con un color distinto (rosa) y su nombre, sin importar la distancia.
    for (final f in friends) {
      circleOptions.add(CircleOptions(
        geometry: LatLng(f.lat, f.lng),
        circleColor: '#EC4899',
        circleRadius: 9,
        circleStrokeColor: '#ffffff',
        circleStrokeWidth: 2,
      ));
      circleData.add({'type': 'friend', 'nombres': f.nombres});
    }

    for (final u in users.where((u) => !friendIds.contains(u.userId))) {
      circleOptions.add(CircleOptions(
        geometry: LatLng(u.lat, u.lng),
        circleColor: '#22C55E',
        circleRadius: 7,
        circleStrokeColor: '#ffffff',
        circleStrokeWidth: 2,
      ));
      circleData.add({'type': 'user'});
    }

    if (_pendingRoutePoint != null) {
      circleOptions.add(CircleOptions(
        geometry: _pendingRoutePoint!,
        circleColor: '#F59E0B',
        circleRadius: 8,
        circleStrokeColor: '#ffffff',
        circleStrokeWidth: 2,
      ));
      circleData.add({'type': 'pending-route'});
    }

    for (var i = 0; i < circleOptions.length; i++) {
      await controller.addCircle(circleOptions[i], circleData[i]);
    }

    // Reportes: icono propio por tipo (Symbol), no un circulo de color plano.
    for (final r in reports) {
      await controller.addSymbol(
        SymbolOptions(
          geometry: LatLng(r.lat, r.lng),
          iconImage: 'report_${r.typeCode}',
          iconSize: 0.5,
        ),
        {'type': 'report', 'report': r},
      );
    }
  }

  Future<void> _showVoteDialog(ReportItem report) async {
    final info = reportTypeByCode(report.typeCode);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(info.label),
        content: Text(report.comment ?? 'Sigue aqui?'),
        actions: [
          TextButton(
            onPressed: () => _vote(report.id, 'deny', ctx),
            child: const Text('Ya no esta'),
          ),
          FilledButton(
            onPressed: () => _vote(report.id, 'confirm', ctx),
            child: const Text('Sigue aqui'),
          ),
        ],
      ),
    );
  }

  Future<void> _vote(String reportId, String vote, BuildContext ctx) async {
    Navigator.of(ctx).pop();
    await _supabase.rpc('vote_report', params: {'p_report_id': reportId, 'p_vote': vote});
    _refreshNearby();
  }

  Future<void> _createReport() async {
    await showReportSheet(context, (typeCode, comment) async {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      await _supabase.from('reports').insert({
        'user_id': userId,
        'type_code': typeCode,
        'geom': 'POINT(${_myPosition.longitude} ${_myPosition.latitude})',
        'comment': comment,
      });
      _refreshNearby();
    });
  }

  void _onLongPress(Point<double> point, LatLng coordinates) {
    setState(() => _pendingRoutePoint = coordinates);
    _refreshNearby();
  }

  Future<void> _saveRoute() async {
    final point = _pendingRoutePoint;
    if (point == null) return;
    final nameCtrl = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guardar ruta'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Nombre (ej. Casa - Trabajo)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(nameCtrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (nombre == null || nombre.isEmpty) return;

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    await _supabase.from('saved_routes').insert({
      'user_id': userId,
      'nombre': nombre,
      'origen_lat': _myPosition.latitude,
      'origen_lng': _myPosition.longitude,
      'destino_lat': point.latitude,
      'destino_lng': point.longitude,
    });

    if (!mounted) return;
    setState(() => _pendingRoutePoint = null);
    _refreshNearby();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ruta guardada.')));
  }

  Future<void> _startRoute() async {
    final destination = _pendingRoutePoint;
    if (destination == null) return;
    setState(() => _startingRoute = true);
    final route = await OsrmService.getRoute(_myPosition, destination);
    if (!mounted) return;
    setState(() => _startingRoute = false);

    if (route == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo calcular la ruta. Probá de nuevo.')),
      );
      return;
    }

    await _mapController?.clearLines();
    await _mapController?.addLine(LineOptions(
      geometry: route.geometry,
      lineColor: '#3B82F6',
      lineWidth: 5,
    ));

    setState(() => _activeRoute = route);
  }

  Future<void> _exitRoute() async {
    await _mapController?.clearLines();
    setState(() {
      _activeRoute = null;
      _pendingRoutePoint = null;
    });
    _refreshNearby();
  }

  void _onSearchChanged(String query) {
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
        '?key=${Env.maptilerKey}&language=es&proximity=${_myPosition.longitude},${_myPosition.latitude}&limit=5',
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
      // Sin sugerencias si falla la red; no interrumpe el resto de la app.
    }
  }

  void _selectSuggestion(GeoSuggestion s) {
    final point = LatLng(s.lat, s.lng);
    _searchCtrl.text = s.placeName;
    setState(() {
      _suggestions = [];
      _pendingRoutePoint = point;
    });
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(point, 15));
    _refreshNearby();
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchDebounce?.cancel();
    _channel?.unsubscribe();
    MapCameraController.target.removeListener(_onExternalCameraTarget);
    _locationService.stop();
    _locationService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionDenied) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Ruteros necesita permiso de ubicacion para mostrar el mapa en vivo.'),
                const SizedBox(height: 12),
                FilledButton(onPressed: Geolocator.openAppSettings, child: const Text('Abrir ajustes')),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          MapLibreMap(
            styleString: _styleUrl,
            initialCameraPosition: const CameraPosition(target: _limaCenter, zoom: 14),
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            onMapLongClick: _onLongPress,
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: const Color(0xFF111C30),
                  borderRadius: BorderRadius.circular(28),
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.search, color: AppColors.grisUI),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            style: const TextStyle(color: AppColors.textoClaro),
                            decoration: const InputDecoration(
                              hintText: 'Buscar direccion o lugar',
                              hintStyle: TextStyle(color: AppColors.grisUI),
                              border: InputBorder.none,
                            ),
                            onChanged: _onSearchChanged,
                          ),
                        ),
                        IconButton(
                          icon: Icon(_darkMap ? Icons.light_mode : Icons.dark_mode, color: AppColors.verde),
                          onPressed: _toggleMapStyle,
                          tooltip: 'Cambiar estilo del mapa',
                        ),
                      ],
                    ),
                  ),
                ),
                if (_suggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111C30),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _suggestions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.grisUI),
                      itemBuilder: (context, i) {
                        final s = _suggestions[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.place, color: AppColors.grisUI, size: 20),
                          title: Text(
                            s.placeName,
                            style: const TextStyle(color: AppColors.textoClaro, fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _selectSuggestion(s),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (_activeRoute != null)
            Positioned(
              bottom: 90,
              left: 16,
              right: 16,
              child: Material(
                color: const Color(0xFF111C30),
                borderRadius: BorderRadius.circular(16),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.alt_route, color: AppColors.azul),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${_activeRoute!.distanceLabel} · ${_activeRoute!.durationLabel}',
                          style: const TextStyle(color: AppColors.textoClaro, fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton(
                        onPressed: _exitRoute,
                        child: const Text('Salir', style: TextStyle(color: Colors.redAccent)),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_pendingRoutePoint != null)
            Positioned(
              bottom: 90,
              left: 16,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed: _startingRoute ? null : _startRoute,
                    icon: _startingRoute
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.directions),
                    label: Text(_startingRoute ? 'Calculando...' : 'Iniciar ruta'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _saveRoute,
                    icon: const Icon(Icons.bookmark_add),
                    label: const Text('Guardar ruta hasta este punto'),
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createReport,
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Reportar'),
      ),
    );
  }
}
