import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// Notifica al mapa que debe centrarse en un punto (ej. al abrir una ruta
/// guardada desde la pestana Perfil). Un ValueNotifier global simple en vez de
/// un paquete de state management completo, ya que es el unico estado que se
/// comparte entre pantallas fuera del bottom nav.
class MapCameraController {
  MapCameraController._();
  static final ValueNotifier<LatLng?> target = ValueNotifier<LatLng?>(null);

  static void moveTo(LatLng point) => target.value = point;
}
