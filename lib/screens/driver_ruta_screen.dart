import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../main.dart' show AppColors;
import '../services/bus_location_service.dart';
import '../services/document_stream.dart';
import '../services/google_auth.dart';
import '../services/phone_launcher.dart';
import '../services/route_service.dart';
import '../services/session_prefs.dart';
import '../widgets/bus_marker.dart';
import '../widgets/bus_nav_bar.dart';
import '../widgets/bus_ui.dart';
import '../widgets/recorrido_bus_view.dart';
import 'acerca_de_screen.dart';
import 'change_password_screen.dart';
import 'driver_datos_screen.dart';
import 'driver_qr_screen.dart';
import 'login_screen.dart';
import 'map_picker_screen.dart';

/// Distancia a la que el botón "Ya recogí" se resalta. A pie son unos dos
/// minutos; más lejos el conductor lo tocaría antes de llegar, pero el botón
/// sigue disponible para no bloquear la recogida si el GPS va retrasado.
const double _kRadioLlegadaMetros = 120;

/// Punto de recogida de un estudiante, ya resuelto desde `recogida/{studentId}`.
class ParadaRecogida {
  ParadaRecogida({
    required this.studentId,
    required this.parentUid,
    required this.punto,
    required this.etiqueta,
    this.parentName,
    this.parentPhone,
    this.avisoVistoEn,
  });

  /// Id del hijo: clave del documento `recogida/{id}` y de `estadoParadas`.
  /// Para el hijo legado es el uid del padre.
  final String studentId;

  /// Uid del padre dueño del hijo. Solo se usa para archivarlo en el historial;
  /// las escrituras de la ruta van por [studentId].
  final String parentUid;

  final LatLng punto;

  /// Nombre del estudiante o del padre, para el botón "Ya recogí" y la lista.
  final String etiqueta;

  /// Nombre y teléfono del padre. El teléfono viaja en `recogida` porque las
  /// reglas no dejan al conductor leer `usuarios/{uid}`.
  final String? parentName;
  final String? parentPhone;

  /// Momento en que el padre confirmó el aviso de llegada ("visto"). Se
  /// conserva por compatibilidad con documentos escritos por versiones
  /// anteriores; el flujo actual ya no espera esa confirmación.
  final DateTime? avisoVistoEn;
}

/// Estudiante vinculado al bus del conductor, tenga o no punto de recogida.
///
/// La pestaña "Estudiantes" se alimenta de dos fuentes: `estudiantes` (el
/// vínculo con el bus, que existe desde que el padre usa el código) y `recogida`
/// (el pin que el padre mueve en el mapa). Antes solo se leía la segunda, así
/// que un hijo vinculado sin pin era invisible para el conductor: no aparecía
/// ni para llamar al padre.
class EstudianteBus {
  const EstudianteBus({
    required this.studentId,
    required this.nombre,
    this.parentName,
    this.parentPhone,
    this.busPlate = '',
    this.tienePunto = false,
  });

  /// Id del hijo: la misma clave de `recogida/{id}` y de `estadoParadas`.
  final String studentId;

  final String nombre;

  /// Placa a la que está vinculado el hijo. Un conductor con dos buses solo
  /// debe ver aquí los del bus de su ficha.
  final String busPlate;

  /// Nombre y teléfono del padre. Solo llegan por `recogida.parentPhone` (las
  /// rules no dejan al conductor leer `usuarios/{uid}`), así que un hijo sin
  /// punto todavía no tiene teléfono.
  final String? parentName;
  final String? parentPhone;

  /// `true` si el padre ya marcó el punto de recogida en el mapa.
  final bool tienePunto;
}

/// Junta los hijos vinculados a un conductor con los puntos de recogida que ya
/// marcaron sus padres.
///
/// Reglas:
///
/// - Manda `estudiantes`: un hijo vinculado aparece **aunque no tenga pin**.
/// - `recogida` aporta el `parentPhone` (las rules no dejan al conductor leer
///   `usuarios/{uid}`) y los documentos legados que no tienen fila en
///   `estudiantes`.
/// - Si un hijo está en las dos fuentes, no se duplica.
/// - Se filtran los de otra placa para que un conductor con dos buses no vea
///   aquí los estudiantes del otro.
///
/// Es una función pura a propósito: `test/estudiantes_conductor_test.dart` la
/// cubre sin red ni Firebase, incluido el caso que causaba el bug (vinculado sin
/// punto invisible).
@visibleForTesting
List<EstudianteBus> fusionarEstudiantes({
  required List<EstudianteBus> vinculados,
  required List<ParadaRecogida> recogidas,
  required String placa,
}) {
  final porId = <String, EstudianteBus>{};

  for (final vinculado in vinculados) {
    if (placa.isNotEmpty &&
        vinculado.busPlate.isNotEmpty &&
        vinculado.busPlate != placa) {
      continue;
    }
    porId[vinculado.studentId] = vinculado;
  }

  for (final parada in recogidas) {
    final vinculado = porId[parada.studentId];
    porId[parada.studentId] = EstudianteBus(
      studentId: parada.studentId,
      nombre: vinculado?.nombre ?? parada.etiqueta,
      parentName: parada.parentName,
      parentPhone: parada.parentPhone,
      busPlate: vinculado?.busPlate ?? placa,
      tienePunto: true,
    );
  }

  final lista = porId.values.toList(growable: false);
  lista.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
  return lista;
}

/// Panel del conductor, ahora sobre el mapa.
///
/// El recorrido ya no se arma escribiendo paradas: el conductor **solo elige el
/// colegio** (destino final) tocando el mapa, y las paradas son los puntos de
/// recogida que cada padre marcó en `recogida/{uid}`. El conductor ve todos los
/// de su bus y la app dibuja el camino con OSRM **tramo por tramo**: hasta la
/// recogida pendiente más cercana y, cuando ya recogió a todos, hasta el
/// colegio. Al llegar a un punto pulsa "Ya recogí", que cierra esa parada
/// (`subioEn`) y avanza el tramo; el padre ve al instante que su hijo ya fue
/// recogido.
///
/// Escribe en dos sitios, con responsabilidades distintas:
///
/// - `rutas/{uid}` — `destino` (colegio) y `estadoParadas` (uids ya atendidos).
/// - `buses/{placa}` — el estado del viaje, solo al pulsar "Iniciar Ruta".
class PantallaRutaConductor extends StatefulWidget {
  const PantallaRutaConductor({super.key});

  @override
  State<PantallaRutaConductor> createState() => _PantallaRutaConductorState();
}

class _PantallaRutaConductorState extends State<PantallaRutaConductor> {
  final StreamsDeDocumento _streams = StreamsDeDocumento();
  final BusLocationService _gps = BusLocationService();
  final RouteService _rutas = RouteService();

  /// Destinos de la barra inferior. El orden se usa como índice del
  /// `IndexedStack`: 0 "Ruta", 1 "Recorrido", 2 "Estudiantes", 3 "Mi Perfil".
  static const List<BusNavDestino> _destinos = <BusNavDestino>[
    BusNavDestino(icono: Icons.map_rounded, etiqueta: 'Ruta'),
    BusNavDestino(icono: Icons.route_rounded, etiqueta: 'Recorrido'),
    BusNavDestino(
      icono: Icons.family_restroom_rounded,
      etiqueta: 'Estudiantes',
    ),
    BusNavDestino(icono: Icons.person_rounded, etiqueta: 'Mi Perfil'),
  ];

