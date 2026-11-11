import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../main.dart' show AppColors;
import '../screens/map_picker_screen.dart';
import '../services/document_stream.dart';
import '../services/route_service.dart';
import 'bus_marker.dart';
import 'bus_ui.dart';

/// Segundos que tiene el padre para confirmar el aviso de llegada antes de que
/// la app lo dé por confirmado sola. Anclado al momento en que el conductor
/// avisó (`llegoEn`), así el conductor nunca queda esperando a que el padre
/// abra la app.
const int _kSegundosAviso = 10;

/// Punto de recogida de un estudiante, leído de `recogida/{studentId}`.
class _PuntoRecogida {
  const _PuntoRecogida({
    required this.id,
    required this.punto,
    required this.etiqueta,
  });

  /// Id del documento: el id del hijo (`estudiantes/{id}`) o, si es legado, el
  /// uid del padre. Es la misma clave que usa `estadoParadas`.
  final String id;
  final LatLng punto;
  final String etiqueta;
}

/// Sección principal del padre: el mapa en vivo del bus con su propio punto de
/// recogida, la ruta dibujada (OSRM) y el aviso de que el bus llegó.
///
/// Es la pestaña "Ruta" del panel y la que se abre por defecto. No inventa
/// datos: lee `buses/{placa}` (posición y `paradasPublicas`), `rutas/{driverUid}`
/// (colegio de destino y quién ya fue recogido) y `recogida/{studentId}` (su
/// propio punto), y escribe **solo** `recogida/{studentId}` cuando el padre fija
/// o cambia su punto.
///
/// Las paradas de **otros** hijos no se leen de `recogida`: esa colección
/// guarda nombre y teléfono del padre y solo la pueden leer el padre dueño, el
/// conductor del bus y el admin. El conductor publica una copia anónima
/// (`id`, `lat`, `lng`) en `buses/{placa}.paradasPublicas`, que es lo que el
/// padre usa para dibujar el resto de paradas y calcular la siguiente.
class ParentMapView extends StatefulWidget {
  const ParentMapView({
    super.key,
    required this.streams,
    required this.placa,
    required this.parentUid,
    required this.studentId,
    this.driverUid,
    this.childName,
    this.parentName,
    this.parentPhone,
  });

  /// Caché de `snapshots()` compartido con el resto del panel para no abrir
  /// listeners duplicados del mismo documento.
  final StreamsDeDocumento streams;

  /// Placa del bus del padre, o `null` si todavía no tiene una asignada.
  final String? placa;

  final String parentUid;

  /// uid del conductor vinculado al hijo (`estudiantes.driverUid`). Se copia a
  /// `recogida` para que las reglas le dejen leer el punto (y el teléfono) al
  /// conductor del bus. En el hijo legado no existe: se toma de
  /// `buses/{placa}.driverUid` cuando el conductor ya inició una ruta.
  final String? driverUid;

  /// Id del hijo seleccionado. Para un hijo legado es el uid del padre, que es
  /// la clave que ya usaban `recogida/{uid}` y `estadoParadas`.
  final String studentId;

  final String? childName;
  final String? parentName;

  /// Teléfono de contacto del padre. Se copia a `recogida` para que el
  /// conductor pueda llamarlo: las reglas no le dejan leer `usuarios/{uid}`.
  final String? parentPhone;

  @override
  State<ParentMapView> createState() => _ParentMapViewState();
}

class _ParentMapViewState extends State<ParentMapView> {
  static const LatLng _centroPorDefecto = LatLng(4.60971, -74.08175);

  final RouteService _rutas = RouteService();

  GoogleMapController? _mapa;
  BitmapDescriptor? _iconoBus;

  Map<String, dynamic> _bus = <String, dynamic>{};
  LatLng? _destino;
  String _nombreDestino = '';

  /// Todos los puntos de recogida del bus (para dibujar y ordenar la ruta).
  List<_PuntoRecogida> _recogidas = <_PuntoRecogida>[];

  /// Mi punto de recogida (el de [ParentMapView.studentId]).
  LatLng? _miPunto;

  /// `driverUid` que ya tiene guardado mi documento `recogida/{studentId}`.
  /// Sirve para no reescribirlo en cada tick del bus y para saber cuándo hace
  /// falta sellarlo (documentos viejos o hijo legado).
  String? _miDriverUid;

  /// ids de hijos que ya subieron al bus (recogido confirmado).
  Set<String> _subidos = <String>{};

  /// ids de hijos a los que el conductor anunció que llegó (llegoEn).
  Set<String> _llegados = <String>{};

  /// Momento en que este padre confirmó el aviso de llegada, si ya lo hizo.
  DateTime? _miVistoEn;

  /// Momento en que el conductor avisó que llegó al paradero de este padre
  /// (`llegoEn`). Es lo que ancla la cuenta regresiva de [_kSegundosAviso].
  DateTime? _miLlegoEn;

  /// `true` cuando el aviso se confirmó solo por haber pasado la ventana, para
  /// no volver a disparar la confirmación automática.
  bool _autoConfirmado = false;

  List<LatLng> _rutaPuntos = <LatLng>[];
  bool _calculando = false;
  bool _siguiendo = true;

