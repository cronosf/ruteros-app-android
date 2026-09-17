import 'dart:async';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Posicion ya enganchada a la calle (snap-to-road) + el heading crudo del
/// GPS, para poder rotar el icono de "en ruta" hacia donde mira el usuario.
class SnappedPosition {
  final LatLng point;
  final double? heading;

  SnappedPosition(this.point, this.heading);
}

/// Publica la posicion del usuario en `live_locations` (Supabase) cada vez que
/// se mueve mas de 25m, con un tick maximo cada 6s para no saturar la red ni
/// la bateria. No llama a ninguna API de Google: el compartir posicion en
/// tiempo real corre por Supabase Realtime, es gratis y escala con la DB.
///
/// Antes de mostrar/guardar la posicion, la "engancha" a la calle mas cercana
/// (snap-to-road) via el servicio publico de OSRM (gratis, sin key) — asi el
/// usuario aparece siempre sobre una via, no en medio de una manzana o dentro
/// de una casa, como corresponde a un clon de Waze centrado en rutas.
/// Nota: OSRM's demo server es para uso liviano/pruebas, no tiene SLA. Si mas
/// adelante hay trafico real, conviene hostear un OSRM propio o usar Valhalla.
class LocationService {
  final _supabase = Supabase.instance.client;
  StreamSubscription<Position>? _positionSub;
  DateTime _lastUpsert = DateTime.fromMillisecondsSinceEpoch(0);

  final _snappedPositionController = StreamController<SnappedPosition>.broadcast();
  Stream<SnappedPosition> get snappedPositionStream => _snappedPositionController.stream;

  Future<bool> ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return false;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    return serviceEnabled &&
        (permission == LocationPermission.always || permission == LocationPermission.whileInUse);
  }

  void start() {
    _positionSub ??= Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
      ),
    ).listen(_onPosition);
  }

  Future<LatLng> _snapToRoad(LatLng point) async {
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/nearest/v1/driving/${point.longitude},${point.latitude}?number=1',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return point;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final waypoints = data['waypoints'] as List?;
      if (waypoints == null || waypoints.isEmpty) return point;
      final location = waypoints.first['location'] as List;
      return LatLng((location[1] as num).toDouble(), (location[0] as num).toDouble());
    } catch (_) {
      return point; // si OSRM falla (red, timeout), seguimos con la posicion cruda del GPS
    }
  }

  Future<void> _onPosition(Position position) async {
    final snapped = await _snapToRoad(LatLng(position.latitude, position.longitude));
    _snappedPositionController.add(SnappedPosition(snapped, position.heading));

    final now = DateTime.now();
    if (now.difference(_lastUpsert) < const Duration(seconds: 6)) return;
    _lastUpsert = now;

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    _supabase.from('live_locations').upsert({
      'user_id': userId,
      'geom': 'POINT(${snapped.longitude} ${snapped.latitude})',
      'heading': position.heading,
      'speed': position.speed,
      'updated_at': now.toIso8601String(),
    }).catchError((_) {
      // Si falla un tick de red no interrumpimos el stream de GPS; se reintenta en el siguiente.
    });
  }

  Future<void> stop() async {
    await _positionSub?.cancel();
    _positionSub = null;
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) {
      await _supabase.from('live_locations').delete().eq('user_id', userId);
    }
  }

  void dispose() {
    _positionSub?.cancel();
    _snappedPositionController.close();
  }
}