  /// Pestaña visible. Abre en "Ruta", el mapa en vivo.
  int _pestana = 0;

  GoogleMapController? _mapa;
  BitmapDescriptor? _iconoBus;

  /// Placa del conductor (de `usuarios/{uid}.busPlate`). Es el puente hacia su
  /// bus y hacia las recogidas de sus padres.
  String _placa = '';
  String _nombreConductor = '';

  /// Teléfono que el conductor registró. Se publica en `buses/{placa}` al
  /// iniciar la ruta para que el padre pueda llamarlo desde su panel.
  String _telefonoConductor = '';
  bool _cargandoPerfil = true;

  /// Colegio de destino elegido en el mapa.
  LatLng? _destino;
  String _nombreDestino = '';

  /// Posición del bus (lat/lng de `buses/{placa}`), que escribe el GPS.
  LatLng? _miPosicion;
  double _rumbo = 0;

  /// Última posición conocida del bus, incluso con la ruta finalizada
  /// (`ultimaLat`/`ultimaLng`). Sirve para que el mapa abra donde quedó el bus.
  LatLng? _ultimaPosicion;
  bool _centradoInicial = false;

  /// Puntos de recogida de los padres de este bus.
  List<ParadaRecogida> _recogidas = <ParadaRecogida>[];

  /// Hijos vinculados a este conductor en `estudiantes`, con o sin punto de
  /// recogida. Es la fuente de la pestaña "Estudiantes"; [_recogidas] sigue
  /// siendo la del mapa y la ruta, porque ahí un punto es obligatorio.
  List<EstudianteBus> _estudiantesVinculados = <EstudianteBus>[];

  /// Estado de cada parada de la ruta actual, leído de
  /// `rutas/{uid}.estadoParadas` = `{ <studentId>: {llegoEn, subioEn} }`.
  ///
  /// - `llegoEn` — se conserva por documentos viejos; el flujo actual ya no lo
  ///   escribe.
  /// - `subioEn` — el conductor confirmó con "Ya recogí" que el estudiante
  ///   subió; la parada queda cerrada y la ruta continúa con la siguiente.
  Map<String, dynamic> _estadoParadas = <String, dynamic>{};

  /// Polilínea del camino y resumen de tiempo/distancia.
  List<LatLng> _rutaPuntos = <LatLng>[];
  String? _resumenRuta;

  bool _esRutaActiva = false;
  bool _isIniciando = false;
  bool _calculandoRuta = false;

  /// Mientras sea `true`, la cámara sigue al bus. Un gesto del conductor la
  /// pausa para que pueda mirar el resto del mapa; el botón de ubicación la
  /// reactiva. Sin esto el mapa se quedaba clavado en la posición inicial y, al
  /// avanzar, el marcador se salía de la pantalla y parecía congelado.
  bool _siguiendo = true;

  /// Distingue un movimiento de cámara hecho por la app (seguir al bus) de uno
  /// hecho con el dedo: solo el gesto del conductor pausa el seguimiento.
  bool _moviendoPorCodigo = false;

  /// Última posición usada para centrar la cámara, para no repetir la animación
  /// en cada tick cuando el bus está quieto.
  LatLng? _ultimaPosicionCentrada;

  /// Firma de la última lista publicada en `buses/{placa}.paradasPublicas`.
  /// Evita reescribir el bus (y despertar a todos los padres) cuando la lista
  /// de paradas no cambió. `null` fuerza la primera publicación, aunque la
  /// lista esté vacía, para limpiar una copia vieja de otra sesión.
  String? _firmaParadasPublicas;

  Timer? _debounceRuta;
  LatLng? _ultimaPosicionCalculo;

  StreamSubscription<DocumentSnapshot>? _subPerfil;
  StreamSubscription<DocumentSnapshot>? _subBus;
  StreamSubscription<DocumentSnapshot>? _subRuta;
  StreamSubscription<QuerySnapshot>? _subRecogidas;
  StreamSubscription<QuerySnapshot>? _subEstudiantes;

  @override
  void initState() {
    super.initState();
    _cargarIconoBus();
    _escucharPerfil();
    _escucharEstudiantes();
  }

  @override
  void dispose() {
    _debounceRuta?.cancel();
    _subPerfil?.cancel();
    _subBus?.cancel();
    _subRuta?.cancel();
    _subRecogidas?.cancel();
    _subEstudiantes?.cancel();
    _mapa?.dispose();
    _gps.detener();
    super.dispose();
  }

  User? get _usuario => FirebaseAuth.instance.currentUser;

  Future<void> _cargarIconoBus() async {
    final icono = await BusMarker.iconoBus();
    if (mounted) setState(() => _iconoBus = icono);
  }

  /// El perfil da la placa; con ella se enganchan el bus, la ruta propia y las
  /// recogidas de los padres de ese bus.
  void _escucharPerfil() {
    final uid = _usuario?.uid;
    if (uid == null) {
      setState(() => _cargandoPerfil = false);
      return;
    }

    _subPerfil = _streams.de('usuarios/$uid').listen((snap) {
      _escucharEstudiantes();
      final datos = snap.data();
      final mapa = datos is Map<String, dynamic> ? datos : <String, dynamic>{};
      final placa = mapa['busPlate']?.toString().trim().toUpperCase() ?? '';
      final nombre = mapa['fullName']?.toString().trim() ?? '';
      final telefono = mapa['phone']?.toString().trim() ?? '';

      if (!mounted) return;
      setState(() {
        _cargandoPerfil = false;
        _nombreConductor = nombre;
        _telefonoConductor = telefono;
      });

      if (placa != _placa) {
        setState(() => _placa = placa);
        _reengancharPlaca(uid, placa);
      }
    });
  }

  /// Hijos vinculados a este conductor, con o sin punto de recogida.
  ///
  /// Sale de `estudiantes` filtrando por `driverUid`, un solo campo, así que no
  /// necesita índice compuesto. El `onError` ignora `permission-denied` a
  /// propósito: mientras las rules desplegadas no incluyan la lectura del
  /// conductor, la pestaña sigue mostrando los que sí marcaron punto en vez de
  /// quedarse vacía para siempre.
  void _escucharEstudiantes() {
    final uid = _usuario?.uid;
    if (uid == null || _subEstudiantes != null) return;

    _subEstudiantes = _streams
        .deConsulta(
          'estudiantes-conductor/$uid',
          () => FirebaseFirestore.instance
              .collection('estudiantes')
              .where('driverUid', isEqualTo: uid)
              .snapshots(),
        )
        .listen(_alActualizarEstudiantes, onError: (Object _) {});
  }

  void _alActualizarEstudiantes(QuerySnapshot snap) {
    final lista = <EstudianteBus>[];
    for (final doc in snap.docs) {
      final datos = doc.data();
      if (datos is! Map<String, dynamic>) continue;
      final nombre = (datos['nombre'] ?? '').toString().trim();
      lista.add(
        EstudianteBus(
          studentId: doc.id,
          nombre: nombre.isEmpty ? 'un estudiante' : nombre,
          busPlate: (datos['busPlate'] ?? '').toString().trim().toUpperCase(),
        ),
      );
    }
    if (!mounted) return;
    setState(() => _estudiantesVinculados = lista);
  }

