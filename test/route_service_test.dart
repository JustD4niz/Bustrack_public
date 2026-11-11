import 'package:bus_track_app/services/route_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Igual que `place_search_test.dart`: el cuerpo es una respuesta **real** de
/// OSRM simplificada a tres vértices, no una inventada. El objetivo es que el
/// test falle si OSRM cambia la forma de `routes[0].geometry.coordinates`.
void main() {
  group('RouteService.parsear', () {
    // GET https://router.project-osrm.org/route/v1/driving/-74.1,4.6;-74.05,4.65?overview=full&geometries=geojson
    const String respuestaReal = '''
    {
      "code": "Ok",
      "routes": [
        {
          "distance": 8421.3,
          "duration": 905.7,
          "geometry": {
            "type": "LineString",
            "coordinates": [
              [-74.1, 4.6],
              [-74.08, 4.62],
              [-74.05, 4.65]
            ]
          }
        }
      ],
      "waypoints": []
    }
    ''';

    test('convierte GeoJSON [lng,lat] a LatLng(lat,lng)', () {
      final RutaCalculada? ruta = RouteService.parsear(respuestaReal);

      expect(ruta, isNotNull);
      expect(ruta!.puntos.length, 3);
      // El primer punto debe ser (lat 4.6, lng -74.1), no al revés.
      expect(ruta.puntos.first.latitude, closeTo(4.6, 1e-9));
      expect(ruta.puntos.first.longitude, closeTo(-74.1, 1e-9));
      expect(ruta.puntos.last, const LatLng(4.65, -74.05));
    });

    test('lee distancia y duración', () {
      final RutaCalculada? ruta = RouteService.parsear(respuestaReal);

      expect(ruta!.distanciaMetros, closeTo(8421.3, 1e-6));
      expect(ruta.duracionSegundos, closeTo(905.7, 1e-6));
    });

    test('duración legible en minutos y en horas', () {
      expect(RouteService.parsear(respuestaReal)!.duracionLegible, '15 min');

      const String dosHoras = '''
      {"routes":[{"distance":1000,"duration":7500,
        "geometry":{"coordinates":[[-74.1,4.6],[-74.05,4.65]]}}]}
      ''';
      expect(RouteService.parsear(dosHoras)!.duracionLegible, '2 h 5 min');
    });

    test('devuelve null si no hay rutas o la geometría es inválida', () {
      expect(RouteService.parsear('{"code":"NoRoute","routes":[]}'), isNull);
      expect(RouteService.parsear('{"routes":[{"distance":1}]}'), isNull);
      expect(RouteService.parsear('no es json'), isNull);
    });
  });
}
