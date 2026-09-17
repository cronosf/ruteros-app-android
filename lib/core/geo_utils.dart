import 'dart:math';
import 'package:maplibre_gl/maplibre_gl.dart';

/// Aproximaciones livianas (no geodesia exacta) para las distancias cortas
/// que maneja esta app (rutas urbanas dentro de una ciudad, tolerancia de
/// decenas de metros) -- evita traer un paquete de geometria completo solo
/// para esto.
class GeoUtils {
  static const _earthRadiusM = 6371000.0;

  static double distanceMeters(LatLng a, LatLng b) {
    final lat1 = a.latitude * pi / 180;
    final lat2 = b.latitude * pi / 180;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final sinDLat = sin(dLat / 2);
    final sinDLng = sin(dLng / 2);
    final h = sinDLat * sinDLat + cos(lat1) * cos(lat2) * sinDLng * sinDLng;
    return 2 * _earthRadiusM * asin(sqrt(h.clamp(0, 1)));
  }

  /// Distancia minima de un punto a una polilinea (usada para: "me desvie de
  /// la ruta trazada?" y "que tan cerca pasa esta ruta de un reporte?").
  static double distanceToPolylineMeters(LatLng point, List<LatLng> line) {
    if (line.isEmpty) return double.infinity;
    if (line.length == 1) return distanceMeters(point, line.first);
    var minDist = double.infinity;
    for (var i = 0; i < line.length - 1; i++) {
      final d = _distanceToSegmentMeters(point, line[i], line[i + 1]);
      if (d < minDist) minDist = d;
    }
    return minDist;
  }

  // Proyecta a un plano local centrado en "a" (x = longitud escalada por
  // cos(lat), y = latitud) -- suficiente para segmentos de pocos km.
  static double _distanceToSegmentMeters(LatLng p, LatLng a, LatLng b) {
    final latRad = a.latitude * pi / 180;
    const mPerDegLat = 111320.0;
    final mPerDegLng = 111320.0 * cos(latRad);

    final bx = (b.longitude - a.longitude) * mPerDegLng;
    final by = (b.latitude - a.latitude) * mPerDegLat;
    final px = (p.longitude - a.longitude) * mPerDegLng;
    final py = (p.latitude - a.latitude) * mPerDegLat;

    final abLenSq = bx * bx + by * by;
    final t = abLenSq == 0 ? 0.0 : ((px * bx + py * by) / abLenSq).clamp(0.0, 1.0);
    final closestX = bx * t;
    final closestY = by * t;
    final dx = px - closestX;
    final dy = py - closestY;
    return sqrt(dx * dx + dy * dy);
  }
}
