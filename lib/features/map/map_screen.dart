import 'dart:async';
import 'dart:convert';
import 'dart:math' show Point;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/env.dart';
import '../../core/geo_utils.dart';
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
// "Iniciar ruta" puede apuntar a cualquier parte del mapa (buscas una
// direccion lejana y armas la ruta hasta ahi), pero un reporte tiene que ser
// de algo que el usuario esta viendo/viviendo cerca -- sin este limite
// alguien podria tapear el mapa en otra ciudad y crear un reporte ahi.
const _reportMaxDistanceMeters = 10000.0;

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
  double? _heading;
  LatLng? _pendingRoutePoint;
  bool _draggingPendingPoint = false;
  Timer? _searchDebounce;
  List<GeoSuggestion> _suggestions = [];

  // "Iniciar ruta" pide hasta 3 alternativas a OSRM y las puntua contra los
  // reportes activos cercanos (ver _scoreRouteOptions) -- la de menor puntaje
  // (duracion + penalizacion por reportes) queda como recomendada en el
  // indice 0 tras ordenar, pero el usuario puede tocar una alternativa (linea
  // gris en el mapa, o su chip) para navegar por esa en cambio.
  List<RouteResult> _routeOptions = [];
  int _activeRouteIndex = 0;
  LatLng? _routeDestination;
  DateTime? _lastRerouteAt;
  bool _startingRoute = false;

  RouteResult? get _activeRoute => _routeOptions.isEmpty ? null : _routeOptions[_activeRouteIndex];

  // Voz guiada: avisa la proxima maniobra de la ruta activa a medida que te
  // acercas (dos avisos por maniobra: uno "a lo lejos" y uno justo antes),
  // usando el motor de texto-a-voz nativo del telefono.
  final FlutterTts _tts = FlutterTts();
  List<RouteStep> _voiceSteps = [];
  int _nextVoiceStepIndex = 0;
  final Set<int> _announcedFar = {};
  final Set<int> _announcedNear = {};
  // El GPS (ver LocationService) solo emite una posicion nueva cada 25m de
  // movimiento -- si _updateVoiceGuidance solo corriera con esos eventos, un
  // auto detenido en un semaforo (o alguien probando la app sin moverse)
  // nunca re-evaluaria si ya toca avisar la proxima maniobra. Este timer la
  // vuelve a chequear cada pocos segundos usando la ultima posicion conocida,
  // independiente de si llego un evento de GPS nuevo o no.
  Timer? _voiceGuidanceTimer;

  Timer? _refreshTimer;
  RealtimeChannel? _channel;
  bool _permissionDenied = false;

  // "Iniciar trayecto": a diferencia de "Iniciar ruta" (que necesita un
  // destino elegido de antemano), esto graba el camino real mientras manejas
  // sin destino fijo, para guardarlo despues en "rutas frecuentes" con la
  // distancia/duracion reales, no una estimacion de OSRM.
  bool _recordingTrip = false;
  final List<LatLng> _tripPoints = [];
  double _tripDistanceMeters = 0;
  DateTime? _tripStartedAt;
  Timer? _tripTicker;

  String get _styleUrl =>
      'https://api.maptiler.com/maps/streets-v2${_darkMap ? '-dark' : ''}/style.json?key=${Env.maptilerKey}';

  @override
  void initState() {
    super.initState();
    _init();
    _initTts();
    MapCameraController.target.addListener(_onExternalCameraTarget);
    MapCameraController.pendingRouteTarget.addListener(_onExternalPendingRoute);
  }

  Future<void> _initTts() async {
    // Si el motor de TTS del telefono no tiene instalada la voz "es-ES"
    // especifica, setLanguage devuelve false/1 en vez de tirar una excepcion
    // -- probamos un par de variantes de espanol antes de darnos por vencidos
    // y quedarnos con el idioma por defecto del sistema (mejor una voz en
    // ingles leyendo texto en espanol que ningun sonido).
    for (final lang in ['es-ES', 'es-US', 'es-MX', 'es']) {
      final isAvailable = await _tts.isLanguageAvailable(lang);
      if (isAvailable == true || isAvailable == 1) {
        await _tts.setLanguage(lang);
        break;
      }
    }
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1.0);
    _tts.setErrorHandler((msg) => debugPrint('flutter_tts error: $msg'));
  }

  void _onExternalCameraTarget() {
    final target = MapCameraController.target.value;
    if (target == null) return;
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 15));
    MapCameraController.target.value = null;
  }

  void _onExternalPendingRoute() {
    final target = MapCameraController.pendingRouteTarget.value;
    if (target == null) return;
    setState(() => _pendingRoutePoint = target);
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 15));
    _refreshNearby();
    MapCameraController.pendingRouteTarget.value = null;
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

  // pos.point ya viene "enganchada" a la calle mas cercana (snap-to-road, ver
  // LocationService) — no es la lectura cruda del GPS.
  void _onOwnPosition(SnappedPosition pos) {
    setState(() {
      if (_recordingTrip && _tripPoints.isNotEmpty) {
        _tripDistanceMeters += GeoUtils.distanceMeters(_tripPoints.last, pos.point);
        _tripPoints.add(pos.point);
      }
      _myPosition = pos.point;
      _heading = pos.heading;
    });
    _mapController?.animateCamera(CameraUpdate.newLatLng(pos.point));
    _refreshNearby();
    if (_routeOptions.isNotEmpty) {
      _maybeReroute();
      _updateVoiceGuidance(pos.point);
    }
    if (_recordingTrip) _redrawTripLine();
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
    controller.onCircleTapped.add(_onCircleTapped);
    controller.onSymbolTapped.add(_onSymbolTapped);
    controller.onFeatureDrag.add(_onFeatureDrag);
    controller.onLineTapped.add(_onLineTapped);
  }

  // Tocar una alternativa (linea gris) en el mapa la vuelve la ruta activa,
  // igual que tocar su chip en la barra inferior.
  void _onLineTapped(Line line) {
    final data = line.data;
    if (data == null || data['type'] != 'route-alt') return;
    _selectRouteOption(data['index'] as int);
  }

  Future<void> _selectRouteOption(int index) async {
    if (index == _activeRouteIndex || index >= _routeOptions.length) return;
    setState(() => _activeRouteIndex = index);
    _resetVoiceGuidance(_routeOptions[index]);
    await _redrawRouteLines();
  }

  // Arranca (o reinicia, ej. tras un recalculo o al cambiar de alternativa) el
  // seguimiento de maniobras para avisarlas por voz. El primer "step" de OSRM
  // es "depart" (el punto de partida en si) -- no hay maniobra que anunciar
  // ahi, por eso el seguimiento arranca en 1. `announceStart` solo va en true
  // al presionar "Iniciar ruta" (no al recalcular o cambiar de alternativa,
  // para no repetir el aviso a cada rato) y no depende de que llegue una
  // lectura de GPS nueva -- confirma de una que la voz esta funcionando.
  void _resetVoiceGuidance(RouteResult route, {bool announceStart = false}) {
    _voiceSteps = route.steps;
    _nextVoiceStepIndex = 1;
    _announcedFar.clear();
    _announcedNear.clear();
    if (announceStart) _speak('Iniciando ruta, voz guiada activada.');

    _voiceGuidanceTimer?.cancel();
    _voiceGuidanceTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _updateVoiceGuidance(_myPosition),
    );
  }

  void _stopVoiceGuidance() {
    _voiceGuidanceTimer?.cancel();
    _voiceGuidanceTimer = null;
    _tts.stop();
    _voiceSteps = [];
    _nextVoiceStepIndex = 0;
    _announcedFar.clear();
    _announcedNear.clear();
  }

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  // Se llama con cada actualizacion de GPS mientras hay una ruta activa: avisa
  // la proxima maniobra dos veces (a los ~300m, y de nuevo justo antes, a los
  // ~35m) y avanza a la siguiente maniobra cuando ya estas encima de esta.
  Future<void> _updateVoiceGuidance(LatLng pos) async {
    if (_nextVoiceStepIndex >= _voiceSteps.length) return;
    final step = _voiceSteps[_nextVoiceStepIndex];
    final dist = GeoUtils.distanceMeters(pos, step.location);

    if (dist <= 300 && !_announcedFar.contains(_nextVoiceStepIndex)) {
      _announcedFar.add(_nextVoiceStepIndex);
      final roundedDist = (dist / 50).round() * 50;
      await _speak(roundedDist >= 100 ? 'En $roundedDist metros, ${step.instruction}' : step.instruction);
    } else if (dist <= 35 && !_announcedNear.contains(_nextVoiceStepIndex)) {
      _announcedNear.add(_nextVoiceStepIndex);
      await _speak(step.instruction);
    }

    if (dist <= 15) {
      _nextVoiceStepIndex++;
    }
  }

  Future<void> _redrawRouteLines() async {
    final controller = _mapController;
    if (controller == null) return;
    await controller.clearLines();
    // La activa se agrega al final para que quede visualmente arriba de las
    // alternativas donde se superponen.
    for (var i = 0; i < _routeOptions.length; i++) {
      if (i == _activeRouteIndex) continue;
      await controller.addLine(
        LineOptions(
          geometry: _routeOptions[i].geometry,
          lineColor: '#64748B',
          lineWidth: 4,
          lineOpacity: 0.65,
        ),
        {'type': 'route-alt', 'index': i},
      );
    }
    if (_routeOptions.isNotEmpty) {
      await controller.addLine(
        LineOptions(
          geometry: _routeOptions[_activeRouteIndex].geometry,
          lineColor: '#3B82F6',
          lineWidth: 5,
        ),
        {'type': 'route-alt', 'index': _activeRouteIndex},
      );
    }
  }

  // Reportes de tipo trafico/accidente/via cerrada/peligro pesan mas en el
  // puntaje que un simple control policial o de fiscalizacion (esos no
  // bloquean el paso, solo pueden demorar un poco).
  static const _routeReportWeights = <String, int>{
    'traffic_jam': 3,
    'accident': 3,
    'road_closed': 3,
    'hazard': 2,
    'police_pnp': 1,
    'atu_checkpoint': 1,
  };

  Future<void> _scoreRouteOptions(List<RouteResult> routes) async {
    var minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
    for (final r in routes) {
      for (final p in r.geometry) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
    }
    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    final radius = (GeoUtils.distanceMeters(center, LatLng(minLat, minLng)) + 400)
        .clamp(1000.0, 25000.0);

    final data = await _supabase.rpc('nearby_reports', params: {
      'lat': center.latitude,
      'lng': center.longitude,
      'radius_m': radius,
    });
    final reports = (data as List).map((e) => ReportItem.fromJson(e as Map<String, dynamic>)).toList();

    for (final route in routes) {
      var hits = 0;
      var impactful = 0;
      for (final r in reports) {
        final weight = _routeReportWeights[r.typeCode];
        if (weight == null) continue;
        final dist = GeoUtils.distanceToPolylineMeters(LatLng(r.lat, r.lng), route.geometry);
        if (dist <= 120) {
          hits += weight;
          // Peso 1 = solo controles policiales/ATU: informan, no bloquean el
          // paso, asi que no cuentan para decidir si la ruta se ve "libre".
          if (weight >= 2) impactful++;
        }
      }
      route.trafficHits = hits;
      route.impactfulReportCount = impactful;
    }
  }

  // Se dispara con cada actualizacion de GPS mientras hay una ruta activa: si
  // te alejaste bastante de la linea trazada (te desviaste, o el semaforo te
  // mando por otra calle), se vuelve a calcular desde la posicion actual --
  // igual que el recalculo automatico de Waze/Google Maps. Con cooldown para
  // no golpear el servidor demo de OSRM en cada lectura de GPS.
  Future<void> _maybeReroute() async {
    final destination = _routeDestination;
    if (destination == null || _routeOptions.isEmpty) return;
    final active = _routeOptions[_activeRouteIndex];
    final deviation = GeoUtils.distanceToPolylineMeters(_myPosition, active.geometry);
    if (deviation < 45) return;
    final now = DateTime.now();
    if (_lastRerouteAt != null && now.difference(_lastRerouteAt!) < const Duration(seconds: 12)) return;
    _lastRerouteAt = now;

    final routes = await OsrmService.getRoutes(_myPosition, destination);
    if (routes.isEmpty || !mounted) return;
    await _scoreRouteOptions(routes);
    routes.sort((a, b) => a.score.compareTo(b.score));
    if (!mounted) return;
    setState(() {
      _routeOptions = routes;
      _activeRouteIndex = 0;
    });
    _resetVoiceGuidance(routes[0]);
    await _redrawRouteLines();
  }

  void _onFeatureDrag(
    Point<double> point,
    LatLng origin,
    LatLng current,
    LatLng delta,
    String id,
    Annotation? annotation,
    DragEventType eventType,
  ) {
    if (annotation is! Circle || annotation.data?['type'] != 'pending-route') return;
    switch (eventType) {
      case DragEventType.start:
        // Mientras se arrastra, _refreshNearby no debe tocar los circulos:
        // clearCircles()+addCircle() recrea el pin con una identidad nueva a
        // mitad de gesto, y eso corta el arrastre de golpe.
        _draggingPendingPoint = true;
      case DragEventType.drag:
        break;
      case DragEventType.end:
        _draggingPendingPoint = false;
        setState(() => _pendingRoutePoint = current);
        _refreshNearby();
    }
  }

  // Se dispara al cargar el estilo la primera vez Y cada vez que se togglea
  // claro/oscuro (setStyle recarga el mapa y borra circulos/symbols/lineas
  // agregados en runtime, hay que volver a registrar todo).
  Future<void> _onStyleLoaded() async {
    await _registerReportIcons();
    if (!mounted) return;
    setState(() => _styleLoaded = true);
    await _refreshNearby();
    await _redrawRouteLines();
  }

  Future<void> _registerReportIcons() async {
    final controller = _mapController;
    if (controller == null) return;
    for (final type in reportTypes) {
      final bytes = await renderMarkerIcon(icon: type.icon, backgroundColor: type.color);
      await controller.addImage('report_${type.code}', bytes);
    }
    // Flecha de navegacion para "mi ubicacion" en modo de ruteo -- reemplaza
    // el circulo simple mientras hay una ruta activa, y rota segun el heading.
    final navBytes = await renderMarkerIcon(icon: Icons.navigation, backgroundColor: AppColors.azul);
    await controller.addImage('me_route', navBytes);

    // Pin de negocio patrocinado (ver migracion 0012) -- estrella dorada,
    // bien distinta de los iconos de reporte, para que no se confunda un
    // anuncio pagado con un incidente real.
    final sponsorBytes = await renderMarkerIcon(icon: Icons.star, backgroundColor: Colors.amber.shade700);
    await controller.addImage('sponsor_pin', sponsorBytes);
  }

  void _toggleMapStyle() => setState(() => _darkMap = !_darkMap);

  void _goToMyLocation() {
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_myPosition, 16));
  }

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
    } else if (data['type'] == 'sponsor') {
      _showSponsoredPinInfo(data['pin'] as SponsoredPin);
    }
  }

  Future<void> _showSponsoredPinInfo(SponsoredPin pin) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.star, color: Colors.amber),
            const SizedBox(width: 8),
            Expanded(child: Text(pin.businessName)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pin.category, style: const TextStyle(color: AppColors.grisUI)),
            if (pin.description != null && pin.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(pin.description!),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar')),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() => _pendingRoutePoint = LatLng(pin.lat, pin.lng));
              _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(pin.lat, pin.lng), 15));
              _refreshNearby();
            },
            icon: const Icon(Icons.directions, size: 18),
            label: const Text('Como llegar'),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshNearby() async {
    final controller = _mapController;
    if (controller == null || !_styleLoaded) return;
    if (_draggingPendingPoint) return;

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
      _supabase.rpc('nearby_sponsored_pins', params: {
        'lat': _myPosition.latitude,
        'lng': _myPosition.longitude,
      }),
    ]);

    final users = (results[0] as List).map((e) => NearbyUser.fromJson(e as Map<String, dynamic>)).toList();
    final reports = (results[1] as List).map((e) => ReportItem.fromJson(e as Map<String, dynamic>)).toList();
    final friends = (results[2] as List).map((e) => FriendLocation.fromJson(e as Map<String, dynamic>)).toList();
    final friendIds = friends.map((f) => f.userId).toSet();
    final sponsoredPins =
        (results[3] as List).map((e) => SponsoredPin.fromJson(e as Map<String, dynamic>)).toList();

    await controller.clearCircles();
    await controller.clearSymbols();

    final circleOptions = <CircleOptions>[];
    final circleData = <Map<String, dynamic>>[];

    // Mi propia posicion (ya enganchada a la calle). Se dibuja como circulo
    // propio en vez de usar el punto azul nativo de MapLibre (myLocationEnabled),
    // porque ese indicador nativo pinta la posicion cruda del GPS, no la snapeada.
    // En modo de ruteo se reemplaza por una flecha de navegacion que rota
    // segun el heading, como el "puck" de Waze -- eso va como Symbol, no
    // circulo, y se agrega mas abajo junto con los demas symbols.
    if (_activeRoute == null) {
      circleOptions.add(CircleOptions(
        geometry: _myPosition,
        circleColor: '#3B82F6',
        circleRadius: 9,
        circleStrokeColor: '#ffffff',
        circleStrokeWidth: 3,
      ));
      circleData.add({'type': 'me'});
    }

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
      circleData.add({'type': 'friend', 'nombres': f.displayName});
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
        // La busqueda de direcciones no siempre es precisa (sin numero de
        // puerta, ver notas en el dashboard web) -- el usuario puede arrastrar
        // el pin de destino a la ubicacion exacta antes de iniciar la ruta.
        draggable: true,
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

    // Negocios patrocinados: estrella dorada, bien distinta de los reportes
    // (son contenido pagado por un negocio, no un incidente reportado por
    // otro conductor).
    for (final p in sponsoredPins) {
      await controller.addSymbol(
        SymbolOptions(
          geometry: LatLng(p.lat, p.lng),
          iconImage: 'sponsor_pin',
          iconSize: 0.5,
        ),
        {'type': 'sponsor', 'pin': p},
      );
    }

    if (_activeRoute != null) {
      await controller.addSymbol(
        SymbolOptions(
          geometry: _myPosition,
          iconImage: 'me_route',
          iconSize: 0.5,
          iconRotate: _heading ?? 0,
        ),
        {'type': 'me'},
      );
    }
  }

  Future<void> _showVoteDialog(ReportItem report) async {
    final info = reportTypeByCode(report.typeCode);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Expanded(child: Text(info.label)),
            Icon(info.icon, color: info.color),
          ],
        ),
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
    // El pin que quedo listo al tapear el mapa (ver _onMapTapped) es donde se
    // crea el reporte; si no tapeaste ningun punto todavia, se reporta en tu
    // posicion actual (comportamiento anterior, sigue funcionando igual).
    final reportPoint = _pendingRoutePoint ?? _myPosition;
    final distance = GeoUtils.distanceMeters(_myPosition, reportPoint);
    if (distance > _reportMaxDistanceMeters) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Solo podes reportar dentro de un radio de 10km de tu ubicacion actual.'),
        ),
      );
      return;
    }

    await showReportSheet(context, (typeCode, comment) async {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      await _supabase.from('reports').insert({
        'user_id': userId,
        'type_code': typeCode,
        'geom': 'POINT(${reportPoint.longitude} ${reportPoint.latitude})',
        'comment': comment,
      });
      _refreshNearby();
    });
  }

  // Mantener presionado cualquier punto del mapa deja un pin listo ahi: sirve tanto para
  // "Iniciar ruta"/"Guardar ruta" (sin limite de distancia) como para crear
  // un reporte en ese punto exacto (con el limite de arriba). Tambien
  // rellena el buscador con la direccion de ese punto (geocoding inverso),
  // igual que si lo hubieras buscado a mano.
  Future<void> _onMapTapped(Point<double> point, LatLng coordinates) async {
    setState(() {
      _pendingRoutePoint = coordinates;
      _suggestions = [];
    });
    _refreshNearby();
    FocusScope.of(context).unfocus();

    final address = await _reverseGeocode(coordinates);
    if (!mounted) return;
    _searchCtrl.text = address ?? 'Ubicacion seleccionada';
  }

  Future<String?> _reverseGeocode(LatLng point) async {
    if (Env.maptilerKey.isEmpty) return null;
    try {
      final uri = Uri.parse(
        'https://api.maptiler.com/geocoding/${point.longitude},${point.latitude}.json'
        '?key=${Env.maptilerKey}&language=es&limit=1',
      );
      final res = await http.get(uri);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final features = (data['features'] as List?) ?? [];
      if (features.isEmpty) return null;
      return features.first['place_name'] as String?;
    } catch (_) {
      return null;
    }
  }

  String _formatTripDistance(double meters) =>
      meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1)} km' : '${meters.round()} m';

  String _formatTripDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    if (minutes < 60) return '$minutes:${secs.toString().padLeft(2, '0')} min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return '${hours}h ${rest}min';
  }

  Future<void> _redrawTripLine() async {
    final controller = _mapController;
    if (controller == null || _tripPoints.length < 2) return;
    await controller.clearLines();
    await controller.addLine(LineOptions(geometry: _tripPoints, lineColor: '#EF4444', lineWidth: 5));
  }

  void _startTrip() {
    if (_routeOptions.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sali del modo de ruteo antes de grabar un trayecto.')),
      );
      return;
    }
    setState(() {
      _recordingTrip = true;
      _tripPoints
        ..clear()
        ..add(_myPosition);
      _tripDistanceMeters = 0;
      _tripStartedAt = DateTime.now();
    });
    // Solo para refrescar el reloj en pantalla cada segundo -- la distancia
    // se suma aparte, en cada lectura real de GPS (ver _onOwnPosition).
    _tripTicker?.cancel();
    _tripTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _stopTrip() async {
    _tripTicker?.cancel();
    _tripTicker = null;
    final origin = _tripPoints.isNotEmpty ? _tripPoints.first : _myPosition;
    final destination = _myPosition;
    final distance = _tripDistanceMeters;
    final duration = _tripStartedAt == null ? 0 : DateTime.now().difference(_tripStartedAt!).inSeconds;

    await _mapController?.clearLines();
    setState(() {
      _recordingTrip = false;
      _tripPoints.clear();
      _tripDistanceMeters = 0;
      _tripStartedAt = null;
    });

    // Trayecto demasiado corto (ej. tocaste el boton por error): no tiene
    // sentido ofrecer guardarlo.
    if (distance < 50 || !mounted) return;

    final wantsSave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trayecto detenido'),
        content: Text(
          'Recorriste ${_formatTripDistance(distance)} en ${_formatTripDuration(duration)}.\n\n'
          'Deseas guardar este trayecto en tus rutas frecuentes?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Guardar')),
        ],
      ),
    );
    if (wantsSave != true || !mounted) return;

    final nameCtrl = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guardar trayecto'),
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
      'origen_lat': origin.latitude,
      'origen_lng': origin.longitude,
      'destino_lat': destination.latitude,
      'destino_lng': destination.longitude,
      'distance_meters': distance,
      'duration_seconds': duration,
      'recorded': true,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trayecto guardado en tus rutas frecuentes.')),
      );
    }
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
    if (_recordingTrip) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deten el trayecto que estas grabando antes de iniciar una ruta.')),
      );
      return;
    }
    setState(() => _startingRoute = true);
    final routes = await OsrmService.getRoutes(_myPosition, destination);
    if (!mounted) return;

    if (routes.isEmpty) {
      setState(() => _startingRoute = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo calcular la ruta. Probá de nuevo.')),
      );
      return;
    }

    await _scoreRouteOptions(routes);
    // La de menor puntaje (mas rapida, penalizada por reportes cercanos)
    // queda primera y se selecciona como recomendada por defecto.
    routes.sort((a, b) => a.score.compareTo(b.score));
    if (!mounted) return;

    setState(() {
      _routeOptions = routes;
      _activeRouteIndex = 0;
      _routeDestination = destination;
      _startingRoute = false;
    });
    _resetVoiceGuidance(routes[0], announceStart: true);
    await _redrawRouteLines();
  }

  Future<void> _exitRoute() async {
    await _mapController?.clearLines();
    _stopVoiceGuidance();
    setState(() {
      _routeOptions = [];
      _activeRouteIndex = 0;
      _routeDestination = null;
      _lastRerouteAt = null;
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

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    setState(() => _suggestions = []);
    FocusScope.of(context).unfocus();
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
    _voiceGuidanceTimer?.cancel();
    _tripTicker?.cancel();
    _channel?.unsubscribe();
    MapCameraController.target.removeListener(_onExternalCameraTarget);
    MapCameraController.pendingRouteTarget.removeListener(_onExternalPendingRoute);
    _tts.stop();
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
            // Long press, no tap simple: un tap corto ya se usa para
            // interactuar con lo que esta en el mapa (ver/votar un reporte,
            // ver info de un amigo) -- los iconos de reporte son chicos, y
            // con tap simple un toque que no cae justo en el icono se
            // interpretaba como "map click libre" y movia el pin ahi en vez
            // de abrir el reporte. Long press no tiene esa ambiguedad.
            onMapLongClick: _onMapTapped,
            // Orden de abajo hacia arriba: symbol (iconos de reportes) al
            // final para que queden ARRIBA de los circulos -- si reportas
            // justo donde estas, tu propio punto azul (un circulo) no debe
            // tapar el icono del reporte que acabas de crear en el mismo lugar.
            annotationOrder: const [
              AnnotationType.line,
              AnnotationType.fill,
              AnnotationType.circle,
              AnnotationType.symbol,
            ],
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
                        // Solo aparece si hay texto escrito, para limpiar y
                        // poder hacer otra busqueda sin borrar letra por letra.
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _searchCtrl,
                          builder: (context, value, _) {
                            if (value.text.isEmpty) return const SizedBox.shrink();
                            return IconButton(
                              icon: const Icon(Icons.close, color: AppColors.grisUI, size: 20),
                              onPressed: _clearSearch,
                              tooltip: 'Limpiar busqueda',
                            );
                          },
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
          // Boton "mi ubicacion", debajo de la barra de busqueda (fuera de esa
          // caja), alineado con el icono de tema claro/oscuro que esta arriba.
          Positioned(
            top: MediaQuery.of(context).padding.top + 76,
            right: 16,
            child: Material(
              color: const Color(0xFF111C30),
              shape: const CircleBorder(),
              elevation: 4,
              child: IconButton(
                icon: const Icon(Icons.my_location, color: AppColors.azul),
                onPressed: _goToMyLocation,
                tooltip: 'Mi ubicacion',
              ),
            ),
          ),
          // "Iniciar trayecto": graba el camino real mientras manejas (sin
          // destino fijo), a diferencia de "Iniciar ruta" que necesita un
          // destino elegido de antemano.
          if (!_recordingTrip)
            Positioned(
              top: MediaQuery.of(context).padding.top + 132,
              right: 16,
              child: Material(
                color: const Color(0xFF111C30),
                shape: const CircleBorder(),
                elevation: 4,
                child: IconButton(
                  icon: const Icon(Icons.fiber_manual_record, color: Colors.redAccent),
                  onPressed: _startTrip,
                  tooltip: 'Iniciar trayecto',
                ),
              ),
            ),
          if (_recordingTrip)
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
                      const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 14),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${_formatTripDistance(_tripDistanceMeters)} · '
                          '${_formatTripDuration(_tripStartedAt == null ? 0 : DateTime.now().difference(_tripStartedAt!).inSeconds)}',
                          style: const TextStyle(color: AppColors.textoClaro, fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton(
                        onPressed: _stopTrip,
                        child: const Text('Detener trayecto', style: TextStyle(color: Colors.redAccent)),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_activeRoute != null)
            Positioned(
              bottom: 90,
              left: 16,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Chips de alternativas: solo aparecen si OSRM devolvio mas
                  // de 1 ruta. Tocar una la cambia (mismo efecto que tocar la
                  // linea gris en el mapa).
                  if (_routeOptions.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _routeOptions.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final r = _routeOptions[i];
                            final active = i == _activeRouteIndex;
                            return ChoiceChip(
                              selected: active,
                              onSelected: (_) => _selectRouteOption(i),
                              label: Text(
                                r.impactfulReportCount == 0
                                    ? '${r.durationLabel} · libre'
                                    : '${r.durationLabel} · ${r.impactfulReportCount} reporte${r.impactfulReportCount > 1 ? 's' : ''}',
                              ),
                              avatar: Icon(
                                r.impactfulReportCount == 0 ? Icons.check_circle : Icons.report_problem,
                                size: 16,
                                color: r.impactfulReportCount == 0 ? AppColors.verde : Colors.orangeAccent,
                              ),
                              selectedColor: AppColors.azul,
                              backgroundColor: const Color(0xFF111C30),
                              labelStyle: TextStyle(
                                color: active ? Colors.white : AppColors.textoClaro,
                                fontSize: 12,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  Material(
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
                ],
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
          // Positioned directo (no Scaffold.floatingActionButton): el margen
          // por defecto (16px) tapaba el icono "i" de atribucion/copyright de
          // MapTiler en la esquina inferior derecha -- sus terminos de uso
          // exigen que ese icono quede siempre visible, asi que el FAB se
          // sube lo suficiente para no superponerse.
          Positioned(
            bottom: 56,
            right: 16,
            child: FloatingActionButton(
              onPressed: _createReport,
              child: const Icon(Icons.add_location_alt),
            ),
          ),
        ],
      ),
    );
  }
}