  /// Lista de la pestaña "Estudiantes": manda el vínculo de `estudiantes` (así
  /// aparece incluso sin pin) y `recogida` aporta el teléfono del padre y los
  /// documentos legados, que no tienen fila en `estudiantes`.
  List<EstudianteBus> get _estudiantesDelBus => fusionarEstudiantes(
        vinculados: _estudiantesVinculados,
        recogidas: _recogidas,
        placa: _placa,
      );

  void _reengancharPlaca(String uid, String placa) {
    _subBus?.cancel();
    _subRecogidas?.cancel();
    _subRuta?.cancel();
    _firmaParadasPublicas = null;

    _subRuta = _streams.de('rutas/$uid').listen(_alActualizarRutaDoc);

    if (placa.isEmpty) {
      setState(() {
        _miPosicion = null;
        _recogidas = <ParadaRecogida>[];
        _esRutaActiva = false;
      });
      return;
    }

    _subBus = _streams.de('buses/$placa').listen(_alActualizarBus);
    // La consulta va por `driverUid`, no por placa: es el campo que las reglas
    // pueden demostrar en una consulta y lo que cierra la lectura de nombre y
    // teléfono al conductor del bus. Un conductor con dos placas filtra en
    // Dart la suya en `_alActualizarRecogidas`.
    _subRecogidas = _streams
        .deConsulta(
          'recogida-conductor/$uid',
          () => FirebaseFirestore.instance
              .collection('recogida')
              .where('driverUid', isEqualTo: uid)
              .snapshots(),
        )
        .listen(_alActualizarRecogidas);

    _reanudarRutaSiEstabaActiva(uid, placa);
  }

  void _alActualizarRutaDoc(DocumentSnapshot snap) {
    if (!mounted) return;
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
    final estados = estadoParadas is Map<String, dynamic>
        ? estadoParadas
        : <String, dynamic>{};

    setState(() {
      _destino = punto;
      _nombreDestino = nombre;
      _estadoParadas = estados;
    });
    _programarCalculoRuta(forzar: true);
  }

  // --- Estado de las paradas -------------------------------------------------

  /// Momento en que se confirmó que el estudiante [studentId] subió, o `null`.
  Timestamp? _subioEn(String studentId) {
    final estado = _estadoParadas[studentId];
    if (estado is! Map) return null;
    final valor = estado['subioEn'];
    return valor is Timestamp ? valor : null;
  }

  bool _subio(String studentId) => _subioEn(studentId) != null;

  /// Copia mutable del estado de la parada [studentId], para no mutar el mapa
  /// leído de Firestore.
  Map<String, dynamic> _estadoDe(String studentId) {
    final valor = _estadoParadas[studentId];
    return valor is Map ? Map<String, dynamic>.from(valor) : <String, dynamic>{};
  }

  void _alActualizarBus(DocumentSnapshot snap) {
    final datos = snap.data();
    final mapa = datos is Map<String, dynamic> ? datos : <String, dynamic>{};
    final uid = _usuario?.uid;

    final lat = mapa['lat'];
    final lng = mapa['lng'];
    LatLng? posicion;
    if (lat is num && lng is num) {
      posicion = LatLng(lat.toDouble(), lng.toDouble());
    }
    final latU = mapa['ultimaLat'];
    final lngU = mapa['ultimaLng'];
    LatLng? ultima;
    if (latU is num && lngU is num) {
      ultima = LatLng(latU.toDouble(), lngU.toDouble());
    }
    final rumbo = mapa['rumbo'];

    final activa =
        uid != null && mapa['driverUid'] == uid && mapa['enMovimiento'] == true;

    if (!mounted) return;
    setState(() {
      _miPosicion = posicion;
      if (posicion != null) _ultimaPosicion = posicion;
      if (ultima != null) _ultimaPosicion ??= ultima;
      _rumbo = rumbo is num ? rumbo.toDouble() : 0;
      if (!activa) _esRutaActiva = false;
    });

    // La cámara sigue al bus mientras el conductor no la haya movido a mano.
    if (_siguiendo && posicion != null && posicion != _ultimaPosicionCentrada) {
      _ultimaPosicionCentrada = posicion;
      _seguirConSiguiente();
    } else if (!_esRutaActiva) {
      _centrarEnUltimaSiHaceFalta();
    }

    _programarCalculoRuta();
  }

