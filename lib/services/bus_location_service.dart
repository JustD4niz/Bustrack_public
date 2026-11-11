import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Publica la posición GPS del conductor en `buses/{placa}`.
///
/// Campos que escribe (el panel del padre ya espera `velocidad` y
/// `ultimaActualizacion`, ver `parent_vehiculo_view.dart`):
///
/// - `lat`, `lng`: posición actual.
/// - `ultimaLat`, `ultimaLng`: última posición conocida; no se borra al
///   finalizar la ruta, para que el mapa abra donde quedó el bus.
/// - `rumbo`: dirección en grados (0-360), para girar el icono del bus.
/// - `velocidad`: km/h.
/// - `precision`: error estimado en metros.
/// - `ultimaActualizacion`: sello del servidor, para saber qué tan fresca es
///   la señal.
/// - `gpsOrigen`: `inicial`, `stream` o `sondeo`. Es solo de diagnóstico: dice
///   por qué camino llegó la última posición (ver [_sondear]).
///
/// Dos caminos alimentan la posición:
///
/// 1. El stream de `Geolocator.getPositionStream` (el normal).
/// 2. Un "vigilante" ([_vigilante]) que, si el stream lleva callado más de
///    [_silencioMaximo], pide la posición a mano con `getCurrentPosition`. Se
///    añadió porque en una prueba real (2 km caminando) el stream no entregó
///    posiciones nuevas, y la única forma de ver al bus moverse era apagar y
///    volver a encender la ruta (que sí llama a `getCurrentPosition`).
///
/// Se escribe como máximo cada [_intervaloPara] (según la velocidad) para no
/// gastar escrituras de Firestore ni batería: un bus detenido no necesita
/// publicar cada segundo. El stream sigue recibiendo posiciones cada segundo,
/// así que el marcador no se queda dormido cuando el bus arranca.
///
/// ## `error` y `advertencia` no son lo mismo
///
/// Antes [iniciar] devolvía un único mensaje y quien llamaba lo trataba como
/// fallo. Eso hacía que negar el permiso de **notificaciones** (que solo afecta
/// al aviso del servicio en primer plano) marcara la ruta como no iniciada:
/// el bus ya estaba `enMovimiento: true`, el padre veía la ruta, pero el
/// conductor no tenía "Ya recogí" ni "Finalizar Ruta". Un [AvisoGps] separa las
/// dos cosas.
class AvisoGps {
  const AvisoGps({this.error, this.advertencia});

  /// Impide compartir la ubicación (sin GPS o sin permiso de ubicación).
  final String? error;

  /// La ubicación sí se comparte; esto solo avisa de algo que puede degradarla.
  final String? advertencia;

  bool get ok => error == null;
}

class BusLocationService {
  /// Ritmo de escritura según la velocidad (km/h).
  ///
  /// El GPS del teléfono entrega posiciones cada segundo, pero publicar cada
  /// una es caro: gasta batería, datos y escrituras de Firestore, y un bus
  /// parado en el colegio no cambia de sitio. Se publica lento cuando está
  /// detenido y rápido cuando se mueve:
  ///
  /// - menos de 2 km/h (detenido): cada 5 s.
  /// - entre 2 y 25 km/h (tráfico urbano): cada 2 s.
  /// - más de 25 km/h (carretera): cada 1 s.
  static Duration _intervaloPara(double kmh) {
    if (kmh < 2) return const Duration(seconds: 5);
    if (kmh < 25) return const Duration(seconds: 2);
    return const Duration(seconds: 1);
  }

  /// Cada cuánto despierta el vigilante.
  static const Duration _periodoVigilante = Duration(seconds: 1);

  /// Si pasó más que esto sin **recibir** una posición, el stream se considera
  /// caído. Se mide contra la última recepción, no contra la última escritura:
  /// con el intervalo adaptativo un bus detenido puede pasar 5 s sin publicar y
  /// no por eso está desconectado.
  static const Duration _silencioMaximo = Duration(seconds: 3);