  /// Para no repetir el aviso de llegada mientras el bus siga en el paradero.
  bool _llegoAvisado = false;

  /// Refresca la cuenta regresiva de 10 s en el panel del padre.
  Timer? _tick;

  /// Recuerda si la ruta llegó a estar en curso, para limpiar el mapa solo en
  /// la transición a "finalizada" y no en cada actualización inactiva.
  bool _estuvoActiva = false;

  /// Distingue un movimiento de cámara hecho por la app (seguir el bus) de uno
  /// hecho con el dedo del padre. Solo un gesto del padre pausa el seguimiento.
  bool _moviendoPorCodigo = false;

  /// Última posición usada para centrar la cámara, para no repetir la animación
  /// en cada tick cuando el bus está quieto.
  LatLng? _ultimaPosicionCentrada;

  /// Evita recentrar en la última posición del bus más de una vez al abrir.
  bool _centradoInicial = false;

  Timer? _debounceRuta;
  LatLng? _ultimaPosicionCalculo;

  StreamSubscription<DocumentSnapshot>? _subBus;
  StreamSubscription<DocumentSnapshot>? _subRuta;
  StreamSubscription<DocumentSnapshot>? _subMiPunto;

  bool _esMiPunto(String id) => id == widget.studentId;

  @override
  void initState() {
    super.initState();
    _cargarIconoBus();
    _suscribirBus();
    _suscribirMiPunto();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _quizasAutoConfirmar();
      if (_llegados.contains(widget.studentId)) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant ParentMapView anterior) {
    super.didUpdateWidget(anterior);
    final bool cambioPlaca = anterior.placa != widget.placa;
    final bool cambioHijo = anterior.studentId != widget.studentId;
    if (!cambioPlaca && !cambioHijo) return;

    if (cambioPlaca) {
      _subBus?.cancel();
      _subRuta?.cancel();
      _bus = <String, dynamic>{};
      _recogidas = <_PuntoRecogida>[];
      _llegados = <String>{};
      _subidos = <String>{};
      _miVistoEn = null;
      _miLlegoEn = null;
      _autoConfirmado = false;
      _llegoAvisado = false;
      _rutaPuntos = <LatLng>[];
      _estuvoActiva = false;
      _centradoInicial = false;
      _ultimaPosicionCentrada = null;
      _suscribirBus();
    }

    // Cambiar de hijo cambia la clave de `recogida` y la de `estadoParadas`, así
    // que hay que soltar el punto anterior y volver a escuchar el del hijo
    // seleccionado. El bus y su ruta son los mismos: solo se relee la ruta para
    // recalcular quién subió con la clave nueva.
    if (cambioHijo) {
      _subMiPunto?.cancel();
      _miPunto = null;
      _miDriverUid = null;
      _miVistoEn = null;
      _miLlegoEn = null;
      _autoConfirmado = false;
      _llegoAvisado = false;
      setState(() {
        _subidos = <String>{};
        _llegados = <String>{};
      });
      _suscribirMiPunto();
      if (!cambioPlaca && _rutaActiva) {
        final driverUid = _bus['driverUid']?.toString();
        if (driverUid != null && driverUid.isNotEmpty) {
          _subRuta?.cancel();
          _subRuta = widget.streams
              .de('rutas/$driverUid')
              .listen(_alActualizarRuta);
        }
      }
    }
  }

