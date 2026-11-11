import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Marcador del bus: el mismo cuadro amarillo con el bus negro de la pantalla
/// de inicio, dibujado a un `BitmapDescriptor` para usarlo como icono en
/// Google Maps.
///
/// Se dibuja en vez de usar una imagen del bundle para que escale nítido en
/// cualquier densidad de pantalla y para no depender de un asset más.
///
/// El resultado se memoiza: `BitmapDescriptor` es inmutable y el dibujado
/// implica `toImage`, que es costoso. Llamar a [iconoBus] muchas veces (una por
/// reconstrucción de la pantalla del mapa) devuelve siempre el mismo objeto.
class BusMarker {
  BusMarker._();

  static const Color _amarillo = Color(0xFFFDB913);
  static const Color _negro = Color(0xFF1A1A1A);

  static BitmapDescriptor? _cache;

  /// Resolución del lienzo en px. Se dibuja grande y Google lo reduce, para
  /// que el borde quede nítido en pantallas de alta densidad.
  static const int _tamanioBitmap = 120;

  /// Tamaño real que ocupa el marcador sobre el mapa, en **píxeles lógicos
  /// (dp)**, no en px del lienzo.
  ///
  /// Es lo que controla que el icono no se vea gigante. Antes se pasaba
  /// `width: 120` (el tamaño del lienzo), y así el bus medía 120 dp: tapaba el
  /// mapa en vez de señalar el punto. Con 40 dp queda del tamaño de un pin
  /// normal y todavía se distingue el dibujo.
  static const double _tamanioMapa = 40;

  /// Aro blanco alrededor del cuadro amarillo: sobre las etiquetas de Google
  /// Maps (que son claras) el amarillo solo se pierde sin un borde.
  static const double _relacionBorde = 0.06;

  static Future<BitmapDescriptor> iconoBus() async {
    final BitmapDescriptor? cacheado = _cache;
    if (cacheado != null) return cacheado;

    final ui.PictureRecorder grabador = ui.PictureRecorder();
    final Canvas canvas = Canvas(grabador);
    final double t = _tamanioBitmap.toDouble();
    final double borde = t * _relacionBorde;

    // Cuadro redondeado con sombra suave, como la tarjeta del logo. La sombra
    // se desplaza un poco hacia abajo y se difumina.
    final RRect cuadro = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, t, t),
      Radius.circular(t * 0.26),
    );
    canvas.drawRRect(
      cuadro.shift(Offset(0, t * 0.03)),
      Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 5),
    );
    canvas.drawRRect(cuadro, Paint()..color = Colors.white);
    canvas.drawRRect(cuadro.deflate(borde), Paint()..color = _amarillo);

    // El icono de bus se pinta con la fuente MaterialIcons (incluida por
    // `uses-material-design: true`), centrado en el cuadro.
    final TextPainter pintor = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(Icons.directions_bus_filled.codePoint),
        style: TextStyle(
          fontSize: t * 0.54,
          fontFamily: Icons.directions_bus_filled.fontFamily,
          package: Icons.directions_bus_filled.fontPackage,
          color: _negro,
        ),
      )
      ..layout();
    pintor.paint(
      canvas,
      Offset((t - pintor.width) / 2, (t - pintor.height) / 2),
    );

    final ui.Image imagen = await grabador.endRecording().toImage(
          _tamanioBitmap,
          _tamanioBitmap,
        );
    final ByteData? bytes = await imagen.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (bytes == null) return BitmapDescriptor.defaultMarker;

    final BitmapDescriptor descriptor = BitmapDescriptor.bytes(
      bytes.buffer.asUint8List(),
      width: _tamanioMapa,
      height: _tamanioMapa,
    );
    _cache = descriptor;
    return descriptor;
  }
}