  /// Centra el mapa en la última posición conocida del bus una sola vez, para
  /// no abrir en un centro por defecto cuando aún no hay ruta activa.
  void _centrarEnUltimaSiHaceFalta() {
    if (_centradoInicial || !mounted) return;
    final ultima = _ultimaPosicion;
    if (ultima == null) return;
    _centradoInicial = true;
    _moviendoPorCodigo = true;
    _mapa?.animateCamera(CameraUpdate.newLatLngZoom(ultima, 15));
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      _moviendoPorCodigo = false;
    });
  }

  void _alActualizarRecogidas(QuerySnapshot snap) {
    final lista = <ParadaRecogida>[];
    for (final doc in snap.docs) {
      final datos = doc.data();
      if (datos is! Map<String, dynamic>) continue;
      // La consulta trae todos los puntos del conductor (puede tener más de una
      // placa); el mapa y la ruta solo deben ver los de la placa abierta.
      final placaDoc =
          (datos['busPlate'] ?? '').toString().trim().toUpperCase();
      if (placaDoc.isNotEmpty && placaDoc != _placa) continue;
      final lat = datos['lat'];
      final lng = datos['lng'];
      if (lat is! num || lng is! num) continue;
      final etiqueta = (datos['childName'] ?? datos['parentName'] ?? '')
          .toString()
          .trim();
      final visto = datos['avisoVistoEn'];
      final parentUid = (datos['parentUid'] ?? doc.id).toString().trim();
      final parentName = datos['parentName']?.toString().trim() ?? '';
      final parentPhone = datos['parentPhone']?.toString().trim() ?? '';
      lista.add(
        ParadaRecogida(
          studentId: doc.id,
          parentUid: parentUid.isEmpty ? doc.id : parentUid,
          punto: LatLng(lat.toDouble(), lng.toDouble()),
          etiqueta: etiqueta.isEmpty ? 'un estudiante' : etiqueta,
          parentName: parentName.isEmpty ? null : parentName,
          parentPhone: parentPhone.isEmpty ? null : parentPhone,
          avisoVistoEn: visto is Timestamp ? visto.toDate() : null,
        ),
      );
    }
    if (!mounted) return;
    setState(() => _recogidas = lista);
    // Copia anónima para los padres: `recogida` ya no es legible por cualquiera.
    _publicarParadasPublicas();
    _programarCalculoRuta(forzar: true);
  }

  /// Publica en `buses/{placa}.paradasPublicas` solo `{id, lat, lng}`.
  ///
  /// Es la única forma que tiene el padre de dibujar las paradas de otros
  /// hijos: `recogida` contiene nombre y teléfono del padre y sus reglas ya no
  /// permiten leerla a cualquier cuenta autenticada. Se escribe desde el
  /// conductor, que es el dueño del bus y el único que puede leerlas todas.
  Future<void> _publicarParadasPublicas() async {
    final uid = _usuario?.uid;
    if (uid == null || _placa.isEmpty) return;

    final List<Map<String, dynamic>> publicas = <Map<String, dynamic>>[
      for (final parada in _recogidas)
        <String, dynamic>{
          'id': parada.studentId,
          'lat': parada.punto.latitude,
          'lng': parada.punto.longitude,
        },
    ];

    final String firma = publicas
        .map((Map<String, dynamic> p) =>
            '${p['id']}|${p['lat']}|${p['lng']}')
        .join(';');
    if (firma == _firmaParadasPublicas) return;
    _firmaParadasPublicas = firma;

    try {
      await FirebaseFirestore.instance.collection('buses').doc(_placa).set(
        <String, dynamic>{
          'placa': _placa,
          // `driverUid` se incluye para que el `create` de un bus que aún no
          // existe pase las reglas; en un bus propio el valor no cambia.
          'driverUid': uid,
          'paradasPublicas': publicas,
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('DriverRuta: no se pudieron publicar las paradas: $e');
      // Se permite reintentar en la próxima actualización de `recogida`.
      _firmaParadasPublicas = null;
    }
  }

  /// Pide el colegio de destino. Se elige en el mapa, tipo app de transporte.
  Future<void> _elegirDestino() async {
    final uid = _usuario?.uid;
    if (uid == null) return;

    final LatLng? punto = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute<LatLng>(
        builder: (context) => MapPickerScreen(
          titulo: 'Colegio de destino',
          textoBoton: 'Usar este colegio',
          centroInicial: _miPosicion,
          colorPin: AppColors.danger,
          ayuda: 'Mueve el mapa y pon el pin sobre el colegio al que llevas '
              'a los estudiantes.',
        ),
      ),
    );
    if (punto == null || !mounted) return;

    final String? nombre = await _pedirNombreDestino();
    if (!mounted) return;

    try {
      await FirebaseFirestore.instance.collection('rutas').doc(uid).set({
        'destino': {
          'lat': punto.latitude,
          'lng': punto.longitude,
          'nombre': (nombre ?? '').trim(),
        },
      }, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      _mostrarAviso(_mensajeAlFallar(e), esError: true);
    }
  }

  Future<String?> _pedirNombreDestino() async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Nombre del colegio'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Ej. Colegio San José',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Omitir'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Guardar'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  /// Publica el viaje y enciende el GPS. Marca el bus en ruta y arranca con el
  /// estado de paradas en blanco.
  Future<void> _iniciarRuta() async {
    if (_destino == null) {
      _mostrarAviso('Elige el colegio de destino antes de iniciar.', esError: true);
      return;
    }

    final uid = _usuario?.uid;
    if (uid == null) {
      _mostrarAviso('Tu sesión venció. Vuelve a iniciar sesión.', esError: true);
      return;
    }
    if (_placa.isEmpty) {
      _mostrarAviso(
        'Tu perfil no tiene placa asignada. Contacta al administrador.',
        esError: true,
      );
      return;
    }

    setState(() => _isIniciando = true);
    try {
      await FirebaseFirestore.instance.collection('rutas').doc(uid).set(
        {'estadoParadas': <String, dynamic>{}},
        SetOptions(merge: true),
      );

      await FirebaseFirestore.instance
          .collection('buses')
          .doc(_placa)
          .set({
            'placa': _placa,
            'driverUid': uid,
            'conductor': _nombreConductor,
            if (_telefonoConductor.isNotEmpty)
              'conductorPhone': _telefonoConductor,
            'estadoRuta': 'En ruta',
            'enMovimiento': true,
            'paradaActual': 0,
            'rutaIniciada': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      // Publica ya las paradas anónimas (aunque el listener no haya cambiado)
      // para que el padre vea el resto de puntos desde el primer tick.
      await _publicarParadasPublicas();

      final AvisoGps avisoGps = await _gps.iniciar(_placa);

      if (!mounted) return;
      setState(() {
        // La ruta está activa en cuanto el documento del bus se escribió: los
        // padres ya la ven. El GPS es un extra que puede fallar (permiso de
        // ubicación o notificaciones) sin deshacer el viaje. Antes esto era
        // `errorGps == null`, así que negar las notificaciones dejaba al
        // conductor sin "Ya recogí" ni "Finalizar Ruta" aunque el bus ya
        // estuviera en movimiento.
        _esRutaActiva = true;
        _estadoParadas = <String, dynamic>{};
        // Al reiniciar, la referencia de "última posición calculada" puede ser
        // la del viaje anterior; si el bus no se movió, el cálculo no se
        // volvería a disparar y el mapa quedaría sin línea.
        _ultimaPosicionCalculo = null;
      });
      _programarCalculoRuta(forzar: true);
      _mostrarAviso(
        avisoGps.error ??
            avisoGps.advertencia ??
            'Ruta iniciada. Los padres ya ven tu ubicación y tus paradas.',
        esError: avisoGps.error != null,
      );
    } catch (e) {
      if (!mounted) return;
      _mostrarAviso(_mensajeAlFallar(e), esError: true);
    } finally {
      if (mounted) setState(() => _isIniciando = false);
    }
  }

  /// Cierra la ruta en orden: primero la archiva en el historial (con la hora
  /// de cada recogida), luego marca el bus como finalizado y borra su
  /// telemetría —para que el mapa del padre se limpie—, y por último vacía el
  /// estado de las paradas para reiniciar el aviso de llegada.
  Future<void> _finalizarRuta() async {
    final uid = _usuario?.uid;
    await _gps.detener();

    if (uid != null) {
      try {
        await _archivarRuta(uid);
      } catch (_) {
        // Si el archivo falla la ruta se cierra igual: no vale dejar el bus
        // marcado "En ruta" solo por no poder guardar el historial.
      }
    }

    if (_placa.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('buses').doc(_placa).set({
          'estadoRuta': 'Finalizada',
          'enMovimiento': false,
          'rutaFinalizada': FieldValue.serverTimestamp(),
          // Se borra la telemetría para que el padre no vea el bus congelado
          // en el último punto: sin `lat`/`lng` no dibuja marcador ni ruta. Se
          // conservan `ultimaLat`/`ultimaLng` para que el mapa abra ahí.
          'lat': FieldValue.delete(),
          'lng': FieldValue.delete(),
          'rumbo': FieldValue.delete(),
          'velocidad': FieldValue.delete(),
          'precision': FieldValue.delete(),
          'ultimaActualizacion': FieldValue.delete(),
          // Las paradas anónimas solo tienen sentido mientras se sigue la
          // ruta; al cerrarla se dejan de compartir.
          'paradasPublicas': FieldValue.delete(),
        }, SetOptions(merge: true));
      } catch (e) {
        if (mounted) _mostrarAviso(_mensajeAlFallar(e), esError: true);
      }
    }

    if (uid != null) {
      try {
        await FirebaseFirestore.instance.collection('rutas').doc(uid).set({
          'estadoParadas': <String, dynamic>{},
        }, SetOptions(merge: true));
      } catch (_) {
        // No es crítico: el historial ya quedó guardado.
      }
    }

    if (!mounted) return;
    setState(() {
      _esRutaActiva = false;
      _estadoParadas = <String, dynamic>{};
      _rutaPuntos = <LatLng>[];
      _ultimaPosicionCalculo = null;
    });
    _firmaParadasPublicas = null;
    _mostrarAviso('Ruta finalizada. Quedó guardada en "Recorrido".');
  }

  /// Guarda una foto de la ruta que acaba de terminar en
  /// `rutas/{uid}/historial`, con la hora en que cada estudiante subió al bus.
  /// Es lo que la pestaña "Recorrido" del padre muestra cuando el viaje cerró.
  Future<void> _archivarRuta(String uid) async {
    Timestamp? iniciada;
    if (_placa.isNotEmpty) {
      final busSnap = await FirebaseFirestore.instance
          .collection('buses')
          .doc(_placa)
          .get();
      final valor = busSnap.data()?['rutaIniciada'];
      if (valor is Timestamp) iniciada = valor;
    }

    var totalSubidos = 0;
    final paradas = <Map<String, dynamic>>[];
    for (final parada in _recogidas) {
      final subio = _subioEn(parada.studentId);
      if (subio != null) totalSubidos++;
      paradas.add({
        // `studentId` es la clave nueva; `parentUid` se conserva para que los
        // registros viejos y el panel del padre sigan leyendo la misma forma.
        'studentId': parada.studentId,
        'parentUid': parada.parentUid,
        'etiqueta': parada.etiqueta,
        'lat': parada.punto.latitude,
        'lng': parada.punto.longitude,
        'recogido': subio != null,
        'hora': ?subio,
      });
    }

    await FirebaseFirestore.instance
        .collection('rutas')
        .doc(uid)
        .collection('historial')
        .add({
      'destino': _destino == null
          ? null
          : {
              'lat': _destino!.latitude,
              'lng': _destino!.longitude,
              'nombre': _nombreDestino,
            },
      'paradas': paradas,
      'totalParadas': paradas.length,
      'totalRecogidos': totalSubidos,
      'iniciada': iniciada,
      'finalizada': FieldValue.serverTimestamp(),
    });
  }

  /// El conductor confirma con "Ya recogí" que el estudiante subió al bus.
  /// Cierra la parada (`subioEn`) y la ruta continúa con la siguiente.
  Future<void> _marcarSubio(ParadaRecogida parada) async {
    final uid = _usuario?.uid;
    if (uid == null) return;

    // Estado previo normalizado: `estadoParadas` se reescribe entero abajo, así
    // que las entradas de los demás padres tienen que viajar tal cual.
    final Map<String, dynamic> previos = <String, dynamic>{
      for (final entrada in _estadoParadas.entries)
        entrada.key: entrada.value is Map
            ? Map<String, dynamic>.from(entrada.value as Map)
            : entrada.value,
    };

    // `Timestamp.now()` y no `FieldValue.serverTimestamp()`: mientras el
    // servidor no confirma, el snapshot local entrega ese campo en `null`, y el
    // listener lo leería como "todavía no recogido", deshaciendo el toque igual
    // que el bug de abajo. La hora local ya era la que se archivaba.
    final Map<String, dynamic> actualizado = <String, dynamic>{
      ...previos,
      parada.studentId: <String, dynamic>{
        ..._estadoDe(parada.studentId),
        'subioEn': Timestamp.now(),
      },
    };

    setState(() => _estadoParadas = actualizado);
    // La parada quedó cerrada: el tramo salta a la siguiente recogida (o al
    // colegio si ya no queda ninguna).
    _programarCalculoRuta(forzar: true);
    try {
      // Se escribe **el mapa completo**, no una ruta con puntos
      // (`'estadoParadas.<uid>.subioEn'`). `set(merge: true)` no interpreta
      // esa notación: guarda el nombre con puntos como un campo literal, así
      // que `estadoParadas` seguía vacío en el documento. El listener devolvía
      // ese mapa vacío un instante después y deshacía el "ya recogí" —la
      // parada volvía a estar pendiente en el panel del conductor y el padre
      // nunca veía `subioEn`—, y por eso la ruta no avanzaba a la siguiente.
      await FirebaseFirestore.instance.collection('rutas').doc(uid).set({
        'estadoParadas': actualizado,
      }, SetOptions(merge: true));
      if (!mounted) return;
      _mostrarAviso('${parada.etiqueta} recogido. Continúa con la ruta.');
    } catch (e) {
      if (!mounted) return;
      // Si la escritura falló, la parada no está cerrada de verdad: se
      // devuelve el estado anterior para no salir con un "recogido" falso.
      setState(() => _estadoParadas = previos);
      _programarCalculoRuta(forzar: true);
      _mostrarAviso(_mensajeAlFallar(e), esError: true);
    }
  }

  /// Si la app se cerró con una ruta en curso, la retoma al reabrir.
  Future<void> _reanudarRutaSiEstabaActiva(String uid, String placa) async {
    try {
      final bus =
          await FirebaseFirestore.instance.collection('buses').doc(placa).get();
      final activa = bus.exists &&
          bus.get('driverUid') == uid &&
          bus.get('enMovimiento') == true;
      if (!activa) return;

      // La ruta ya figura activa en Firestore, así que el panel debe mostrarla
      // así aunque el GPS no arranque. Si no, el conductor veía "Iniciar Ruta"
      // sobre un viaje que los padres ya estaban siguiendo.
      if (!mounted) return;
      setState(() => _esRutaActiva = true);

      final AvisoGps aviso = await _gps.iniciar(placa);
      if (!mounted) return;
      if (aviso.error != null) {
        _mostrarAviso(aviso.error!, esError: true);
      }
    } catch (_) {
      // Si falla, el conductor puede volver a pulsar "Iniciar Ruta".
    }
  }

  // --- Cálculo de la ruta con OSRM ------------------------------------------

  /// Agrupa varios cambios seguidos (posición, recogidas, recogidos) en un solo
  /// cálculo, y no recalcula si el bus apenas se movió: OSRM es un servicio
  /// público y ajeno, no hay que golpearlo en cada tick del GPS.
  void _programarCalculoRuta({bool forzar = false}) {
    if (!_esRutaActiva) {
      if (_rutaPuntos.isNotEmpty) setState(() => _rutaPuntos = <LatLng>[]);
      return;
    }

    // Si todavía no hay línea en el mapa, se calcula aunque el bus esté quieto.
    // El cálculo forzado que dispara "Iniciar Ruta" puede llegar antes de que
    // `_esRutaActiva` sea `true` y descartarse; sin esta excepción, un bus
    // detenido (sin cambios de posición > 25 m) se quedaba sin ruta, sobre todo
    // cuando no hay paradas de recogida y el único tramo es bus → colegio.
    if (!forzar && !_movioSuficiente() && _rutaPuntos.isNotEmpty) return;

    _debounceRuta?.cancel();
    _debounceRuta = Timer(
      const Duration(milliseconds: 600),
      () => _calcularRuta(),
    );
  }

  bool _movioSuficiente() {
    final pos = _miPosicion;
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

  /// Arma el recorrido **tramo por tramo**: mientras queden recogidas
  /// pendientes, la línea va del bus a la siguiente parada (la más cercana);
  /// cuando ya recogió a todos, va al colegio. Así el conductor no ve de un
  /// tirón todo el recorrido que aún no le toca.
  List<LatLng> _rutaOrdenada() {
    final LatLng? desde = _miPosicion;
    final ParadaRecogida? siguiente = _siguienteParada();

    return <LatLng>[
      ?desde,
      if (siguiente != null) siguiente.punto else ?_destino,
    ];
  }

  double _distancia(LatLng a, LatLng b) =>
      Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);

  Future<void> _calcularRuta() async {
    if (!mounted || _calculandoRuta) return;
    final puntos = _rutaOrdenada();
    if (puntos.length < 2) {
      setState(() {
        _rutaPuntos = <LatLng>[];
        _resumenRuta = null;
      });
      return;
    }

    _calculandoRuta = true;
    _ultimaPosicionCalculo = _miPosicion;
    final RutaCalculada? calculada = await _rutas.calcular(puntos);
    _calculandoRuta = false;
    if (!mounted) return;

    setState(() {
      if (calculada == null) {
        // Sin ruta por carretera (servidor caído): se dibuja la línea recta
        // entre los puntos para no dejar el mapa sin guía.
        _rutaPuntos = puntos;
        _resumenRuta = null;
      } else {
        _rutaPuntos = calculada.puntos;
        final String km = (calculada.distanciaMetros / 1000).toStringAsFixed(1);
        _resumenRuta = '${calculada.duracionLegible} · $km km';
      }
    });
    // Con el seguimiento activo no se encuadra toda la ruta: la cámara va
    // pegada al bus. El botón "ver ruta completa" pausa el seguimiento y ahí sí
    // se ajusta el encuadre a todos los puntos.
    if (!_siguiendo) _encuadrarRuta();
  }

  /// Centra la cámara en el bus y la siguiente parada, sin alejarse para
  /// abarcar toda la ruta: el conductor solo necesita ver hasta el punto más
  /// cercano que le queda por delante.
  Future<void> _seguirConSiguiente() async {
    final pos = _miPosicion;
    if (pos == null) return;

    final objetivo = _siguienteParada()?.punto ?? _destino;
    _moviendoPorCodigo = true;
    try {
      if (objetivo == null || objetivo == pos) {
        await _mapa?.animateCamera(CameraUpdate.newLatLngZoom(pos, 16));
      } else {
        final bounds = LatLngBounds(
          southwest: LatLng(
            pos.latitude < objetivo.latitude ? pos.latitude : objetivo.latitude,
            pos.longitude < objetivo.longitude ? pos.longitude : objetivo.longitude,
          ),
          northeast: LatLng(
            pos.latitude > objetivo.latitude ? pos.latitude : objetivo.latitude,
            pos.longitude > objetivo.longitude ? pos.longitude : objetivo.longitude,
          ),
        );
        await _mapa?.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 90),
        );
      }
    } catch (_) {
      // Mapa todavía sin crear o bounds degenerados: se ignora.
    } finally {
      // `onCameraMoveStarted` puede llegar después de que el Future resuelva;
      // se baja la bandera con un retardo para no confundir este movimiento
      // programado con un gesto del conductor.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      _moviendoPorCodigo = false;
    }
  }

  Future<void> _encuadrarRuta() async {
    final controlador = _mapa;
    if (controlador == null || _rutaPuntos.isEmpty) return;

    final lats = _rutaPuntos.map((p) => p.latitude);
    final lngs = _rutaPuntos.map((p) => p.longitude);
    final bounds = LatLngBounds(
      southwest: LatLng(lats.reduce((a, b) => a < b ? a : b), lngs.reduce((a, b) => a < b ? a : b)),
      northeast: LatLng(lats.reduce((a, b) => a > b ? a : b), lngs.reduce((a, b) => a > b ? a : b)),
    );
    _moviendoPorCodigo = true;
    try {
      await controlador.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 64),
      );
    } catch (_) {
      // Bounds degenerados (un solo punto): se ignora.
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      _moviendoPorCodigo = false;
    }
  }

  // --- Navegación y avisos ---------------------------------------------------

  /// Abre el panel con el QR y el código que los padres usan para vincular a
  /// sus hijos a este bus. El código se genera la primera vez que se abre.
  Future<void> _abrirCodigoBus() async {
    if (_placa.isEmpty) {
      _mostrarAviso(
        'Tu perfil no tiene placa asignada. Contacta al administrador.',
        esError: true,
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DriverQrScreen(
          placa: _placa,
          conductor: _nombreConductor,
        ),
      ),
    );
  }

  Future<void> _cerrarSesion() async {
    final NavigatorState nav = Navigator.of(context);
    try {
      await _gps.detener();
      await GoogleAuth.cerrarSesion();
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      // Si falla el cierre de sesión, se sale igual: no dejar al conductor
      // atrapado es más importante que limpiar la sesión a la perfección.
    }
    await PreferenciasDeSesion.olvidarSesion();
    if (!mounted) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (context) => const PantallaLoginPaisaje()),
      (route) => false,
    );
  }

  String _mensajeAlFallar(Object e) {
    if (e is FirebaseException && e.code == 'permission-denied') {
      return 'No se pudo guardar: la base de datos no permite esta escritura. '
          'Hay que actualizar las reglas de seguridad.';
    }
    return 'No se pudo guardar. Revisa tu conexión e inténtalo otra vez.';
  }

  void _mostrarAviso(String texto, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: esError ? AppColors.danger : AppColors.success,
      ),
    );
  }

  // --- Interfaz --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: BusNavBar(
        destinos: _destinos,
        currentIndex: _pestana,
        onChanged: (i) => setState(() => _pestana = i),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildEncabezado(),
            const SizedBox(height: 12),
            // Las cuatro pestañas viven a la vez: cambiar de pestaña no
            // destruye el mapa (ni su cámara) ni corta los listeners.
            Expanded(
              child: IndexedStack(
                index: _pestana,
                children: [
                  _buildPestanaRuta(),
                  _buildPestanaRecorrido(),
                  _buildPestanaEstudiantes(),
                  _buildPestanaPerfil(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Encabezado del panel. El QR queda a la izquierda y el cierre de sesión se
  /// movió a "Mi Perfil", igual que en el panel del padre.
  Widget _buildEncabezado() {
    return BusHeader(
      title: _nombreConductor.isEmpty
          ? 'Bienvenido'
          : 'Bienvenido, $_nombreConductor',
      subtitle: _placa.isEmpty
          ? 'Panel del conductor'
          : 'Panel del conductor · Bus $_placa',
      titleSize: 21,
      fullBleed: true,
      leading: BusIconButton(
        icon: Icons.qr_code_2_rounded,
        tooltip: 'Código del bus',
        onTap: _abrirCodigoBus,
      ),
      trailing: const BusIconBadge(
        icon: Icons.directions_bus_filled_rounded,
        size: 46,
        color: Colors.white,
      ),
    );
  }

  /// Pestaña "Ruta": el mapa en vivo y el panel de control del viaje.
  Widget _buildPestanaRuta() {
    return Column(
      children: [
        Expanded(child: _buildMapa()),
        _buildPanelInferior(),
      ],
    );
  }

  /// Pestaña "Recorrido": el mismo itinerario que ve el padre, sin marcar
  /// "(tu punto)" y con respaldo en el uid del conductor para ver el destino
  /// planificado antes de iniciar la ruta.
  Widget _buildPestanaRecorrido() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: RecorridoBusView(
        streams: _streams,
        placa: _placa,
        driverUidRespaldo: _usuario?.uid,
        textoSinBus:
            'Tu perfil no tiene placa asignada. Contacta al administrador.',
        textoSinRutaConductor:
            'Elige el colegio de destino en la pestaña "Ruta" para armar el '
            'recorrido.',
      ),
    );
  }

  /// Pestaña "Estudiantes": quiénes suben a este bus, con el botón para llamar
  /// al padre. Deliberadamente **no** muestra el estado de recogida: eso se
  /// maneja en la pestaña "Ruta" con "Ya recogí".
  Widget _buildPestanaEstudiantes() {
    final estudiantes = _estudiantesDelBus;
    final sinPunto = estudiantes.where((e) => !e.tienePunto).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: estudiantes.isEmpty
              ? BusCard(
                  padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
                  child: Column(
                    children: [
                      const BusIconBadge(
                        icon: Icons.family_restroom_rounded,
                        size: 68,
                        color: AppColors.primaryPale,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Aún no hay estudiantes en tu bus',
                        textAlign: TextAlign.center,
                        style: busText(size: 17, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Comparte el código del bus con los padres para que '
                        'vinculen a sus hijos. Aparecerán aquí apenas se '
                        'vinculen, aunque todavía no marquen su punto de '
                        'recogida.',
                        textAlign: TextAlign.center,
                        style: busText(
                          size: 12.5,
                          color: AppColors.textMuted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                )
              : BusSeccion(
                  titulo: 'Estudiantes',
                  subtitulo: estudiantes.length == 1
                      ? '1 estudiante en tu bus'
                      : '${estudiantes.length} estudiantes en tu bus',
                  icon: Icons.family_restroom_rounded,
                  children: [
                    if (sinPunto > 0)
                      BusInfoBox(
                        icon: Icons.location_off_rounded,
                        iconColor: AppColors.textMuted,
                        child: Text(
                          sinPunto == 1
                              ? 'Un estudiante todavía no tiene punto de '
                                  'recogida. Su padre debe abrir la pestaña '
                                  '"Ruta" y marcar "Mi punto de recogida".'
                              : '$sinPunto estudiantes todavía no tienen punto '
                                  'de recogida. Sus padres deben marcarlo en '
                                  'la pestaña "Ruta".',
                          style: busText(
                            size: 12.5,
                            color: AppColors.textStrong,
                            height: 1.4,
                          ),
                        ),
                      ),
                    for (final estudiante in estudiantes)
                      _buildFilaEstudiante(estudiante),
                  ],
                ),
        ),
      ),
    );
  }

  /// Renglón de un estudiante: nombre, estado del punto y el botón para llamar
  /// al padre.
  Widget _buildFilaEstudiante(EstudianteBus estudiante) {
    final String? telefono = estudiante.parentPhone;
    final bool puedeLlamar = telefono != null && telefono.isNotEmpty;
    final String detalle;
    if (!estudiante.tienePunto) {
      detalle = 'Sin punto de recogida';
    } else if (estudiante.parentName == null) {
      detalle = 'Padre de familia';
    } else {
      detalle = 'Padre: ${estudiante.parentName}';
    }

    final String motivoSinLlamada = !estudiante.tienePunto
        ? 'El padre de ${estudiante.nombre} todavía no marcó el punto de '
            'recogida, así que aún no tenemos su teléfono.'
        : 'El padre de ${estudiante.nombre} todavía no registró su teléfono.';

    return BusOpcion(
      icon: estudiante.tienePunto
          ? Icons.face_rounded
          : Icons.location_off_rounded,
      title: estudiante.nombre,
      subtitle: detalle,
      onTap: puedeLlamar
          ? () => _llamarPadre(telefono)
          : () => _mostrarAviso(motivoSinLlamada),
      trailing: IconButton(
        tooltip: puedeLlamar
            ? 'Llamar al padre de ${estudiante.nombre}'
            : 'Todavía no hay teléfono del padre',
        icon: const Icon(Icons.call_rounded),
        color: puedeLlamar ? AppColors.primaryDeep : AppColors.textMuted,
        onPressed: puedeLlamar ? () => _llamarPadre(telefono) : null,
      ),
    );
  }

  Future<void> _llamarPadre(String telefono) async {
    final bool abierto = await PhoneLauncher.llamar(telefono);
    if (abierto || !mounted) return;
    _mostrarAviso('No se pudo abrir el marcador.', esError: true);
  }

  /// Pestaña "Mi Perfil": identidad del conductor y opciones de la cuenta.
  Widget _buildPestanaPerfil() {
    final String nombre = _nombreConductor.isEmpty
        ? 'Conductor'
        : _nombreConductor;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BusCard(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: AppColors.ink,
                        size: 36,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nombre,
                            style: busText(size: 20, weight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _placa.isEmpty
                                ? 'Sin placa asignada'
                                : 'Conductor del bus $_placa',
                            style: busText(
                              size: 13,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              BusSeccion(
                titulo: 'Opciones',
                subtitulo: 'Administra tu cuenta',
                icon: Icons.settings_rounded,
                children: [
                  BusOpcion(
                    icon: Icons.person_outline_rounded,
                    title: 'Mis datos',
                    subtitle: 'Tu cuenta y los datos del bus',
                    onTap: _abrirMisDatos,
                  ),
                  BusOpcion(
                    icon: Icons.lock_outline_rounded,
                    title: 'Cambiar contraseña',
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const ChangePasswordScreen(),
                      ),
                    ),
                  ),
                  BusOpcion(
                    icon: Icons.info_outline_rounded,
                    title: 'Acerca de',
                    subtitle: 'Versión $kBusTrackVersion',
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const AcercaDeScreen(),
                      ),
                    ),
                  ),
                  BusOpcion(
                    icon: Icons.logout_rounded,
                    title: 'Cerrar sesión',
                    color: AppColors.danger,
                    onTap: _cerrarSesion,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _abrirMisDatos() async {
    final String? uid = _usuario?.uid;
    if (uid == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DriverDatosScreen(streams: _streams, uid: uid),
      ),
    );
  }

  Widget _buildMapa() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _miPosicion ??
                    _ultimaPosicion ??
                    const LatLng(4.60971, -74.08175),
                zoom: _miPosicion == null ? 12 : 15,
              ),
              onMapCreated: (c) => _mapa = c,
              onCameraMoveStarted: () {
                // Solo un gesto del conductor pausa el seguimiento; los
                // movimientos que hace la app para seguirlo no cuentan.
                if (!_moviendoPorCodigo && _siguiendo) {
                  setState(() => _siguiendo = false);
                }
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              markers: _buildMarcadores(),
              polylines: _buildPolilineas(),
            ),
            _buildChipCoordenadas(),
            if (_cargandoPerfil || _calculandoRuta)
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
              bottom: 10,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'seguir_mi',
                    backgroundColor:
                        _siguiendo ? AppColors.primary : AppColors.surface,
                    foregroundColor: AppColors.ink,
                    onPressed: () {
                      setState(() {
                        _siguiendo = true;
                        _ultimaPosicionCentrada = _miPosicion;
                      });
                      _seguirConSiguiente();
                    },
                    child: Icon(
                      _siguiendo
                          ? Icons.my_location
                          : Icons.location_disabled,
                    ),
                  ),
                  if (_rutaPuntos.length > 1) ...[
                    const SizedBox(height: 10),
                    FloatingActionButton.small(
                      heroTag: 'encuadrar_ruta',
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.ink,
                      onPressed: () {
                        setState(() => _siguiendo = false);
                        _encuadrarRuta();
                      },
                      child: const Icon(Icons.center_focus_strong),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Coordenadas del GPS en la esquina superior izquierda del mapa.
  ///
  /// Es la forma de comprobar de verdad si el dispositivo se está moviendo:
  /// el sexto decimal cambia cada ~11 cm, así que basta mirar los últimos
  /// dígitos. Sin esto, con el marcador quieto, no se distingue un avance real
  /// de un redondeo.
  Widget _buildChipCoordenadas() {
    final pos = _miPosicion;

    return Positioned(
      left: 10,
      top: 10,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BusStatusPill(
            label: pos == null ? 'Buscando GPS' : 'Mi posición',
            dotColor: pos == null ? AppColors.textMuted : AppColors.primary,
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
                    '${pos.latitude.toStringAsFixed(6)}, '
                    '${pos.longitude.toStringAsFixed(6)}',
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

  Set<Marker> _buildMarcadores() {
    final marcas = <Marker>{};

    final icono = _iconoBus;
    final pos = _miPosicion;
    if (pos != null && icono != null) {
      marcas.add(
        Marker(
          markerId: const MarkerId('bus'),
          position: pos,
          rotation: _rumbo,
          // `flat: false`: el bus queda como billboard (no se acuesta con el
          // mapa ni se agranda al alejar el zoom).
          flat: false,
          anchor: const Offset(0.5, 0.5),
          icon: icono,
          infoWindow: InfoWindow(
            title: _placa.isEmpty ? 'Mi bus' : 'Bus $_placa',
          ),
        ),
      );
    }

    for (final parada in _recogidas) {
      final subido = _subio(parada.studentId);
      final double tono =
          subido ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueOrange;
      final String detalle =
          subido ? 'Ya recogido' : 'Punto de recogida';
      marcas.add(
        Marker(
          markerId: MarkerId('recogida_${parada.studentId}'),
          position: parada.punto,
          icon: BitmapDescriptor.defaultMarkerWithHue(tono),
          infoWindow: InfoWindow(
            title: parada.etiqueta,
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
            snippet: 'Destino final',
          ),
        ),
      );
    }

    return marcas;
  }

  Set<Polyline> _buildPolilineas() {
    if (_rutaPuntos.length < 2) return <Polyline>{};
    return {
      Polyline(
        polylineId: const PolylineId('ruta'),
        points: _rutaPuntos,
        color: AppColors.ink,
        width: 5,
      ),
    };
  }

  Widget _buildPanelInferior() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: _destino == null ? _buildSinDestino() : _buildConDestino(),
      ),
    );
  }

  List<Widget> _buildSinDestino() {
    return [
      Row(
        children: [
          const BusIconBadge(
            icon: Icons.school_rounded,
            size: 44,
            color: AppColors.primaryPale,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Elige el colegio al que llevas a los estudiantes',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textStrong,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      BusInfoBox(
        icon: Icons.touch_app_rounded,
        iconColor: AppColors.textMuted,
        child: Text(
          'Toca el mapa para marcar el destino final. Las paradas salen solas: '
          'son los puntos de recogida que marcaron los padres.',
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: AppColors.textMuted,
            height: 1.35,
          ),
        ),
      ),
      const SizedBox(height: 14),
      BusPrimaryButton(
        label: 'Elegir colegio en el mapa',
        icon: Icons.school_rounded,
        onPressed: _elegirDestino,
      ),
      const SizedBox(height: 4),
      TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size.fromHeight(44),
        ),
        onPressed: _abrirCodigoBus,
        icon: const Icon(Icons.qr_code_2_rounded, size: 18),
        label: const Text('Compartir código con los padres'),
      ),
    ];
  }

  List<Widget> _buildConDestino() {
    final siguiente = _siguienteParada();

    return [
      Row(
        children: [
          const BusIconBadge(
            icon: Icons.school_rounded,
            size: 44,
            color: AppColors.primaryPale,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nombreDestino.isEmpty ? 'Colegio de destino' : _nombreDestino,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textStrong,
                  ),
                ),
                Text(
                  _resumenRuta == null
                      ? 'Destino final'
                      : 'Siguiente tramo: $_resumenRuta',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _elegirDestino,
            child: const Text('Cambiar'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (!_esRutaActiva)
        _buildResumenPendientes()
      else if (siguiente == null)
        _buildTodoRecogido()
      else
        _buildSiguienteParada(siguiente),
      const SizedBox(height: 14),
      if (_esRutaActiva)
        BusPrimaryButton(
          label: 'Finalizar Ruta',
          icon: Icons.stop_rounded,
          background: AppColors.danger,
          iconColor: Colors.white,
          loading: _isIniciando,
          onPressed: _finalizarRuta,
        )
      else
        BusPrimaryButton(
          label: 'Iniciar Ruta',
          icon: Icons.play_arrow_rounded,
          loading: _isIniciando,
          onPressed: _iniciarRuta,
        ),
    ];
  }

  /// Antes de arrancar: cuántos puntos de recogida hay para esta ruta.
  Widget _buildResumenPendientes() {
    final total = _recogidas.length;
    final texto = total == 0
        ? 'Aún no hay padres con punto de recogida en tu bus. Comparte el '
            'código del bus (arriba, en el QR) para que vinculen a sus hijos, '
            'o inicia la ruta y llévala directo al colegio.'
        : 'Tienes $total punto(s) de recogida para visitar.';

    return _cajaInfo(
      icono: Icons.route_outlined,
      texto: texto,
      colorIcono: AppColors.textMuted,
    );
  }

  Widget _buildTodoRecogido() {
    return _cajaInfo(
      icono: Icons.check_circle_outline,
      texto: 'Recogiste a todos. Sigue al colegio de destino.',
      colorIcono: AppColors.success,
    );
  }

  Widget _buildSiguienteParada(ParadaRecogida siguiente) {
    final pos = _miPosicion;
    final double? metros =
        pos == null ? null : _distancia(pos, siguiente.punto);
    final bool cerca = metros != null && metros <= _kRadioLlegadaMetros;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cajaInfo(
          icono: Icons.person_pin_circle_rounded,
          texto:
              'Siguiente parada: ${siguiente.etiqueta}'
              '${metros == null ? '' : ' · a ${metros.round()} m'}',
          colorIcono: AppColors.textStrong,
        ),
        const SizedBox(height: 10),
        BusPrimaryButton(
          label: 'Ya recogí a ${siguiente.etiqueta}',
          icon: Icons.how_to_reg_rounded,
          background: cerca ? AppColors.success : AppColors.ink,
          // Un solo toque cierra la parada y avanza el tramo. No se exige
          // estar dentro del radio para que un GPS con retraso no deje al
          // conductor sin poder marcar la recogida.
          onPressed: () => _marcarSubio(siguiente),
        ),
      ],
    );
  }

  Widget _cajaInfo({
    required IconData icono,
    required String texto,
    required Color colorIcono,
  }) {
    return BusInfoBox(
      icon: icono,
      iconColor: colorIcono,
      child: Text(
        texto,
        style: GoogleFonts.poppins(
          fontSize: 13,
          color: AppColors.textStrong,
          height: 1.3,
        ),
      ),
    );
  }

  /// La recogida pendiente más cercana al bus, que es la "siguiente parada".
  /// Una parada deja de estar pendiente cuando el estudiante subió (`subioEn`).
  ParadaRecogida? _siguienteParada() {
    final pendientes =
        _recogidas.where((p) => !_subio(p.studentId)).toList();
    if (pendientes.isEmpty) return null;

    final pos = _miPosicion;
    if (pos == null) return pendientes.first;

    pendientes.sort(
      (a, b) =>
          _distancia(pos, a.punto).compareTo(_distancia(pos, b.punto)),
    );
    return pendientes.first;
  }
}
