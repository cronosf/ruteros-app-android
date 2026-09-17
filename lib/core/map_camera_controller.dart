import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// Notifica al mapa que debe centrarse en un punto, o reabrir una ruta
/// guardada como destino pendiente (ej. desde la pestana Perfil -> Mis
/// rutas). Un ValueNotifier global simple en vez de un paquete de state
/// management completo, ya que es el unico estado que se comparte entre
/// pantallas fuera del bottom nav.
class MapCameraController {
  MapCameraController._();

  static final ValueNotifier<LatLng?> target = ValueNotifier<LatLng?>(null);
  static void moveTo(LatLng point) => target.value = point;

  // Reabre una ruta guardada: pone el pin de destino ahi (mismo estado que
  // deja una busqueda) para que el usuario pueda tocar "Iniciar ruta" de
  // nuevo desde su posicion actual.
  static final ValueNotifier<LatLng?> pendingRouteTarget = ValueNotifier<LatLng?>(null);
  static void openSavedRoute(LatLng destination) => pendingRouteTarget.value = destination;
}
