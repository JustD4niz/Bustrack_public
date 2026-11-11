import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'main.dart' show AppColors;
import 'models/hijo.dart';
import 'screens/acerca_de_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/child_form_screen.dart';
import 'screens/login_screen.dart';
import 'screens/parent_datos_screen.dart';
import 'screens/parent_hijos_screen.dart';
import 'services/document_stream.dart';
import 'services/google_auth.dart';
import 'services/hijos_service.dart';
import 'services/session_prefs.dart';
import 'widgets/bus_nav_bar.dart';
import 'widgets/bus_ui.dart';
import 'widgets/parent_map_view.dart';
import 'widgets/parent_vehiculo_view.dart';
import 'widgets/recorrido_bus_view.dart';

/// Índices de las pestañas de [BusNavBar]. El orden debe coincidir con
/// [_ParentHomeScreenState._destinos]; se usan como índices del `IndexedStack`
/// del panel: 0 "Ruta", 1 "Recorrido", 2 "Conductor", 3 "Mi Perfil".
///
/// "Ruta" (el mapa en vivo del bus) es la pestaña que abre por defecto, porque
/// es lo que el padre viene a mirar cuando entra.
const int _kPestanaRuta = 0;

/// Panel del padre: el mapa en vivo, el itinerario, el conductor y el perfil
/// (que incluye a los hijos).
///
/// Lee el perfil del padre de `usuarios/{uid}` y sus hijos de `estudiantes`.
/// El hijo legado (cuentas viejas, con `childName` dentro del perfil) se
/// sintetiza con [Hijo.legado] y se trata igual que los demás: su id es el uid
/// del padre, que es la clave que ya usaban `recogida` y `estadoParadas`.
///
/// El mapa, el recorrido y el conductor muestran **un** hijo a la vez. Con más
/// de uno aparece un selector sobre las pestañas; cada hijo puede ir en un bus
/// distinto, así que las tres vistas reciben la placa del seleccionado y no la
/// del perfil.
class ParentHomeScreen extends StatefulWidget {
  const ParentHomeScreen({super.key});

  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends State<ParentHomeScreen> {
  /// Destinos de la barra inferior. Compartida con el panel del conductor vía
  /// [BusNavBar], pero cada panel pasa los suyos.
  static const List<BusNavDestino> _destinos = <BusNavDestino>[
    BusNavDestino(icono: Icons.map_rounded, etiqueta: 'Ruta'),
    BusNavDestino(icono: Icons.route_rounded, etiqueta: 'Recorrido'),
    BusNavDestino(
      icono: Icons.directions_bus_filled_rounded,
      etiqueta: 'Conductor',
    ),
    BusNavDestino(icono: Icons.person_rounded, etiqueta: 'Mi Perfil'),
  ];

  /// Los `snapshots()` se reutilizan entre reconstrucciones; ver
  /// `StreamsDeDocumento`. Sin esto, los `StreamBuilder` se resuscribían en
  /// cada `setState` de la pantalla.
  final StreamsDeDocumento _streams = StreamsDeDocumento();

  /// Pestaña visible. El `IndexedStack` de abajo la usa como índice, así que
  /// cambiar de pestaña no reconstruye las otras ni pierde su scroll. Abre en
  /// "Ruta" (el mapa): es la sección principal del panel.
  int _pestana = _kPestanaRuta;

  /// Id del hijo cuyas vistas se están mostrando. `null` deja que se elija el
  /// primero; se conserva aunque la lista se reconstruya para que un snapshot
  /// no devuelva al padre al primer hijo.
  String? _hijoSeleccionadoId;

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
        child: Column(
          children: [
            _buildEncabezado(),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<DocumentSnapshot>(
                stream: _perfilPadre(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return const _Aviso(
                      texto: 'No se pudo cargar tu perfil.',
                    );
                  }

                  if (!snapshot.hasData || !snapshot.data!.exists) {
                    return const _Aviso(
                      texto: 'No encontramos un perfil asociado a tu cuenta.',
                    );
                  }

                  final datos = snapshot.data!.data() as Map<String, dynamic>;
                  return StreamBuilder<QuerySnapshot>(
                    stream: _hijosDelPadre(),
                    builder: (context, snapHijos) {
                      // El perfil ya llegó, pero la lista de hijos todavía no:
                      // pintar el panel vacío haría parpadear "sin hijos".
                      if (snapHijos.connectionState == ConnectionState.waiting &&
                          !snapHijos.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final hijos = _hijos(datos, snapHijos.data);
                      final seleccionado = _hijoSeleccionado(hijos);
                      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

                      // Las cuatro pestañas se construyen a la vez y solo una
                      // se pinta. Es lo que permite que cambiar de pestaña no
                      // tire los `ScrollController` ni corte un stream a medio
                      // camino.
                      return Column(
                        children: [
                          if (hijos.length > 1)
                            _buildSelectorHijos(hijos, seleccionado),
                          Expanded(
                            child: IndexedStack(
                              index: _pestana,
                              children: [
                                _buildRuta(datos, seleccionado, uid),
                                _buildRecorrido(seleccionado),
                                _buildVehiculo(seleccionado),
                                _buildPestana([
                                  _buildTarjetaPerfil(datos, hijos),
                                ]),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Perfil del padre autenticado. Devuelve `null` si todavía no hay sesión, en
  /// cuyo caso el `StreamBuilder` queda inactivo.
  Stream<DocumentSnapshot>? _perfilPadre() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return _streams.de('usuarios/${user.uid}');
  }

  /// Hijos nuevos del padre. Se cachea bajo una clave por uid para que el
  /// listener no se reabra en cada reconstrucción.
  Stream<QuerySnapshot>? _hijosDelPadre() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return _streams.deConsulta(
      'estudiantes/${user.uid}',
      () => HijosService.consultaHijos(user.uid),
    );
  }

  /// Junta el hijo legado (si lo hay) con los documentos de `estudiantes`.
  ///
  /// El legado va primero para que una cuenta vieja siga abriendo en el mismo
  /// hijo que antes, incluso si con el tiempo agregó otros.
  List<Hijo> _hijos(Map<String, dynamic> datosPerfil, QuerySnapshot? snap) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return HijosService.hijosDesdeSnapshot(snap);
    return HijosService.listaCompleta(
      parentUid: user.uid,
      perfil: datosPerfil,
      snap: snap,
    );
  }

  /// Hijo seleccionado, tolerando que haya sido borrado o renombrado. Si el id
  /// guardado ya no existe, se usa el primero sin tocar el estado durante
  /// `build`.
  Hijo? _hijoSeleccionado(List<Hijo> hijos) {
    if (hijos.isEmpty) return null;
    final id = _hijoSeleccionadoId;
    if (id != null) {
      for (final hijo in hijos) {
        if (hijo.id == id) return hijo;
      }
    }
    return hijos.first;
  }

  /// Selector horizontal de hijos, visible solo cuando hay más de uno.
  Widget _buildSelectorHijos(List<Hijo> hijos, Hijo? seleccionado) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        itemCount: hijos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final hijo = hijos[i];
          final activo = hijo.id == seleccionado?.id;
          return Material(
            color: activo ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => setState(() => _hijoSeleccionadoId = hijo.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.face_rounded,
                      size: 17,
                      color: activo ? AppColors.ink : AppColors.textMuted,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      hijo.nombre,
                      style: busText(
                        size: 13,
                        weight: FontWeight.w700,
                        color: activo ? AppColors.ink : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Pestaña "Ruta": mapa en vivo del bus del hijo seleccionado.
  Widget _buildRuta(
    Map<String, dynamic> datosPerfil,
    Hijo? hijo,
    String uid,
  ) {
    if (hijo == null) return _buildSinHijos();
    if (!hijo.tieneBus) return _buildSinBus(hijo);

    return ParentMapView(
      streams: _streams,
      placa: hijo.busPlate,
      parentUid: uid,
      studentId: hijo.id,
      driverUid: hijo.driverUid,
      childName: hijo.nombre,
      parentName: _texto(datosPerfil['fullName']),
      parentPhone: _texto(datosPerfil['phone']),
    );
  }

  /// Pestaña "Recorrido": itinerario del bus del hijo seleccionado.
  Widget _buildRecorrido(Hijo? hijo) {
    if (hijo == null) return _buildSinHijos();
    if (!hijo.tieneBus) return _buildSinBus(hijo);

    return RecorridoBusView(
      streams: _streams,
      placa: hijo.busPlate,
      studentId: hijo.id,
    );
  }

  /// Pestaña "Conductor": quién lleva el bus del hijo seleccionado.
  Widget _buildVehiculo(Hijo? hijo) {
    if (hijo == null) return _buildSinHijos();
    if (!hijo.tieneBus) return _buildSinBus(hijo);

    return ParentVehiculoView(
      streams: _streams,
      placa: hijo.busPlate,
      driverNameRegistrado: hijo.driverName,
    );
  }

  /// Estado vacío cuando el padre todavía no registró a nadie.
  Widget _buildSinHijos() {
    return _buildPestana([
      BusCard(
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
              'Aún no has registrado a tu hijo',
              textAlign: TextAlign.center,
              style: busText(size: 17, weight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Agrégalo para ver la ruta del bus, marcar su punto de recogida '
              'y vincularlo con el conductor.',
              textAlign: TextAlign.center,
              style: busText(
                size: 12.5,
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            BusPrimaryButton(
              label: 'Agregar hijo',
              icon: Icons.person_add_alt_1_rounded,
              onPressed: _agregarHijo,
            ),
          ],
        ),
      ),
    ]);
  }

  /// Estado cuando el hijo existe pero todavía no tiene bus vinculado.
  Widget _buildSinBus(Hijo hijo) {
    return _buildPestana([
      BusCard(
        padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
        child: Column(
          children: [
            const BusIconBadge(
              icon: Icons.directions_bus_filled_rounded,
              size: 68,
              color: AppColors.primaryPale,
            ),
            const SizedBox(height: 16),
            Text(
              '${hijo.nombre} no tiene bus vinculado',
              textAlign: TextAlign.center,
              style: busText(size: 17, weight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Pídele al conductor su código o su QR y vincúlalo desde aquí. '
              'Sin bus no se puede seguir la ruta.',
              textAlign: TextAlign.center,
              style: busText(
                size: 12.5,
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            BusPrimaryButton(
              label: 'Vincular un bus',
              icon: Icons.qr_code_scanner_rounded,
              onPressed: () => _editarHijo(hijo),
            ),
          ],
        ),
      ),
    ]);
  }

  /// Envoltura de scroll compartida por las pestañas con datos: el mismo
  /// centrado y ancho máximo que usa el resto del panel.
  Widget _buildPestana(List<Widget> tarjetas) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: tarjetas,
          ),
        ),
      ),
    );
  }

  /// Barra superior con el título del panel.
  ///
  /// Encabezado amarillo con esquinas inferiores redondeadas, círculos
  /// decorativos claros y línea punteada de carretera, igual que el resto de
  /// paneles del rediseño.
  ///
  /// Ya no lleva el botón de cerrar sesión: se quitó de aquí a pedido del
  /// usuario ("esa opción tan fea en la parte superior"). Cerrar sesión vive
  /// ahora como una fila más de "Mi Perfil", junto a las otras acciones de la
  /// cuenta.
  Widget _buildEncabezado() {
    return const BusHeader(
      title: 'Panel de Padres',
      subtitle: 'Sigue la ruta escolar de tu hijo en tiempo real',
      titleSize: 23,
      fullBleed: true,
      trailing: BusIconBadge(
        icon: Icons.directions_bus_filled_rounded,
        size: 50,
        color: Colors.white,
      ),
    );
  }

  /// Cierra la sesión y vuelve al login.
  Future<void> _cerrarSesion(BuildContext context) async {
    // Se resuelven antes del primer `await`: después, `context` ya está detrás
    // de un async gap.
    final NavigatorState nav = Navigator.of(context);
    final ScaffoldMessengerState avisos = ScaffoldMessenger.of(context);
    try {
      await GoogleAuth.cerrarSesion();
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      // Un fallo al limpiar la sesión no debe dejar al padre atrapado en el
      // panel sin poder salir.
    }
    // Cierre de sesión explícito: la próxima apertura debe mostrar la
    // bienvenida, no el aviso de "no pudimos restaurar tu sesión".
    await PreferenciasDeSesion.olvidarSesion();
    // Antes de navegar: este `ScaffoldMessenger` pertenece al panel que
    // `pushAndRemoveUntil` va a desmontar, y limpiarlo después opera sobre un
    // estado ya liberado.
    avisos.clearSnackBars();
    nav.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (context) => const PantallaLoginPaisaje(),
      ),
      (route) => false,
    );
  }

  /// Abre el formulario de alta y, si se guardó, deja ese hijo seleccionado.
  Future<void> _agregarHijo() async {
    final String? id = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const ChildFormScreen(),
      ),
    );
    if (!mounted || id == null) return;
    setState(() {
      _hijoSeleccionadoId = id;
      _pestana = _kPestanaRuta;
    });
  }

  /// Abre la edición. El formulario devuelve el id guardado o `true` si el
  /// hijo se eliminó; en ese caso se suelta la selección.
  Future<void> _editarHijo(Hijo hijo) async {
    final Object? resultado = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => ChildFormScreen(hijo: hijo),
      ),
    );
    if (!mounted || resultado == null) return;

    if (resultado == true) {
      if (_hijoSeleccionadoId == hijo.id) {
        setState(() => _hijoSeleccionadoId = null);
      }
      return;
    }
    if (resultado is String) {
      setState(() => _hijoSeleccionadoId = resultado);
    }
  }

  /// Pestaña "Mi Perfil": la identidad del padre y la lista de opciones.
  ///
  /// Los datos y los hijos ya no se incrustan aquí: son entradas que abren sus
  /// propias pantallas. Así el perfil queda como un menú de cuenta y no como un
  /// muro de tarjetas que hay que recorrer para llegar a "Cerrar sesión".
  Widget _buildTarjetaPerfil(
    Map<String, dynamic> datos,
    List<Hijo> hijos,
  ) {
    final nombre = _texto(datos['fullName']) ?? 'Padre de familia';
    final email = _texto(datos['email']);

    final String detalleHijos;
    if (hijos.isEmpty) {
      detalleHijos = 'Sin hijos registrados';
    } else if (hijos.length == 1) {
      detalleHijos = '1 hijo registrado';
    } else {
      detalleHijos = '${hijos.length} hijos registrados';
    }

    return Column(
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
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textStrong,
                      ),
                    ),
                    if (email != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
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
              subtitle: 'Nombre, correo y teléfono',
              onTap: _abrirDatos,
            ),
            BusOpcion(
              icon: Icons.family_restroom_rounded,
              title: 'Mis hijos',
              subtitle: detalleHijos,
              onTap: () => _abrirHijos(datos, hijos),
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
              onTap: () => _cerrarSesion(context),
            ),
          ],
        ),
      ],
    );
  }

  /// Abre "Mis datos" (nombre, correo y teléfono de la cuenta).
  Future<void> _abrirDatos() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ParentDatosScreen(streams: _streams),
      ),
    );
  }

  /// Abre "Mis hijos". Si el padre toca uno, vuelve al panel con ese hijo
  /// seleccionado: lo que quiere ver a continuación es su ruta.
  Future<void> _abrirHijos(
    Map<String, dynamic> datos,
    List<Hijo> hijos,
  ) async {
    final String? id = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => ParentHijosScreen(
          streams: _streams,
          parentUid: FirebaseAuth.instance.currentUser?.uid ?? '',
          datosPerfil: datos,
          seleccionadoId: _hijoSeleccionado(hijos)?.id,
        ),
      ),
    );
    if (!mounted || id == null) return;
    setState(() {
      _hijoSeleccionadoId = id;
      _pestana = _kPestanaRuta;
    });
  }


  /// Normaliza un valor de Firestore a texto no vacío, o `null`.
  String? _texto(dynamic valor) {
    if (valor == null) return null;
    final s = valor.toString().trim();
    return s.isEmpty ? null : s;
  }
}

/// Mensaje centrado dentro del panel, para los casos sin datos.
class _Aviso extends StatelessWidget {
  final String texto;

  const _Aviso({required this.texto});

  @override
  Widget build(BuildContext context) {
    return BusEmptyState(
      text: texto,
      icon: Icons.info_outline_rounded,
    );
  }
}