  StreamSubscription<Position>? _suscripcion;
  Timer? _vigilante;
  bool _sondeando = false;
  String? _placa;
  DateTime _ultimoEnvio = DateTime.fromMillisecondsSinceEpoch(0);

  /// Momento en que se **recibió** la última posición, se publicara o no. Es lo
  /// que usa el vigilante para saber si el stream sigue vivo.
  DateTime _ultimaActividad = DateTime.fromMillisecondsSinceEpoch(0);

  /// `true` mientras se está compartiendo la ubicación.
  bool get activo => _suscripcion != null;

  /// Revisa GPS y permisos. Devuelve un mensaje para el usuario si algo falta,
  /// o `null` si todo está listo.
  ///
  /// El permiso de **notificaciones** se pide aquí, pero no es un requisito:
  /// se devuelve aparte en [iniciar] como advertencia.
  static Future<String?> verificarPermisos() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Activa el GPS del teléfono para compartir tu ubicación.';
    }

    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }

    if (permiso == LocationPermission.denied) {
      return 'Necesitamos el permiso de ubicación para que los padres '
          'puedan ver el bus.';
    }
    if (permiso == LocationPermission.deniedForever) {
      return 'El permiso de ubicación está bloqueado. Actívalo desde los '
          'ajustes de la app.';
    }

    return null;
  }

  /// Pide el permiso de notificaciones (Android 13+) y devuelve una advertencia
  /// si se negó. **No** es un error: el GPS funciona igual, solo se pierde el
  /// aviso del servicio en primer plano.
  static Future<String?> advertenciaNotificaciones() async {
    final notificaciones = await Permission.notification.request();
    if (!notificaciones.isGranted &&
        defaultTargetPlatform == TargetPlatform.android) {
      return 'Sin notificaciones, el teléfono puede cortar el seguimiento '
          'cuando bloqueas la pantalla.';
    }
    return null;
  }

  LocationSettings _ajustes() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        // `distanceFilter: 0` hace que `intervalDuration` mande: con un filtro
        // por distancia, un bus detenido no emitía ninguna posición y el padre
        // veía el marcador congelado en el último punto. A 0, la posición se
        // refresca cada 1 s aunque el bus esté parado en una parada.
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        // Servicio en primer plano: sin esto Android corta el GPS cuando el
        // conductor bloquea la pantalla o cambia de app. La notificación
        // tiene que ser visible para que el sistema no mate el servicio.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'BusTrack',
          notificationText:
              'Compartiendo tu ruta en tiempo real con los padres',
          notificationChannelName: 'Seguimiento de ruta',
          setOngoing: true,
          enableWakeLock: true,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
    );
  }

  /// Empieza a compartir la posición del bus [placa].
  ///
  /// [AvisoGps.error] solo se llena si de verdad no se puede compartir (sin GPS
  /// o sin permiso de ubicación). Negar las notificaciones queda en
  /// [AvisoGps.advertencia] y la ruta sigue siendo válida.
  Future<AvisoGps> iniciar(String placa) async {
    final error = await verificarPermisos();
    if (error != null) return AvisoGps(error: error);

    final advertencia = await advertenciaNotificaciones();

    await _suscripcion?.cancel();
    _vigilante?.cancel();
    _placa = placa;
    _ultimoEnvio = DateTime.fromMillisecondsSinceEpoch(0);
    _ultimaActividad = DateTime.now();

    _suscripcion = Geolocator.getPositionStream(locationSettings: _ajustes())
        .listen(
      (p) {
        _ultimaActividad = DateTime.now();
        _publicar(p, origen: 'stream');
      },
      onError: (Object e) {
        debugPrint('BusLocationService: error de GPS: $e');
      },
    );
    debugPrint('BusLocationService: stream GPS activado, placa=$placa, '
        'settings=${_ajustes().runtimeType}');

    // Primera posición inmediata, para que el padre vea el bus sin esperar al
    // primer evento del stream.
    try {
      final inicial = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      await _publicar(inicial, forzar: true, origen: 'inicial');
    } catch (e) {
      debugPrint('BusLocationService: sin posición inicial: $e');
    }

    // El vigilante arranca después de la posición inicial, para no competir
    // con ella.
    _vigilante = Timer.periodic(_periodoVigilante, (_) => _sondear());
    return AvisoGps(advertencia: advertencia);
  }

  /// Respaldo del stream: si lleva más de [_silencioMaximo] sin **recibir**
  /// posiciones, pide la ubicación con `getCurrentPosition` y la publica.
  /// Con el stream sano nunca llega a actuar (siempre hay una recepción
  /// reciente), así que no duplica escrituras.
  Future<void> _sondear() async {
    if (_placa == null || _sondeando) return;
    if (DateTime.now().difference(_ultimaActividad) < _silencioMaximo) return;

    _sondeando = true;
    try {
      debugPrint('BusLocationService: el stream lleva callado, sondeando...');
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      await _publicar(p, forzar: true, origen: 'sondeo');
    } catch (e) {
      debugPrint('BusLocationService: falló el sondeo: $e');
    } finally {
      _sondeando = false;
    }
  }

  Future<void> _publicar(
    Position p, {
    bool forzar = false,
    required String origen,
  }) async {
    final placa = _placa;
    if (placa == null) return;

    final ahora = DateTime.now();
    _ultimaActividad = ahora;

    // `speed` viene en m/s y puede ser negativo si el sensor no tiene dato.
    final kmh = p.speed.isNaN || p.speed < 0 ? 0.0 : p.speed * 3.6;

    // Detenido se publica menos seguido; en movimiento, casi en vivo. El
    // forzado (posición inicial y sondeo) siempre escribe.
    if (!forzar && ahora.difference(_ultimoEnvio) < _intervaloPara(kmh)) {
      return;
    }
    _ultimoEnvio = ahora;

    debugPrint('BusLocationService: GPS ($origen) -> placa=$placa, '
        'lat=${p.latitude}, lng=${p.longitude}, heading=${p.heading}, '
        'vel=${kmh.toStringAsFixed(1)}km/h, acc=${p.accuracy}, '
        'ts=${ahora.toIso8601String()}');

    try {
      await FirebaseFirestore.instance.collection('buses').doc(placa).set({
        'lat': p.latitude,
        'lng': p.longitude,
        // Última posición conocida, que **no** se borra al finalizar la ruta.
        // `lat`/`lng` se limpian para que el padre deje de ver el bus cuando el
        // viaje cierra; estos dos se conservan para que el mapa abra donde
        // quedó el bus la última vez y no en un centro por defecto.
        'ultimaLat': p.latitude,
        'ultimaLng': p.longitude,
        'rumbo': p.heading.isNaN || p.heading < 0 ? 0.0 : p.heading,
        'velocidad': double.parse(kmh.toStringAsFixed(1)),
        'precision': p.accuracy,
        'ultimaActualizacion': FieldValue.serverTimestamp(),
        'gpsOrigen': origen,
      }, SetOptions(merge: true));
      debugPrint('BusLocationService: Firestore actualizado OK -> buses/$placa');
    } catch (e, st) {
      // Sin internet o sin permisos de Firestore: se reintenta con la
      // siguiente posición, no se rompe la sesión del conductor.
      debugPrint('BusLocationService: ERROR al publicar buses/$placa: $e');
      debugPrint('$st');
    }
  }

  /// Deja de compartir. Con [marcarDetenido] también avisa a los padres de que
  /// el bus ya no está en ruta.
  Future<void> detener({bool marcarDetenido = true}) async {
    _vigilante?.cancel();
    _vigilante = null;
    await _suscripcion?.cancel();
    _suscripcion = null;
    debugPrint('BusLocationService: stream detenido, placa=$_placa');

    final placa = _placa;
    _placa = null;
    if (placa == null || !marcarDetenido) return;

    try {
      await FirebaseFirestore.instance.collection('buses').doc(placa).set({
        'enMovimiento': false,
        'estadoRuta': 'Ruta finalizada',
        'velocidad': 0,
        'ultimaActualizacion': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('BusLocationService: no se pudo marcar el bus detenido: $e');
    }
  }
}
