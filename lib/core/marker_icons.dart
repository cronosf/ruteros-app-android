import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Genera un bitmap PNG en memoria (circulo de color + el glyph de un
/// IconData de Material Icons encima) para usarlo como icono de Symbol en el
/// mapa -- maplibre_gl necesita bytes de imagen via `addImage`, no un
/// IconData directamente. Evita depender de assets externos: los iconos son
/// genericos (no insignias oficiales de PNP/ATU), generados en runtime.
Future<Uint8List> renderMarkerIcon({
  required IconData icon,
  required Color backgroundColor,
  double size = 96,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
  final center = Offset(size / 2, size / 2);
  final radius = size / 2;

  canvas.drawCircle(center, radius, Paint()..color = backgroundColor);
  canvas.drawCircle(
    center,
    radius - 2,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3,
  );

  final textPainter = TextPainter(textDirection: TextDirection.ltr)
    ..text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: size * 0.55,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: Colors.white,
      ),
    )
    ..layout();
  textPainter.paint(
    canvas,
    Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}
