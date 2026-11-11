import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

/// Ruta calculada por el motor de direcciones: la polilínea a dibujar y los
/// totales que se muestran en pantalla.
class RutaCalculada {
  const RutaCalculada({
    required this.puntos,
    required this.distanciaMetros,
    required this.duracionSegundos,
  });

  /// Vértices de la polilínea, en orden de recorrido.
  final List<LatLng> puntos;

  final double distanciaMetros;
  final double duracionSegundos;

  /// "12 min" o "1 h 5 min", para mostrar el tiempo estimado al siguiente
  /// punto sin que el conductor tenga que interpretar segundos.
  String get duracionLegible {
    final int minutos = (duracionSegundos / 60).round();
    if (minutos < 60) return '$minutos min';
    final int horas = minutos ~/ 60;
    final int resto = minutos % 60;
    return resto == 0 ? '$horas h' : '$horas h $resto min';
  }
}

/// Calcula el camino entre puntos con OSRM (OpenStreetMap), el motor de rutas
/// gratuito del proyecto.
///
/// Se eligió OSRM sobre Google Directions a propósito: Directions exige activar
/// facturación en Google Cloud, y este proyecto ya decidió no pagar APIs de
/// Google más allá del mapa. OSRM devuelve la misma polilínea sin key ni cuenta.
///
/// La geometría se pide en GeoJSON (`geometries=geojson`) y no en el formato
/// `polyline` comprimido: así el parseo es JSON plano y no hay que decodificar
/// el algoritmo de Google.
class RouteService {
  static const String _base =
      'https://router.project-osrm.org/route/v1/driving/';

  /// OSRM es un servicio público ajeno; igual que con cualquier API pública, un
  /// `User-Agent` de navegador evita que la petición se rechace por venir de
  /// `dart:io`.
  static const String _userAgent =
      'Mozilla/5.0 (compatible; BusTrackApp/1.0; seguimiento escolar)';

  Future<RutaCalculada?> calcular(List<LatLng> puntos) async {
    if (puntos.length < 2) return null;

    // OSRM espera cada punto como `lng,lat`, separados por `;`.
    final String coordenadas =
        puntos.map((p) => '${p.longitude},${p.latitude}').join(';');
    final Uri uri = Uri.parse(
      '$_base$coordenadas?overview=full&geometries=geojson',
    );

    try {
      final http.Response respuesta = await http
          .get(uri, headers: const {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 12));
      if (respuesta.statusCode != 200) return null;
      return parsear(respuesta.body);
    } catch (e) {
      // Sin red o servidor caído: la pantalla muestra el mapa sin la línea en
      // vez de romperse.
      debugPrint('RouteService: no se pudo calcular la ruta: $e');
      return null;
    }
  }

  /// Convierte la respuesta de OSRM en [RutaCalculada]. `static` y visible para
  /// test para poder verificar el parseo con una respuesta real guardada, sin
  /// red.
  @visibleForTesting
  static RutaCalculada? parsear(String cuerpo) {
    try {
      final dynamic decodificado = jsonDecode(cuerpo);
      if (decodificado is! Map<String, dynamic>) return null;

      final dynamic rutas = decodificado['routes'];
      if (rutas is! List || rutas.isEmpty) return null;

      final Map<String, dynamic> ruta = rutas.first as Map<String, dynamic>;
      final dynamic geometria = ruta['geometry'];
      if (geometria is! Map<String, dynamic>) return null;

      final dynamic coordenadas = geometria['coordinates'];
      if (coordenadas is! List) return null;

      final List<LatLng> puntos = <LatLng>[];
      for (final dynamic c in coordenadas) {
        if (c is List && c.length >= 2 && c[0] is num && c[1] is num) {
          // GeoJSON es [lng, lat]; LatLng quiere (lat, lng).
          puntos.add(
            LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
          );
        }
      }
      if (puntos.isEmpty) return null;

      return RutaCalculada(
        puntos: puntos,
        distanciaMetros: (ruta['distance'] as num?)?.toDouble() ?? 0,
        duracionSegundos: (ruta['duration'] as num?)?.toDouble() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}