  @override
  void dispose() {
    _debounceRuta?.cancel();
    _subBus?.cancel();
    _subRuta?.cancel();
    _subMiPunto?.cancel();
    _mapa?.dispose();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _cargarIconoBus() async {
    final icono = await BusMarker.iconoBus();
    if (mounted) setState(() => _iconoBus = icono);
  }

  void _suscribirBus() {
    final placa = widget.placa;
    if (placa == null || placa.isEmpty) return;

    _subBus = widget.streams.de('buses/$placa').listen(_alActualizarBus);
  }

  /// El punto propio se escucha aparte de la lista del bus: así el padre ve su
  /// marcador incluso antes de que el conductor empiece la ruta.
  void _suscribirMiPunto() {
    _subMiPunto?.cancel();
    _subMiPunto = widget.streams
        .de('recogida/${widget.studentId}')
        .listen((snap) {
        final datos = snap.data();
        final mapa = datos is Map<String, dynamic> ? datos : <String, dynamic>{};
        final lat = mapa['lat'];
        final lng = mapa['lng'];
        final visto = mapa['avisoVistoEn'];
        final driverUid = mapa['driverUid']?.toString().trim();
        LatLng? punto;
        if (lat is num && lng is num) {
          punto = LatLng(lat.toDouble(), lng.toDouble());
        }
        if (!mounted) return;
        setState(() {
          _miPunto = punto;
          _miDriverUid =
              (driverUid == null || driverUid.isEmpty) ? null : driverUid;
          _miVistoEn = visto is Timestamp ? visto.toDate() : null;
        });
        // Si el punto ya está pero el documento no tiene `driverUid`, se sella
        // con el que publique el bus.
        _quizasSellarDriverUid(_bus['driverUid']?.toString());
        _programarCalculoRuta(forzar: true);
      });
  }

  void _alActualizarBus(DocumentSnapshot snap) {
    final datos = snap.data();
    final mapa = datos is Map<String, dynamic> ? datos : <String, dynamic>{};
    final driverUid = mapa['driverUid']?.toString();

    debugPrint('ParentMapView: buses/${widget.placa} cambio -> '
        'enMovimiento=${mapa['enMovimiento']}, lat=${mapa['lat']}, '
        'lng=${mapa['lng']}, ultimaLat=${mapa['ultimaLat']}, '
        'ultimaLng=${mapa['ultimaLng']}, ts=${mapa['ultimaActualizacion']}');

    if (!mounted) return;
    setState(() {
      _bus = mapa;
      // Las paradas de otros padres llegan anónimas en `paradasPublicas`.
      // `recogida` solo se lee para el punto propio (ver `_subMiPunto`).
      _recogidas = _leerParadasPublicas(mapa['paradasPublicas']);
    });

    // Documentos viejos (y el hijo legado) pueden no tener `driverUid` en
    // `recogida`: sin él, las reglas no dejan al conductor leer el punto ni el
    // teléfono. En cuanto el bus publica quién lo conduce, se sella.
    _quizasSellarDriverUid(driverUid);

    if (!_rutaActiva) {
      // La ruta terminó (o nunca arrancó): se limpia todo lo que quedó
      // congelado —bus, línea, destino y el aviso "llegó a tu paradero"— y se
      // suelta el listener de la ruta. Se recupera si el conductor vuelve a
      // iniciar (el doc del bus cambia y este listener se dispara otra vez).
      _subRuta?.cancel();
      _subRuta = null;
      if (_estuvoActiva) {
        _estuvoActiva = false;
        _limpiarRuta();
      }
      _centrarEnUltimaSiHaceFalta();
      return;
    }
    _estuvoActiva = true;

    // La ruta cuelga del conductor, no de la placa: se reengancha si cambia.
    _subRuta?.cancel();
    if (driverUid != null && driverUid.isNotEmpty) {
      _subRuta = widget.streams
          .de('rutas/$driverUid')
          .listen(_alActualizarRuta);
    }

    // Como en las apps de transporte: mientras el padre no toque el mapa, la
    // cámara sigue al bus. Al arrastrar, el seguimiento se pausa y queda libre.
    final pos = _posicionBus();
    if (pos != null && _siguiendo && pos != _ultimaPosicionCentrada) {
      _ultimaPosicionCentrada = pos;
      _centrarBus();
      debugPrint('ParentMapView: siguiendo bus -> ${pos.latitude},${pos.longitude}');
    }

    _programarCalculoRuta();
  }

  /// Centra el mapa en la última posición conocida del bus la primera vez que
  /// llega el documento, para no abrir siempre en el centro por defecto.
  void _centrarEnUltimaSiHaceFalta() {
    if (_centradoInicial || !mounted) return;
    final ultima = _ultimaPosicionBus();
    if (ultima == null) return;
    _centradoInicial = true;
    _moviendoPorCodigo = true;
    _mapa?.animateCamera(CameraUpdate.newLatLngZoom(ultima, 15));
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      _moviendoPorCodigo = false;
    });
  }

  /// Borra del mapa y del panel todo lo que pertenece a la ruta activa, para
  /// que al finalizar el viaje no quede el bus ni el aviso congelados.
  void _limpiarRuta() {
    if (!mounted) return;
    setState(() {
      _destino = null;
      _nombreDestino = '';
      _llegados = <String>{};
      _subidos = <String>{};
      _miVistoEn = null;
      _miLlegoEn = null;
      _autoConfirmado = false;
      _rutaPuntos = <LatLng>[];
      _llegoAvisado = false;
      _ultimaPosicionCalculo = null;
      _calculando = false;
    });
    ScaffoldMessenger.of(context).clearSnackBars();
  }

  void _alActualizarRuta(DocumentSnapshot snap) {
    // Si la ruta ya cerró, el historial manda: no revive destino ni recogidos.
    if (!_rutaActiva) return;

    final datos = snap.data();
    final mapa = datos is Map<String, dynamic> ? datos : <String, dynamic>{};

    final destino = mapa['destino'];
    LatLng? punto;
    String nombre = '';
    if (destino is Map) {
      final lat = destino['lat'];
      final lng = destino['lng'];
      if (lat is num && lng is num) {
        punto = LatLng(lat.toDouble(), lng.toDouble());
      }
      nombre = destino['nombre']?.toString().trim() ?? '';
    }

    final estadoParadas = mapa['estadoParadas'];
    final llegados = <String>{};
    final subidos = <String>{};
    DateTime? miLlegoEn;
    if (estadoParadas is Map) {
      estadoParadas.forEach((k, v) {
        if (v is! Map) return;
        if (v['subioEn'] != null) {
          subidos.add(k.toString());
        } else if (v['llegoEn'] != null) {
          llegados.add(k.toString());
          if (k.toString() == widget.studentId) {
            final valor = v['llegoEn'];
            if (valor is Timestamp) miLlegoEn = valor.toDate();
          }
        }
      });
    }

    // Documentos viejos: la lista plana `recogidos`, anterior a
    // `estadoParadas`. Sin esto un recorrido antiguo aparecía sin nadie
    // recogido en el panel.
    final crudos = mapa['recogidos'];
    if (crudos is List) {
      for (final r in crudos) {
        subidos.add(r.toString());
      }
    }

    final llegue = llegados.contains(widget.studentId);
    // Un aviso nuevo (otro `llegoEn`) vuelve a habilitar la confirmación.
    if (miLlegoEn != _miLlegoEn) _autoConfirmado = false;
    if (!mounted) return;
    setState(() {
      _destino = punto;
      _nombreDestino = nombre;
      _llegados = llegados;
      _subidos = subidos;
      _miLlegoEn = miLlegoEn;
    });

    if (llegue && !_llegoAvisado) {
      _llegoAvisado = true;
      _avisarLlegada();
      // Si el aviso ya llegó viejo (el padre abrió la app tarde), se confirma
      // de una vez en lugar de esperar otro tick.
      _quizasAutoConfirmar();
    } else if (!llegue && _llegoAvisado) {
      // Se reinició la ruta: el aviso vuelve a estar disponible.
      _llegoAvisado = false;
    }
    _programarCalculoRuta(forzar: true);
  }

  /// Convierte la lista anónima de `buses/{placa}.paradasPublicas` en puntos
  /// del mapa. El conductor la escribe con `{id, lat, lng}` y **sin** nombre ni
  /// teléfono: son justo los datos que no queremos que un padre vea de otro.
  List<_PuntoRecogida> _leerParadasPublicas(dynamic crudas) {
    if (crudas is! List) return <_PuntoRecogida>[];
    final lista = <_PuntoRecogida>[];
    for (final item in crudas) {
      if (item is! Map) continue;
      final id = (item['id'] ?? '').toString().trim();
      final lat = item['lat'];
      final lng = item['lng'];
      if (id.isEmpty || lat is! num || lng is! num) continue;
      lista.add(
        _PuntoRecogida(
          id: id,
          punto: LatLng(lat.toDouble(), lng.toDouble()),
          etiqueta: _esMiPunto(id)
              ? (widget.childName ?? 'Mi punto')
              : 'Punto de recogida',
        ),
      );
    }
    return lista;
  }

  /// Copia a mi documento de `recogida` el `driverUid` que publica el bus.
  ///
  /// Es la clave que las reglas comparan para dejar al conductor leer mi punto
  /// y mi teléfono. Sin esto, un punto marcado con el hijo legado (o antes de
  /// este cambio) quedaba invisible para su conductor.
  Future<void> _quizasSellarDriverUid(String? driverUid) async {
    final uid = (driverUid ?? '').trim();
    if (uid.isEmpty || _miPunto == null || _miDriverUid == uid) return;

    // Se marca antes del `await` para no disparar una escritura por cada tick
    // del GPS mientras la anterior viaja.
    _miDriverUid = uid;
    try {
      await FirebaseFirestore.instance
          .collection('recogida')
          .doc(widget.studentId)
          .set(<String, dynamic>{
        'driverUid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Si las reglas viejas no lo permiten, el padre puede volver a guardar su
      // punto (que ya escribe `driverUid`) sin quedarse bloqueado.
    }
  }

  // --- Punto de recogida propio ---------------------------------------------

  Future<void> _elegirMiPunto() async {
    final LatLng? punto = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute<LatLng>(
        builder: (context) => MapPickerScreen(
          titulo: 'Mi punto de recogida',
          textoBoton: 'Guardar punto',
          centroInicial: _miPunto ?? _posicionBus(),
          colorPin: AppColors.success,
          ayuda: 'Pon el pin donde el bus debe recoger a tu hijo.',
        ),
      ),
    );
    if (punto == null || !mounted) return;

    final placa = widget.placa;
    if (placa == null || placa.isEmpty) {
      _avisar('Tu cuenta aún no tiene un bus asignado.', esError: true);
      return;
    }

    try {
      final String driverUid =
          ((widget.driverUid ?? '').trim().isNotEmpty
                  ? widget.driverUid!.trim()
                  : (_bus['driverUid']?.toString().trim() ?? ''));
      await FirebaseFirestore.instance
          .collection('recogida')
          .doc(widget.studentId)
          .set({
        'busPlate': placa.toUpperCase(),
        'parentUid': widget.parentUid,
        'studentId': widget.studentId,
        'lat': punto.latitude,
        'lng': punto.longitude,
        'direccion': '',
        'childName': widget.childName ?? '',
        'parentName': widget.parentName ?? '',
        'parentPhone': widget.parentPhone ?? '',
        if (driverUid.isNotEmpty) 'driverUid': driverUid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _miDriverUid = driverUid.isEmpty ? null : driverUid;
      if (!mounted) return;
      _avisar('Tu punto de recogida quedó guardado.');
    } catch (e) {
      if (!mounted) return;
      _avisar(
        e is FirebaseException && e.code == 'permission-denied'
            ? 'La base de datos no permitió guardar. Faltan desplegar las '
                'reglas de seguridad.'
            : 'No se pudo guardar tu punto. Revisa tu conexión.',
        esError: true,
      );
    }
  }

  /// Elimina el punto de recogida del hijo (`recogida/{studentId}`).
  ///
  /// Solo se ofrece cuando ya hay un punto marcado, que es exactamente el caso
  /// de `_buildConPunto`. Pide confirmación porque deja el hijo sin parada en el
  /// mapa hasta que el padre vuelva a marcarla.
  Future<void> _eliminarMiPunto() async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogo) => AlertDialog(
        title: const Text('Eliminar punto de recogida'),
        content: Text(
          widget.childName == null
              ? 'Se quitará tu punto de recogida del mapa.'
              : 'Se quitará el punto de recogida de '
                  '${widget.childName} del mapa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogo).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    try {
      await FirebaseFirestore.instance
          .collection('recogida')
          .doc(widget.studentId)
          .delete();
      if (!mounted) return;
      // El listener de `recogida/{studentId}` también lo refleja, pero se
      // adelanta aquí para que el panel cambie en cuanto toca "Eliminar".
      setState(() {
        _miPunto = null;
        _miDriverUid = null;
      });
      _avisar('Tu punto de recogida se eliminó.');
    } catch (e) {
      if (!mounted) return;
      _avisar(
        e is FirebaseException && e.code == 'permission-denied'
            ? 'La base de datos no permitió borrar. Faltan desplegar las '
                'reglas de seguridad.'
            : 'No se pudo borrar tu punto. Revisa tu conexión.',
        esError: true,
      );
    }
  }

  /// Aviso de que el bus llegó al paradero. El padre lo confirma desde el
  /// SnackBar o desde el botón del panel; si no responde en 10 s, la app lo da
  /// por confirmado sola y el conductor continúa.
  void _avisarLlegada() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: _kSegundosAviso),
        action: SnackBarAction(
          label: 'Confirmar',
          textColor: Colors.white,
          onPressed: _confirmarLlegada,
        ),
        content: Text(
          '¡El bus llegó a tu paradero!'
          '${widget.childName == null ? '' : ' Sigue ${widget.childName}.'}',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  /// Marca el aviso como confirmado si ya pasó la ventana de [_kSegundosAviso]
  /// sin respuesta del padre. Corre desde el contador del panel.
  void _quizasAutoConfirmar() {
    if (_autoConfirmado || _miVistoEn != null) return;
    if (!_llegados.contains(widget.studentId)) return;
    final llego = _miLlegoEn;
    if (llego == null) return;
    final segundos = DateTime.now().difference(llego).inSeconds;
    if (segundos < _kSegundosAviso) return;
    _autoConfirmado = true;
    _confirmarLlegada();
  }

  /// Confirma que el padre vio el aviso de llegada. Se guarda en
  /// `recogida/{studentId}.avisoVistoEn` para que el conductor lo detecte.
  Future<void> _confirmarLlegada() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() => _miVistoEn = DateTime.now());
    try {
      await FirebaseFirestore.instance
          .collection('recogida')
          .doc(widget.studentId)
          .set({
        'avisoVistoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        _avisar(
          e is FirebaseException && e.code == 'permission-denied'
              ? 'No se pudo confirmar: revisa las reglas de Firestore.'
              : 'No se pudo enviar la confirmación. Revisa tu conexión.',
          esError: true,
        );
      }
    }
  }

  void _avisar(String texto, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: esError ? AppColors.danger : AppColors.success,
      ),
    );
  }

  // --- Ruta (OSRM) -----------------------------------------------------------

  /// ¿Hay una ruta en curso? Es el único dato que decide si el mapa del padre
  /// muestra algo. El conductor pone `enMovimiento: true` al iniciar y `false`
  /// al finalizar; con la ruta cerrada no se dibuja ni el bus ni la línea.
  bool get _rutaActiva => _bus['enMovimiento'] == true;

  LatLng? _posicionBus() {
    if (!_rutaActiva) return null;
    final lat = _bus['lat'];
    final lng = _bus['lng'];
    if (lat is! num || lng is! num) return null;
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  /// Última posición conocida del bus, aunque la ruta ya haya terminado. Es lo
  /// que hace que el mapa abra donde quedó el bus y no en un centro por
  /// defecto. `ultimaLat`/`ultimaLng` los conserva el GPS al finalizar.
  LatLng? _ultimaPosicionBus() {
    final lat = _bus['ultimaLat'];
    final lng = _bus['ultimaLng'];
    if (lat is! num || lng is! num) return _posicionBus();
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  double _rumbo() {
    final valor = _bus['rumbo'];
    return valor is num ? valor.toDouble() : 0;
  }

  void _programarCalculoRuta({bool forzar = false}) {
    if (!forzar && !_movioSuficiente()) return;
    _debounceRuta?.cancel();
    _debounceRuta = Timer(
      const Duration(milliseconds: 600),
      _calcularRuta,
    );
  }

  bool _movioSuficiente() {
    final pos = _posicionBus();
    final previa = _ultimaPosicionCalculo;
    if (pos == null) return false;
    if (previa == null) return true;
    return Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          previa.latitude,
          previa.longitude,
        ) >
        25;
  }

  /// Ruta que le importa al padre, **tramo por tramo** y con la misma regla que
  /// el conductor (`driver_ruta_screen._rutaOrdenada`): mientras el bus no haya
  /// recogido a su hijo, el tramo hacia su paradero; una vez que subió, el tramo
  /// hacia la parada pendiente más cercana y, solo cuando ya no queda ninguna,
  /// el tramo hacia el colegio.
  ///
  /// Antes, en cuanto su hijo subía, la línea saltaba directo al colegio aunque
  /// el bus siguiera con los puntos de otros estudiantes: el padre veía al bus
  /// ir a un lado mientras el texto del panel, justo debajo, decía "aún tiene N
  /// paradas pendientes antes del colegio". Las dos pantallas dibujan ahora el
  /// mismo trayecto.
  List<LatLng> _rutaInteres() {
    final bus = _posicionBus();
    if (bus == null) return <LatLng>[];

    final LatLng? miPunto = _miPunto;
    if (miPunto != null && !_subidos.contains(widget.studentId)) {
      return <LatLng>[bus, miPunto];
    }

    // Misma regla que el conductor: la siguiente parada pendiente.
    // `_siguienteParada` ya excluye a los recogidos, así que aquí no vuelve a
    // aparecer mi punto.
    final LatLng? objetivo = _siguienteParada()?.punto ?? _destino;
    return <LatLng>[bus, ?objetivo];
  }

  Future<void> _calcularRuta() async {
    if (!mounted || _calculando) return;
    final puntos = _rutaInteres();
    if (puntos.length < 2) {
      setState(() => _rutaPuntos = <LatLng>[]);
      return;
    }

    _calculando = true;
    _ultimaPosicionCalculo = _posicionBus();
    final RutaCalculada? calculada = await _rutas.calcular(puntos);
    _calculando = false;
    if (!mounted) return;
    setState(() {
      _rutaPuntos = calculada?.puntos ?? puntos;
    });
  }

  Future<void> _centrarBus() async {
    final pos = _posicionBus();
    if (pos == null) return;
    _moviendoPorCodigo = true;
    try {
      await _mapa?.animateCamera(CameraUpdate.newLatLngZoom(pos, 16));
    } catch (_) {
      // Mapa todavía sin crear.
    } finally {
      // `onCameraMoveStarted` puede llegar después de que el Future resuelva;
      // se baja la bandera con un pequeño retardo para no confundir ese
      // movimiento programado con un gesto del padre.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      _moviendoPorCodigo = false;
    }
  }

  // --- Interfaz --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final placa = widget.placa;
    if (placa == null || placa.isEmpty) {
      return const _AvisoMapa(
        texto: 'No tienes ninguna placa de bus asociada a tu cuenta.',
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            _buildMapa(),
            _buildChipSenal(),
            if (_calculando)
              const Positioned(
                top: 10,
                right: 10,
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            Positioned(
              right: 10,
              bottom: 168,
              child: FloatingActionButton.small(
                heroTag: 'seguir_bus_padre',
                backgroundColor:
                    _siguiendo ? AppColors.primary : AppColors.surface,
                foregroundColor: AppColors.ink,
                onPressed: () {
                  setState(() {
                    _siguiendo = true;
                    _ultimaPosicionCentrada = _posicionBus();
                  });
                  _centrarBus();
                },
                child: Icon(
                  _siguiendo ? Icons.my_location : Icons.location_disabled,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildPanelInferior(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapa() {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _posicionBus() ??
            _ultimaPosicionBus() ??
            _miPunto ??
            _centroPorDefecto,
        zoom: 15,
      ),
      onMapCreated: (c) => _mapa = c,
      onCameraMoveStarted: () {
        // Solo un gesto del padre pausa el seguimiento; los movimientos que
        // hace la app para seguir al bus no cuentan.
        if (!_moviendoPorCodigo && _siguiendo) {
          setState(() => _siguiendo = false);
        }
      },
      markers: _buildMarcadores(),
      polylines: _rutaPuntos.length < 2
          ? <Polyline>{}
          : {
              Polyline(
                polylineId: const PolylineId('ruta_padre'),
                points: _rutaPuntos,
                color: AppColors.ink,
                width: 5,
              ),
            },
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      // El mapa vive en una pestaña indexada: sin esto el resto de gestos de
      // la pantalla podrían robar el arrastre.
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
      },
    );
  }

  Set<Marker> _buildMarcadores() {
    final marcas = <Marker>{};
    final activa = _rutaActiva;

    if (activa) {
      final bus = _posicionBus();
      final icono = _iconoBus;
      if (bus != null && icono != null) {
        marcas.add(
          Marker(
            markerId: const MarkerId('bus'),
            position: bus,
            // `flat: false` dibuja el bus como "billboard": no se inclina con el
            // mapa ni se agranda al alejar el zoom, así la flechita se ve
            // siempre del mismo tamaño y parada. Con `flat: true` el icono se
            // acostaba y crecía al hacer zoom out.
            rotation: _rumbo(),
            flat: false,
            anchor: const Offset(0.5, 0.5),
            icon: icono,
            infoWindow: InfoWindow(title: 'Bus ${widget.placa}'),
          ),
        );
      }

      for (final parada in _recogidas) {
        final atendido = _subidos.contains(parada.id);
        final esMia = _esMiPunto(parada.id);
        final llego = _llegados.contains(parada.id);
        final double tono = atendido
            ? BitmapDescriptor.hueGreen
            : (llego && esMia)
                ? BitmapDescriptor.hueGreen
                : (llego ? BitmapDescriptor.hueAzure : (esMia ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueOrange));
        final String detalle = atendido
            ? 'Ya recogido'
            : (llego ? 'Aviso enviado · esperando' : 'Punto de recogida');
        marcas.add(
          Marker(
            markerId: MarkerId('recogida_${parada.id}'),
            position: parada.punto,
            icon: BitmapDescriptor.defaultMarkerWithHue(tono),
            infoWindow: InfoWindow(
              // Sin el nombre del otro estudiante: el mapa del padre solo
              // necesita distinguir "mi parada" de "otra parada".
              title: esMia ? 'Mi punto de recogida' : 'Punto de recogida',
              snippet: detalle,
            ),
          ),
        );
      }

      final destino = _destino;
      if (destino != null) {
        marcas.add(
          Marker(
            markerId: const MarkerId('destino'),
            position: destino,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(
              title: _nombreDestino.isEmpty ? 'Colegio' : _nombreDestino,
              snippet: 'Destino del bus',
            ),
          ),
        );
      }
    }

    // Mi punto se dibuja incluso sin ruta activa: es mi dato, sobrevive al
    // cierre del recorrido. Si ya lo pintó el bucle de arriba, no se repite.
    final yaDibujado = activa && _recogidas.any((p) => _esMiPunto(p.id));
    if (_miPunto != null && !yaDibujado) {
      marcas.add(
        Marker(
          markerId: MarkerId('mi_punto_${widget.studentId}'),
          position: _miPunto!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            _subidos.contains(widget.studentId)
                ? BitmapDescriptor.hueGreen
                : (_llegados.contains(widget.studentId)
                    ? BitmapDescriptor.hueAzure
                    : BitmapDescriptor.hueAzure),
          ),
          infoWindow: const InfoWindow(title: 'Mi punto de recogida'),
        ),
      );
    }

    return marcas;
  }

  /// Chip de la esquina superior izquierda: estado de la señal del bus y, si
  /// ya hay posición, las coordenadas actuales con seis decimales.
  ///
  /// Las coordenadas están para poder mirar si el bus **de verdad se mueve**:
  /// con el marcador fijo es fácil dudar entre "el bus avanzó" y "moví yo el
  /// mapa". El sexto decimal cambia a cada ~11 cm, así que en cuanto haya
  /// movimiento se ve.
  Widget _buildChipSenal() {
    final activa = _rutaActiva;
    final frescura = _frescura();
    final pos = _posicionBus();
    final texto = !activa
        ? 'Sin ruta activa'
        : (pos == null
            ? 'Esperando la señal del bus'
            : (frescura == null ? 'Señal en vivo' : 'Señal $frescura'));

    return Positioned(
      left: 10,
      top: 10,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BusStatusPill(
            label: texto,
            dotColor: !activa
                ? AppColors.textMuted
                : (pos == null ? AppColors.primaryDeep : AppColors.primary),
          ),
          if (pos != null) ...[
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 5),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.my_location,
                    size: 12,
                    color: AppColors.primaryDeep,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _formatoCoordenadas(pos),
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Lat/lng con seis decimales: suficiente para ver el desplazamiento en
  /// centímetros y no quedarse con una cifra redondeada que no cambia.
  String _formatoCoordenadas(LatLng p) {
    return '${p.latitude.toStringAsFixed(6)}, '
        '${p.longitude.toStringAsFixed(6)}';
  }

  String? _frescura() {
    final valor = _bus['ultimaActualizacion'];
    if (valor is! Timestamp) return null;
    final seg = DateTime.now().difference(valor.toDate()).inSeconds;
    if (seg < 0) return 'ahora';
    if (seg < 60) return 'hace $seg s';
    if (seg < 3600) return 'hace ${seg ~/ 60} min';
    return 'hace ${seg ~/ 3600} h';
  }

  Widget _buildPanelInferior() {
    return Container(
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _miPunto == null
            ? _buildSinPunto()
            : _buildConPunto(),
      ),
    );
  }

  List<Widget> _buildSinPunto() {
    return [
      Row(
        children: [
          BusIconBadge(
            icon: Icons.add_location_alt_rounded,
            size: 42,
            color: AppColors.primaryPale,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Marca dónde recoges a '
              '${widget.childName ?? 'tu hijo'}: así sabes cuándo llega el bus.',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppColors.textStrong,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      // `BusPrimaryButton` en vez de un `SizedBox` de 46 con `ElevatedButton`:
      // el padding vertical del tema no cabía en 46 y el texto salía cortado.
      BusPrimaryButton(
        label: 'Marcar mi punto de recogida',
        icon: Icons.location_on_rounded,
        onPressed: _elegirMiPunto,
      ),
    ];
  }

  List<Widget> _buildConPunto() {
    final atendido = _subidos.contains(widget.studentId);
    final llego = _llegados.contains(widget.studentId);
    final siguiente = _siguienteParada();
    final bus = _posicionBus();
    final double? metros =
        bus == null ? null : Geolocator.distanceBetween(
              bus.latitude,
              bus.longitude,
              _miPunto!.latitude,
              _miPunto!.longitude,
            );

    // Segundos que le quedan al padre antes de que el aviso se confirme solo.
    final int segundosAviso = (!llego || _miVistoEn != null || _miLlegoEn == null)
        ? 0
        : (_kSegundosAviso - DateTime.now().difference(_miLlegoEn!).inSeconds)
            .clamp(0, _kSegundosAviso)
            .toInt();

    final String titulo;
    final String subtitulo;
    final Color colorTitulo;

    // Cuántos estudiantes del bus siguen pendientes. El padre no ve sus
    // nombres (son otros niños), pero el número explica por qué el bus no va
    // todavía al colegio. Antes, apenas subía su hijo, el panel decía "El bus
    // continúa hacia el colegio" aunque quedaran paradas: el mensaje era falso
    // y hacía parecer que la ruta estaba rota.
    final int pendientes = _recogidas
        .where((p) => !_subidos.contains(p.id))
        .length;

    if (!_rutaActiva) {
      titulo = 'Esta ruta se finalizó';
      subtitulo = 'El conductor cerró el recorrido. Lo tienes en "Recorrido".';
      colorTitulo = AppColors.textMuted;
    } else if (atendido) {
      titulo = widget.childName == null
          ? 'Tu hijo ya fue recogido'
          : '${widget.childName} ya fue recogido';
      subtitulo = pendientes > 0
          ? 'El bus aún tiene ${pendientes == 1 ? 'una parada pendiente' : '$pendientes paradas pendientes'} antes del colegio.'
          : 'El bus continúa hacia el colegio.';
      colorTitulo = AppColors.success;
    } else if (llego) {
      final visto = _miVistoEn != null;
      titulo = visto ? 'Confirmado' : '¡El bus llegó a tu paradero!';
      subtitulo = visto
          ? 'Confirmaste la llegada. El conductor espera que ${widget.childName ?? 'tu hijo'} suba.'
          : segundosAviso > 0
              ? 'Toca Confirmar para que continúe. Se marcará solo en '
                  '$segundosAviso s.'
              : 'Confirmando la llegada…';
      colorTitulo = visto ? AppColors.success : AppColors.ink;
    } else if (bus == null) {
      titulo = 'Esperando la señal del bus';
      subtitulo = 'El recorrido aparece cuando el conductor inicia la ruta.';
      colorTitulo = AppColors.textStrong;
    } else {
      final esMiaLaSiguiente =
          siguiente != null && _esMiPunto(siguiente.id);
      // No se nombra a los otros estudiantes: el padre solo necesita saber si
      // el bus viene hacia su paradero o si aún está atendiendo a alguien más.
      titulo = esMiaLaSiguiente
          ? 'El bus está en camino a tu hijo'
          : (siguiente == null
              ? 'El bus va al colegio'
              : 'El bus está atendiendo otras paradas');
      subtitulo = metros == null
          ? 'Sigue el recorrido en el mapa.'
          : (esMiaLaSiguiente
              ? 'A ${metros.round()} m de tu punto.'
              : 'El bus está a ${metros.round()} m de tu punto.');
      colorTitulo = esMiaLaSiguiente ? AppColors.ink : AppColors.textStrong;
    }

    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            !_rutaActiva
                ? Icons.flag_circle_outlined
                : (atendido
                    ? Icons.check_circle
                    : (llego ? Icons.notifications_active : Icons.directions_bus_filled)),
            color:             !_rutaActiva
                ? AppColors.textMuted
                : (atendido
                    ? AppColors.success
                    : (llego ? AppColors.ink : AppColors.ink)),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colorTitulo,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitulo,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      // `minimumSize` en vez de un `SizedBox` de altura fija: con altura fija
      // el padding vertical del tema dejaba al texto menos alto del que
      // necesita y se veía cortado por abajo.
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.border),
          minimumSize: const Size.fromHeight(44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: _elegirMiPunto,
        icon: const Icon(Icons.edit_location_alt, size: 18),
        label: const Text('Cambiar mi punto'),
      ),
      const SizedBox(height: 10),
      TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.danger,
          minimumSize: const Size.fromHeight(44),
        ),
        onPressed: _eliminarMiPunto,
        icon: const Icon(Icons.delete_outline, size: 18),
        label: const Text('Eliminar mi punto'),
      ),
      if (llego && !atendido && _miVistoEn == null) ...[
        const SizedBox(height: 10),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.ink,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: _confirmarLlegada,
          icon: const Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: AppColors.primary,
          ),
          label: const Text('Confirmar que vi el aviso'),
        ),
      ],
    ];
  }

  /// Recogida pendiente más cercana al bus.
  _PuntoRecogida? _siguienteParada() {
    final pendientes =
        _recogidas.where((p) => !_subidos.contains(p.id)).toList();
    if (pendientes.isEmpty) return null;

    final bus = _posicionBus();
    if (bus == null) return pendientes.first;

    pendientes.sort(
      (a, b) => Geolocator.distanceBetween(bus.latitude, bus.longitude,
              a.punto.latitude, a.punto.longitude)
          .compareTo(Geolocator.distanceBetween(bus.latitude, bus.longitude,
              b.punto.latitude, b.punto.longitude)),
    );
    return pendientes.first;
  }
}

/// Aviso centrado, para cuando no hay placa que seguir.
class _AvisoMapa extends StatelessWidget {
  const _AvisoMapa({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return BusEmptyState(
      text: texto,
      icon: Icons.location_off_rounded,
    );
  }
}
