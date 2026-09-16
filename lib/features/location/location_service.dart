import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Publica la posicion del usuario en `live_locations` (Supabase) cada vez que
/// se mueve mas de 25m, con un tick maximo cada 6s para no saturar la red ni
/// la bateria. No llama a ninguna API de Google: el compartir posicion en
/// tiempo real corre por Supabase Realtime, es gratis y escala con la DB.
class LocationService {
  final _supabase = Supabase.instance.client;
  StreamSubscription<Position>? _positionSub;
  DateTime _lastUpsert = DateTime.fromMillisecondsSinceEpoch(0);

  final _positionController = StreamController<Position>.broadcast();
  Stream<Position> get positionStream => _positionController.stream;

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

  void _onPosition(Position position) {
    _positionController.add(position);

    final now = DateTime.now();
    if (now.difference(_lastUpsert) < const Duration(seconds: 6)) return;
    _lastUpsert = now;

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    _supabase.from('live_locations').upsert({
      'user_id': userId,
      'geom': 'POINT(${position.longitude} ${position.latitude})',
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
    _positionController.close();
  }
}
