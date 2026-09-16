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
import '../../core/models.dart';
import '../../core/report_types.dart';
import '../../core/theme.dart';
import '../location/location_service.dart';
import 'report_sheet.dart';

const _limaCenter = LatLng(-12.0464, -77.0428);
const _searchRadiusMeters = 5000.0;

// ignore: deprecated_member_use
String _hex(Color color) => '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';

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
  LatLng _myPosition = _limaCenter;
  LatLng? _pendingRoutePoint;
  bool _searching = false;

  Timer? _refreshTimer;
  RealtimeChannel? _channel;
  bool _permissionDenied = false;

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
    _locationService.positionStream.listen(_onOwnPosition);

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

  void _onOwnPosition(Position position) {
    final newPos = LatLng(position.latitude, position.longitude);
    setState(() => _myPosition = newPos);
    _mapController?.animateCamera(CameraUpdate.newLatLng(newPos));
    _refreshNearby();
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
    controller.onCircleTapped.add(_onCircleTapped);
  }

  void _onCircleTapped(Circle circle) {
    final data = circle.data;
    if (data == null) return;
    if (data['type'] == 'report') {
      final report = data['report'] as ReportItem;
      _showVoteDialog(report);
    } else if (data['type'] == 'friend') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${data['nombres']} esta compartiendo su ubicacion')),
      );
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

    final options = <CircleOptions>[];
    final dataList = <Map<String, dynamic>>[];

    // Amigos compartiendo ubicacion: se distinguen de "otros usuarios cercanos"
    // con un color distinto (rosa) y su nombre, sin importar la distancia.
    for (final f in friends) {
      options.add(CircleOptions(
        geometry: LatLng(f.lat, f.lng),
        circleColor: '#EC4899',
        circleRadius: 9,
        circleStrokeColor: '#ffffff',
        circleStrokeWidth: 2,
      ));
      dataList.add({'type': 'friend', 'nombres': f.nombres});
    }

    for (final u in users.where((u) => !friendIds.contains(u.userId))) {
      options.add(CircleOptions(
        geometry: LatLng(u.lat, u.lng),
        circleColor: '#22C55E',
        circleRadius: 7,
        circleStrokeColor: '#ffffff',
        circleStrokeWidth: 2,
      ));
      dataList.add({'type': 'user'});
    }

    for (final r in reports) {
      options.add(CircleOptions(
        geometry: LatLng(r.lat, r.lng),
        circleColor: _hex(reportTypeByCode(r.typeCode).color),
        circleRadius: 8,
        circleStrokeColor: '#ffffff',
        circleStrokeWidth: 2,
      ));
      dataList.add({'type': 'report', 'report': r});
    }

    if (_pendingRoutePoint != null) {
      options.add(CircleOptions(
        geometry: _pendingRoutePoint!,
        circleColor: '#3B82F6',
        circleRadius: 8,
        circleStrokeColor: '#ffffff',
        circleStrokeWidth: 2,
      ));
      dataList.add({'type': 'pending-route'});
    }

    for (var i = 0; i < options.length; i++) {
      await controller.addCircle(options[i], dataList[i]);
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

  Future<void> _searchAddress() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty || Env.maptilerKey.isEmpty) return;
    setState(() => _searching = true);
    try {
      final uri = Uri.parse(
        'https://api.maptiler.com/geocoding/${Uri.encodeComponent(query)}.json'
        '?key=${Env.maptilerKey}&language=es&proximity=${_myPosition.longitude},${_myPosition.latitude}',
      );
      final res = await http.get(uri);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final features = data['features'] as List?;
      if (features == null || features.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se encontro esa direccion.')),
        );
        return;
      }
      final coords = (features.first['geometry']['coordinates'] as List);
      final target = LatLng((coords[1] as num).toDouble(), (coords[0] as num).toDouble());
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 15));
      setState(() => _pendingRoutePoint = target);
      _refreshNearby();
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
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
            styleString: 'https://api.maptiler.com/maps/streets-v2/style.json?key=${Env.maptilerKey}',
            initialCameraPosition: const CameraPosition(target: _limaCenter, zoom: 14),
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: () {
              setState(() => _styleLoaded = true);
              _refreshNearby();
            },
            onMapLongClick: _onLongPress,
            myLocationEnabled: true,
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Material(
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
                        onSubmitted: (_) => _searchAddress(),
                      ),
                    ),
                    if (_searching)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(icon: const Icon(Icons.arrow_forward, color: AppColors.verde), onPressed: _searchAddress),
                  ],
                ),
              ),
            ),
          ),
          if (_pendingRoutePoint != null)
            Positioned(
              bottom: 90,
              left: 16,
              right: 16,
              child: FilledButton.icon(
                onPressed: _saveRoute,
                icon: const Icon(Icons.bookmark_add),
                label: const Text('Guardar ruta hasta este punto'),
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
