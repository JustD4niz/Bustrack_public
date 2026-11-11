import 'package:geolocator/geolocator.dart';

/// Estado del permiso de ubicación, con el mensaje que se le muestra al usuario.
enum PermisoUbicacion {
  /// Hay GPS encendido y permiso concedido.
  concedido,

  /// El usuario apagó la ubicación del teléfono.
  sinServicio,

  /// Dijo que no en el diálogo del sistema; se le puede volver a preguntar.
  denegado,

  /// Permiso de ubicación bloqueado para siempre: solo se arregla en ajustes.
  bloqueado;

  /// Mensaje para el usuario, ya en español.
  String get mensaje => switch (this) {
        PermisoUbicacion.concedido => '',
        PermisoUbicacion.sinServicio =>
          'Activa la ubicación (GPS) del teléfono para buscar dónde estás.',
        PermisoUbicacion.denegado =>
          'Necesitamos permiso de ubicación para llevarte a tu posición. '
              'Toca "Mi ubicación" otra vez y acepta el permiso.',
        PermisoUbicacion.bloqueado =>
          'El permiso de ubicación está bloqueado. Actívalo en los ajustes '
              'del teléfono para usar "Mi ubicación".',
      };

  /// Hay algo que el usuario puede arreglar fuera de la app.
  bool get necesitaAjustes =>
      this == PermisoUbicacion.bloqueado || this == PermisoUbicacion.sinServicio;
}

/// Resultado de intentar leer la posición del teléfono.
class UbicacionObtenida {
  const UbicacionObtenida({
    this.posicion,
    this.advertencia,
    this.permiso = PermisoUbicacion.concedido,
  });

  /// `null` cuando no se pudo obtener nada.
  final Position? posicion;

  /// Texto opcional cuando se devolvió una posición peor que la ideal (por
  /// ejemplo, la última conocida porque el GPS no respondió a tiempo).
  final String? advertencia;

  /// Estado del permiso al terminar el intento. Sirve para ofrecer el atajo a
  /// los ajustes solo cuando de verdad hace falta.
  final PermisoUbicacion permiso;

  bool get ok => posicion != null;
}

/// Lectura de la ubicación del dispositivo para el selector de mapa.
///
/// Existe porque `Geolocator.getCurrentPosition` **no pide permiso por sí
/// solo**: sin una llamada explícita a `requestPermission`, en Android lanza
/// `PermissionDeniedException` en cuanto el permiso no está concedido. Como el
/// selector de mapa no pedía nunca el permiso, "Mi ubicación" siempre terminaba
/// en "No pudimos obtener tu ubicación actual" incluso con el GPS encendido.
///
/// Dos caminos deliberadamente distintos:
///
/// - [obtener] — flujo completo: revisa GPS, pide permiso si hace falta y busca
///   la posición. Es lo que debe disparar un botón que el usuario tocó.
/// - [obtenerSiYaHayPermiso] — consulta silenciosa, sin diálogos, para centrar
///   el mapa al abrirlo. Si no hay permiso devuelve `null` sin molestar.
class UbicacionActual {
  const UbicacionActual._();

  /// Cuánto se espera una posición "en vivo" antes de caer a la última
  /// conocida. Con `LocationAccuracy.medium` 15 s cubren un primer fix en
  /// interiores; con 8 s fallaba a menudo y el usuario veía un error.
  static const Duration _esperaMaxima = Duration(seconds: 15);

  /// Revisa GPS y permiso, pidiéndolo si todavía se puede.
  static Future<PermisoUbicacion> asegurarPermiso() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return PermisoUbicacion.sinServicio;
    }

    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }

    if (permiso == LocationPermission.deniedForever) {
      return PermisoUbicacion.bloqueado;
    }
    if (permiso == LocationPermission.denied) {
      return PermisoUbicacion.denegado;
    }

    // `LocationPermission.unableToDetermine` también llega aquí: se intenta
    // leer la posición y, si falla, el error que se muestra es el de la
    // lectura, no el del permiso.
    return PermisoUbicacion.concedido;
  }

  /// Igual que [asegurarPermiso], pero **sin mostrar el diálogo del sistema**.
  static Future<PermisoUbicacion> permisoActual() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return PermisoUbicacion.sinServicio;
    }

    final permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.always ||
        permiso == LocationPermission.whileInUse) {
      return PermisoUbicacion.concedido;
    }
    if (permiso == LocationPermission.deniedForever) {
      return PermisoUbicacion.bloqueado;
    }
    return PermisoUbicacion.denegado;
  }

  /// Pide permiso si hace falta y devuelve una posición.
  ///
  /// Si el GPS no entrega un fix a tiempo se usa [Geolocator.getLastKnownPosition]
  /// (la última que el teléfono recuerde) y se avisa en
  /// [UbicacionObtenida.advertencia]. Sin eso, un teléfono con el GPS frío
  /// dentro de un edificio siempre mostraba el error aunque hubiera una posición
  /// reciente disponible.
  static Future<UbicacionObtenida> obtener() async {
    final permiso = await asegurarPermiso();
    if (permiso != PermisoUbicacion.concedido) {
      return UbicacionObtenida(
        posicion: null,
        advertencia: permiso.mensaje,
        permiso: permiso,
      );
    }
    return _leer();
  }

  /// Centra el mapa sin pedir nada: si no hay permiso, devuelve `null` para que
  /// quien llama use un centro por defecto.
  static Future<UbicacionObtenida> obtenerSiYaHayPermiso() async {
    final permiso = await permisoActual();
    if (permiso != PermisoUbicacion.concedido) {
      return UbicacionObtenida(permiso: permiso);
    }
    return _leer();
  }

  static Future<UbicacionObtenida> _leer() async {
    try {
      final Position actual = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: _esperaMaxima,
        ),
      );
      return UbicacionObtenida(posicion: actual);
    } catch (_) {
      // Sin fix a tiempo (interiores, GPS frío) o error del proveedor: abajo se
      // intenta la última conocida.
    }

    try {
      final Position? ultima = await Geolocator.getLastKnownPosition();
      if (ultima != null) {
        return UbicacionObtenida(
          posicion: ultima,
          advertencia: 'Usamos tu última ubicación conocida.',
        );
      }
    } catch (_) {
      // Sin caché de posición: se devuelve el error de abajo.
    }

    return const UbicacionObtenida(
      posicion: null,
      advertencia: 'No pudimos obtener tu ubicación. Sal a un lugar abierto e '
          'inténtalo otra vez.',
    );
  }

  /// Abre los ajustes de la app para desbloquear el permiso.
  static Future<bool> abrirAjustes() => Geolocator.openAppSettings();

  /// Abre la pantalla de ubicación del sistema (para encender el GPS).
  static Future<bool> abrirAjustesDeUbicacion() =>
      Geolocator.openLocationSettings();
}
