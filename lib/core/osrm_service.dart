import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';

/// Una maniobra de la ruta ("gire a la derecha", "tome la rotonda", etc.)
/// para la voz guiada -- viene de los "steps" que devuelve OSRM con
/// steps=true. `location` es el punto donde hay que ejecutar la maniobra
/// (el arranque de este tramo); `stepDistanceMeters` es cuanto se avanza
/// DESPUES de esa maniobra hasta la siguiente.
class RouteStep {
  final String instruction;
  final LatLng location;
  final double stepDistanceMeters;

  RouteStep({
    required this.instruction,
    required this.location,
    required this.stepDistanceMeters,
  });
}

class RouteResult {
  final List<LatLng> geometry;
  final double distanceMeters;
  final double durationSeconds;
  final List<RouteStep> steps;

  /// Suma pesada de reportes encontrados cerca de esta ruta (incluye
  /// controles policiales/ATU, que pesan poco) -- se usa solo para el
  /// puntaje/orden de las alternativas, no para decidir si se muestra
  /// "libre". 0 hasta que map_screen.dart la calcula con _scoreRouteOptions.
  int trafficHits = 0;

  /// Cantidad de reportes que SI afectan el transito de verdad (accidente,
  /// trafico pesado, via cerrada, peligro) cerca de esta ruta -- un control
  /// policial o de fiscalizacion no bloquea el paso, asi que no cuenta aca.
  /// Es lo que decide si el chip de la ruta se ve "libre" o con advertencia.
  int impactfulReportCount = 0;

  RouteResult({
    required this.geometry,
    required this.distanceMeters,
    required this.durationSeconds,
    this.steps = const [],
  });

  /// Menor es mejor. Penaliza minutos "equivalentes" por cada reporte cercano
  /// a la ruta, asi una alternativa un poco mas larga pero sin reportes puede
  /// ganarle a la "mas rapida" en el papel si esa pasa por varios reportes.
  double get score => durationSeconds + trafficHits * 90;

  String get distanceLabel => distanceMeters >= 1000
      ? '${(distanceMeters / 1000).toStringAsFixed(1)} km'
      : '${distanceMeters.round()} m';

  String get durationLabel {
    final minutes = (durationSeconds / 60).round();
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return '${hours}h ${rest}min';
  }
}

/// Ruteo via el servidor demo publico de OSRM (gratis, sin key, mismo que se
/// usa para el snap-to-road). Es un servidor de uso liviano/pruebas, sin SLA:
/// para trafico de produccion real convendria hostear un OSRM propio.
class OsrmService {
  /// Hasta 3 rutas candidatas (la mas rapida + alternativas por otras calles).
  /// map_screen.dart las puntua contra los reportes activos y elige cual
  /// mostrar como recomendada.
  static Future<List<RouteResult>> getRoutes(LatLng origin, LatLng destination) async {
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=geojson&alternatives=true&steps=true',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') return [];

      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return [];
      return routes.take(3).map((route) {
        final r = route as Map<String, dynamic>;
        final coords = (r['geometry']['coordinates'] as List)
            .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();
        return RouteResult(
          geometry: coords,
          distanceMeters: (r['distance'] as num).toDouble(),
          durationSeconds: (r['duration'] as num).toDouble(),
          steps: _parseSteps(r),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static List<RouteStep> _parseSteps(Map<String, dynamic> route) {
    final legs = route['legs'] as List?;
    if (legs == null || legs.isEmpty) return [];
    final rawSteps = (legs.first as Map<String, dynamic>)['steps'] as List?;
    if (rawSteps == null) return [];

    return rawSteps.map((s) {
      final step = s as Map<String, dynamic>;
      final maneuver = step['maneuver'] as Map<String, dynamic>;
      final loc = maneuver['location'] as List;
      return RouteStep(
        instruction: _instructionFor(
          type: maneuver['type'] as String? ?? '',
          modifier: maneuver['modifier'] as String?,
          streetName: step['name'] as String? ?? '',
          exit: maneuver['exit'] as int?,
        ),
        location: LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble()),
        stepDistanceMeters: (step['distance'] as num).toDouble(),
      );
    }).toList();
  }

  /// Traduce el (type, modifier) de OSRM a una instruccion en español para
  /// la voz guiada. OSRM sigue las convenciones de Mapbox Directions:
  /// https://docs.mapbox.com/api/navigation/directions/#step-maneuver-object
  static String _instructionFor({
    required String type,
    String? modifier,
    required String streetName,
    int? exit,
  }) {
    final calle = streetName.isNotEmpty ? ' por $streetName' : '';
    switch (type) {
      case 'depart':
        return 'Iniciando ruta$calle';
      case 'arrive':
        return 'Ha llegado a su destino';
      case 'roundabout':
      case 'rotary':
        return exit != null ? 'Tome la rotonda y salga en la salida $exit' : 'Tome la rotonda';
      case 'exit roundabout':
      case 'exit rotary':
        return 'Salga de la rotonda$calle';
      case 'merge':
        return 'Incorporese a la via$calle';
      case 'on ramp':
        return 'Tome la rampa$calle';
      case 'off ramp':
        return 'Salga por la rampa$calle';
      case 'fork':
        return 'En la bifurcacion, ${_modifierText(modifier)}$calle';
      case 'end of road':
        return 'Al final de la via, ${_modifierText(modifier)}$calle';
      case 'continue':
      case 'new name':
        return modifier == 'straight' || modifier == null
            ? 'Continue derecho$calle'
            : '${_modifierText(modifier)}$calle';
      case 'turn':
        return '${_modifierText(modifier)}$calle';
      default:
        return 'Continue$calle';
    }
  }

  static String _modifierText(String? modifier) {
    switch (modifier) {
      case 'uturn':
        return 'Haga un cambio de sentido';
      case 'sharp right':
        return 'Gire fuertemente a la derecha';
      case 'right':
        return 'Gire a la derecha';
      case 'slight right':
        return 'Gire levemente a la derecha';
      case 'straight':
        return 'Continue derecho';
      case 'slight left':
        return 'Gire levemente a la izquierda';
      case 'left':
        return 'Gire a la izquierda';
      case 'sharp left':
        return 'Gire fuertemente a la izquierda';
      default:
        return 'Continue';
    }
  }
}
