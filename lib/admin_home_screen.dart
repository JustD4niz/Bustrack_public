import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'admin_service.dart'; // Importamos el archivo que acabamos de crear
import 'main.dart';
import 'models/hijo.dart';
import 'screens/login_screen.dart';
import 'services/document_stream.dart';
import 'services/google_auth.dart';
import 'services/session_prefs.dart';
import 'widgets/admin_drawer.dart';
import 'widgets/bus_ui.dart';

/// Panel de aprobación de conductores.
///
/// La maqueta lo pintaba con `Align` sobre un `Stack` de tamaño fijo
/// (412x856.8); aquí la banda superior, la cabecera de sección y la lista son
/// una `Column` normal, para que se ajusten a cualquier pantalla.
///
/// Es `StatefulWidget` porque el menú lateral cambia la sección visible
/// ([_seccion]) y esa elección tiene que sobrevivir a las reconstrucciones que
/// dispara el propio Firestore.
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  /// Los `snapshots()` se reutilizan entre reconstrucciones; ver
  /// `StreamsDeDocumento`. Como el `State` vive lo que la pantalla, un campo
  /// basta: no hace falta el `final` de archivo que usaba la versión
  /// `StatelessWidget`.
  final StreamsDeDocumento _streams = StreamsDeDocumento();

  /// Sección que muestra la lista. Arranca en la cola de aprobación, que es lo
  /// que hacía el panel antes de tener menú.
  SeccionAdmin _seccion = SeccionAdmin.pendientes;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        drawer: AdminDrawer(
          actual: _seccion,
          onSeleccionar: (SeccionAdmin seccion) {
            if (seccion != _seccion) setState(() => _seccion = seccion);
          },
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildBandaTitulo(context),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildEncabezadoSeccion(),
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildListaSeccion()),
            ],
          ),
        ),
      ),
    );
  }

  /// Encabezado amarillo a sangre con las tres líneas que abren el menú a la
  /// izquierda y el botón de salida a la derecha.
  Widget _buildBandaTitulo(BuildContext context) {
    return BusHeader(
      title: 'Panel de Administración',
      subtitle: 'Aprueba y revisa las cuentas de BusTrack',
      titleSize: 22,
      fullBleed: true,
      leading: Builder(
        builder: (BuildContext contextoDelScaffold) {
          // El `Builder` es necesario: el `context` del `build` está por
          // encima del `Scaffold` y `Scaffold.of` no lo encontraría. Además,
          // el panel llega desde el login con `pushReplacement`, así que no
          // hay a qué volver con "atrás": este botón cierra sesión.
          return BusIconButton(
            icon: Icons.menu_rounded,
            tooltip: 'Menú',
            onTap: () => Scaffold.of(contextoDelScaffold).openDrawer(),
          );
        },
      ),
      trailing: BusIconButton(
        icon: Icons.logout_rounded,
        tooltip: 'Cerrar sesión',
        onTap: () => _cerrarSesion(context),
      ),
    );
  }

  /// Cierra la sesión y vuelve al login.
  static Future<void> _cerrarSesion(BuildContext context) async {
    // Se resuelven antes del primer `await`: después, `context` ya está detrás
    // de un async gap.
    final NavigatorState nav = Navigator.of(context);
    final ScaffoldMessengerState avisos = ScaffoldMessenger.of(context);
    try {
      await GoogleAuth.cerrarSesion();
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      // Un fallo al limpiar la sesión no debe dejar al admin atrapado en el
      // panel sin poder salir.
    }
    // Cierre de sesión explícito: la próxima apertura debe mostrar la
    // bienvenida, no el aviso de "no pudimos restaurar tu sesión".
    await PreferenciasDeSesion.olvidarSesion();
    // Antes de navegar: este `ScaffoldMessenger` pertenece al panel que
    // `pushAndRemoveUntil` va a desmontar, y limpiarlo después opera sobre un
    // un estado ya liberado.
    avisos.clearSnackBars();
    nav.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (context) => const PantallaLoginPaisaje(),
      ),
      (route) => false,
    );
  }

  /// Cabecera de la sección activa: barra amarilla corta y el título.
  Widget _buildEncabezadoSeccion() {
    return Row(
      children: [
        Container(
          width: 6,
          height: 24,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _tituloSeccion,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textStrong,
            ),
          ),
        ),
      ],
    );
  }

  /// Título de la sección activa, el que pinta la cabecera.
  String get _tituloSeccion {
    switch (_seccion) {
      case SeccionAdmin.usuarios:
        return 'Usuarios totales';
      case SeccionAdmin.pendientes:
        return 'Conductores pendientes de Aprobación';
      case SeccionAdmin.aprobados:
        return 'Perfiles de Conductores Aprobados';
    }
  }

  /// Lista de la sección activa. Las tres secciones son la misma tarjeta verde
  /// con una consulta distinta sobre `usuarios`; lo único que cambia es el
  /// filtro y si la ficha ofrece aprobar/rechazar.
  Widget _buildListaSeccion() {
    switch (_seccion) {
      case SeccionAdmin.pendientes:
        return _buildLista(
          clave: 'cola_conductores_pendientes',
          consulta: () => FirebaseFirestore.instance
              .collection('usuarios')
              .where('role', isEqualTo: 'driver')
              .where('isApproved', isEqualTo: false)
              .snapshots(),
          vacio: 'No hay solicitudes pendientes de conductores.',
          permiteAprobar: true,
        );

      case SeccionAdmin.aprobados:
        return _buildLista(
          // El mismo índice compuesto (role + isApproved) sirve para
          // `isApproved == true`; no hace falta uno nuevo.
          clave: 'conductores_aprobados',
          consulta: () => FirebaseFirestore.instance
              .collection('usuarios')
              .where('role', isEqualTo: 'driver')
              .where('isApproved', isEqualTo: true)
              .snapshots(),
          vacio: 'Todavía no hay conductores aprobados.',
          permiteAprobar: false,
        );

      case SeccionAdmin.usuarios:
        return _buildLista(
          // Sin `where`: es toda la colección `usuarios`, así que no necesita
          // índice compuesto.
          clave: 'usuarios_todos',
          consulta: () =>
              FirebaseFirestore.instance.collection('usuarios').snapshots(),
          vacio: 'Todavía no hay usuarios registrados.',
          permiteAprobar: false,
          mostrarRol: true,
        );
    }
  }

  /// Tarjeta verde de la maqueta con la lista de la sección activa.
  ///
  /// [clave] memoiza el listener (ver `StreamsDeDocumento`), [consulta] lo crea
  /// una sola vez por sección, [vacio] es el mensaje sin resultados y
  /// [permiteAprobar] decide si "Ver" abre la hoja con aprobar/rechazar o solo
  /// de lectura. [mostrarRol] añade la etiqueta Padre/Conductor en la ficha,
  /// que hace falta cuando la lista mezcla los dos roles.
  Widget _buildLista({
    required String clave,
    required Stream<QuerySnapshot> Function() consulta,
    required String vacio,
    required bool permiteAprobar,
    bool mostrarRol = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: StreamBuilder<QuerySnapshot>(
        // El listener se reutiliza entre reconstrucciones; ver
        // `StreamsDeDocumento`.
        stream: _streams.deConsulta(clave, consulta),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.ink),
            );
          }

          if (snapshot.hasError) {
            return _buildAviso(
              'No se pudieron cargar los datos: ${snapshot.error}',
            );
          }

          final List<QueryDocumentSnapshot<Object?>> documentos =
              snapshot.data?.docs ?? const [];

          if (documentos.isEmpty) {
            return _buildAviso(vacio);
          }

          return Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(26),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 22,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(12),
            child: ListView.separated(
              itemCount: documentos.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final QueryDocumentSnapshot<Object?> doc = documentos[index];
                final Map<String, dynamic> data =
                    (doc.data() as Map?)?.cast<String, dynamic>() ?? const {};
                return _buildFichaConductor(
                  context,
                  nombre: data['fullName'] as String? ?? 'Sin nombre',
                  email: data['email'] as String? ?? 'Sin correo',
                  rol: mostrarRol ? data['role'] as String? : null,
                  onVer: () => _mostrarDetalle(
                    context,
                    doc,
                    data,
                    permiteAprobar: permiteAprobar,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// Fila de la lista: recuadro claro con el icono de persona, el nombre y el
  /// botón "Ver".
  ///
  /// [rol] solo llega en "Usuarios totales", donde la lista mezcla padres y
  /// conductores y sin la etiqueta no se distingue uno de otro.
  Widget _buildFichaConductor(
    BuildContext context, {
    required String nombre,
    required String email,
    required VoidCallback onVer,
    String? rol,
  }) {
    final String? etiquetaRol = switch (rol) {
      'driver' => 'Conductor',
      'parent' => 'Padre',
      _ => null,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.primaryPale,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const BusIconBadge(
            icon: Icons.person_rounded,
            size: 44,
            color: Colors.white,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textStrong,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                if (etiquetaRol != null) ...[
                  const SizedBox(height: 6),
                  BusStatusPill(label: etiquetaRol),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // "Ver" de la maqueta (10 px, 24 de alto) subido a 40 px para
          // cumplir el objetivo táctil.
          SizedBox(
            height: 40,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.ink,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onVer,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Ver',
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Hoja inferior con los datos de la ficha. El botón "Ver" de la maqueta no
  /// llegaba a la aprobación: la aprobación vive aquí, con los mismos métodos
  /// de [AdminService] que usaba la lista anterior.
  ///
  /// [permiteAprobar] en `false` deja la hoja en solo lectura: las secciones
  /// "Usuarios totales" y "Perfiles aprobados" no ofrecen aprobar ni rechazar.
  /// Aprobar lo ya aprobado no hace nada, y "Rechazar" **borra** el documento
  /// del usuario, así que no puede quedar al alcance de un toque desde una
  /// lista que mezcla padres y conductores.
  Future<void> _mostrarDetalle(
    BuildContext context,
    QueryDocumentSnapshot<Object?> doc,
    Map<String, dynamic> data, {
    required bool permiteAprobar,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      // Con cinco adjuntos la hoja pasa de la mitad de la pantalla: sin esto
      // el contenido se sale por abajo en phones bajos.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (BuildContext hoja) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const BusIconBadge(
                        icon: Icons.person_rounded,
                        size: 46,
                        color: AppColors.primaryPale,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['fullName'] as String? ?? 'Sin nombre',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textStrong,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${permiteAprobar ? 'Solicitud' : 'Usuario'} ${doc.id}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildDato('Correo', data['email'] as String?),
                  // Los campos del vehículo solo los llena el conductor: en la
                  // lista de usuarios aparecían como "—" en cada padre. Se
                  // omiten cuando están vacíos.
                  _buildDatoSiHay(
                    'Documento',
                    _unirTipoYNumero(
                      data['docType'] as String?,
                      data['docNumber'] as String?,
                    ),
                  ),
                  _buildDatoSiHay('Teléfono', data['phone'] as String?),
                  _buildDatoSiHay('Placa del bus', data['busPlate'] as String?),
                  _buildDatoSiHay(
                    'Vehículo',
                    _unirVehiculo(
                      data['busBrand'] as String?,
                      data['busModel'] as String?,
                      data['busYear'] as String?,
                    ),
                  ),
                  _buildAdjuntos(context, doc.id, data['documents']),
                  // Los hijos ya no viven en `usuarios`: el padre crea uno por
                  // documento en `estudiantes`. Sin esto, un padre registrado
                  // con el flujo nuevo se veía en la hoja sin ningún dato del
                  // estudiante.
                  if (_esPadre(data))
                    _HijosDelPadre(uid: doc.id, perfil: data),
                  if (_esConductor(data)) ...[
                    const SizedBox(height: 16),
                    _buildBotonEliminar(
                      etiqueta: 'Eliminar ruta del conductor',
                      onPressed: () => _confirmarYEliminar(
                        context,
                        titulo: 'Eliminar ruta',
                        mensaje: 'Se borrarán la ruta y su historial de este '
                            'conductor. Esta acción no se puede deshacer.',
                        accion: () => AdminService.eliminarRuta(doc.id),
                        exito: 'Ruta eliminada.',
                      ),
                    ),
                  ],
                  if (_esPadre(data)) ...[
                    const SizedBox(height: 16),
                    _buildBotonEliminar(
                      etiqueta: 'Eliminar punto de recogida',
                      onPressed: () => _confirmarYEliminar(
                        context,
                        titulo: 'Eliminar punto de recogida',
                        mensaje: 'Se borrará el punto que este padre marcó '
                            'para su hijo. Esta acción no se puede deshacer.',
                        accion: () =>
                            AdminService.eliminarPuntoRecogida(doc.id),
                        exito: 'Punto de recogida eliminado.',
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (!permiteAprobar)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textStrong,
                        side: const BorderSide(color: AppColors.border),
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () => Navigator.of(hoja).pop(),
                      child: const Text('Cerrar'),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.success,
                              side: const BorderSide(
                                color: AppColors.success,
                                width: 1.5,
                              ),
                              minimumSize: const Size(0, 48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () async {
                              final NavigatorState nav = Navigator.of(context);
                              try {
                                await AdminService.aprobarConductor(doc.id);
                                nav.pop();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        '¡Conductor aprobado con éxito!',
                                      ),
                                      backgroundColor: AppColors.success,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('$e'),
                                      backgroundColor: AppColors.danger,
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Aprobar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.danger,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              minimumSize: const Size(0, 48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () async {
                              final NavigatorState nav = Navigator.of(context);
                              final String? motivo =
                                  await _pedirMotivoRechazo(context);
                              if (motivo == null) return;
                              try {
                                await AdminService.rechazarConductor(
                                  doc.id,
                                  motivo: motivo,
                                );
                                nav.pop();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Solicitud rechazada. El conductor '
                                        'puede corregirla y reenviarla.',
                                      ),
                                      backgroundColor: AppColors.ink,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('$e'),
                                      backgroundColor: AppColors.danger,
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Rechazar'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// ¿La ficha es de un conductor? Decide si la hoja ofrece borrar su ruta.
  bool _esConductor(Map<String, dynamic> data) => data['role'] == 'driver';

  /// ¿La ficha es de un padre? Decide si la hoja ofrece borrar su punto de
  /// recogida.
  bool _esPadre(Map<String, dynamic> data) => data['role'] == 'parent';

  /// Botón destructivo del detalle (rojo, con borde) para las acciones que
  /// borran datos: la ruta de un conductor o el punto de recogida de un padre.
  Widget _buildBotonEliminar({
    required String etiqueta,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.danger,
        side: const BorderSide(color: AppColors.danger, width: 1.5),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      onPressed: onPressed,
      icon: const Icon(Icons.delete_outline, size: 18),
      label: Text(etiqueta),
    );
  }

  /// Pide confirmación antes de una acción destructiva, la ejecuta y cierra la
  /// hoja de detalle con un SnackBar.
  ///
  /// La confirmación importa: borrar la ruta o el punto de recogida de otro
  /// usuario no se puede deshacer desde la app.
  Future<void> _confirmarYEliminar(
    BuildContext context, {
    required String titulo,
    required String mensaje,
    required Future<void> Function() accion,
    required String exito,
  }) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogo) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
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
    if (confirmar != true || !context.mounted) return;

    // Se resuelven antes del primer `await`: después, `context` ya está detrás
    // de un async gap.
    final NavigatorState nav = Navigator.of(context);
    final ScaffoldMessengerState avisos = ScaffoldMessenger.of(context);
    try {
      await accion();
      nav.pop();
      avisos.clearSnackBars();
      avisos.showSnackBar(
        SnackBar(content: Text(exito), backgroundColor: AppColors.ink),
      );
    } catch (e) {
      avisos.clearSnackBars();
      avisos.showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
      );
    }
  }

  /// Pide al admin el motivo del rechazo.
  ///
  /// El motivo viaja a `usuarios/{uid}.motivoRechazo` y es lo que el conductor
  /// ve en `PantallaSolicitudRevision` para saber qué corregir. Devuelve `null`
  /// si el admin cancela; un texto vacío es válido y se traduce después en un
  /// mensaje genérico (`AdminService.rechazarConductor`).
  Future<String?> _pedirMotivoRechazo(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    final String? motivo = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogo) => AlertDialog(
        title: const Text('Rechazar solicitud'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'El conductor podrá corregir sus datos y reenviar la solicitud. '
              'Escribe qué debe corregir:',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Ej.: la licencia está vencida o no se lee.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogo).pop(controller.text),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    controller.dispose();
    return motivo;
  }

  /// "Cédula de Ciudadanía · 12345678": junta tipo y número en la misma línea.
  /// Si el documento aún no trae alguno de los dos, devuelve el que sí exista
  /// en lugar de un "—" intermedio.
  String? _unirTipoYNumero(String? tipo, String? numero) {
    final List<String> partes = <String>[
      if (tipo != null && tipo.isNotEmpty) tipo,
      if (numero != null && numero.isNotEmpty) numero,
    ];
    if (partes.isEmpty) return null;
    return partes.join(' · ');
  }

  /// "Toyota · Hilux · 2019" a partir de marca, modelo y año, omitiendo los que
  /// el conductor no llenó.
  String? _unirVehiculo(String? marca, String? modelo, String? anio) {
    final List<String> partes = <String>[
      if (marca != null && marca.isNotEmpty) marca,
      if (modelo != null && modelo.isNotEmpty) modelo,
      if (anio != null && anio.isNotEmpty) anio,
    ];
    if (partes.isEmpty) return null;
    return partes.join(' · ');
  }

  /// Los adjuntos del registro del conductor se guardan en la ficha como
  /// `{título del tile: {name, slug, isPdf}}`, y los bytes viven en documentos
  /// aparte: `solicitudes/{uid}/adjuntos/{slug}`. Cada tile trae su miniatura y
  /// se abre a pantalla completa al tocarlo.
  ///
  /// Los documentos pueden ser PDF (la licencia, por ejemplo): esos no se
  /// previsualizan porque Flutter no pinta PDF, así que el tile los señala como
  /// tales. Y las solicitudes anteriores a esta versión tienen solo el nombre en
  /// texto plano: se listan igual, sin miniatura.
  Widget _buildAdjuntos(BuildContext context, String uid, Object? documentos) {
    if (documentos is! Map || documentos.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<Widget> tiles = <Widget>[];
    documentos.forEach((Object? clave, Object? valor) {
      final String titulo = clave.toString();
      // Solicitud antigua: el valor es el nombre en texto plano.
      if (valor is! Map) {
        tiles.add(
          _buildTileAdjunto(
            uid: uid,
            titulo: titulo,
            nombre: valor.toString(),
            slug: null,
            esPdf: false,
          ),
        );
        return;
      }

      tiles.add(
        _buildTileAdjunto(
          uid: uid,
          titulo: titulo,
          nombre: valor['name'] as String? ?? '',
          slug: valor['slug'] as String?,
          esPdf: valor['isPdf'] as bool? ?? false,
        ),
      );
    });

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Adjuntos',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 10, runSpacing: 10, children: tiles),
        ],
      ),
    );
  }

  Widget _buildTileAdjunto({
    required String uid,
    required String titulo,
    required String nombre,
    required String? slug,
    required bool esPdf,
  }) {
    return SizedBox(
      width: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 104,
              height: 78,
              child: esPdf
                  ? _buildAvisoArchivo(
                      Icons.picture_as_pdf_outlined,
                      'PDF\nno se previsualiza',
                    )
                  : (slug == null
                        ? _buildAvisoArchivo(
                            Icons.insert_drive_file_outlined,
                            'Solo nombre',
                          )
                        : _buildMiniatura(uid, slug, titulo)),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            titulo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textStrong,
              height: 1.2,
            ),
          ),
          if (nombre.isNotEmpty)
            Text(
              nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9,
                color: AppColors.textMuted,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAvisoArchivo(IconData icono, String texto) {
    return Container(
      color: AppColors.primaryPale,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icono, size: 22, color: AppColors.textMuted),
          const SizedBox(height: 2),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  /// Un campo `bytes` de Firestore no llega igual en todas las plataformas, y
  /// hacer `as Uint8List` revienta en una de ellas:
  ///
  /// - En Android e iOS llega como `Uint8List` (el canal de método lo
  ///   deserializa así).
  /// - En web, `cloud_firestore_web` lo devuelve envuelto en un [Blob], que es
  ///   una clase aparte con el `Uint8List` dentro de `.bytes`; por eso un
  ///   `TypeError` de cast es el síntoma típico de leer una foto en el navegador.
  Uint8List? _bytesDe(Object? valor) {
    if (valor is Uint8List) return valor;
    if (valor is Blob) return valor.bytes;
    if (valor is List<int>) return Uint8List.fromList(valor);
    return null;
  }

  /// Miniatura de un adjunto. Los bytes viven en
  /// `solicitudes/{uid}/adjuntos/{slug}`, así que hace falta una lectura por
  /// imagen; el `FutureBuilder` las pide solo cuando se abre la hoja.
  Widget _buildMiniatura(String uid, String slug, String titulo) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(uid)
          .collection('adjuntos')
          .doc(slug)
          .get(),
      builder:
          (
            BuildContext contexto,
            AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snap,
          ) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            if (snap.hasError) {
              return _buildAvisoArchivo(Icons.lock_outline, 'Sin permiso');
            }

            final Uint8List? bytes = _bytesDe(snap.data?.data()?['data']);
            if (bytes == null) {
              return _buildAvisoArchivo(Icons.broken_image_outlined, 'No está');
            }

            return InkWell(
              onTap: () => _abrirAdjunto(contexto, titulo, bytes),
              child: Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            );
          },
    );
  }

  /// Vista ampliada del documento, con zoom. Los bytes ya están en memoria (los
  /// trajo la miniatura), así que no vuelve a leer de Firestore.
  void _abrirAdjunto(BuildContext context, String titulo, Uint8List bytes) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (BuildContext dialogo) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white24,
                ),
                onPressed: () => Navigator.of(dialogo).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDato(String etiqueta, String? valor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.primaryPale,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              etiqueta,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              (valor == null || valor.isEmpty) ? '—' : valor,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Igual que [_buildDato], pero desaparece cuando no hay valor. Se usa en
  /// los campos que solo aplican a un rol: en la lista de usuarios, un padre
  /// no tiene placa ni vehículo y no tiene sentido pintarle un "—".
  Widget _buildDatoSiHay(String etiqueta, String? valor) {
    if (valor == null || valor.isEmpty) return const SizedBox.shrink();
    return _buildDato(etiqueta, valor);
  }

  /// Estado vacío o de error, dentro de la misma tarjeta.
  Widget _buildAviso(String mensaje) {
    return BusEmptyState(
      text: mensaje,
      icon: Icons.folder_open_rounded,
      margin: EdgeInsets.zero,
    );
  }
}

/// Hijos de un padre, dentro de la hoja de detalle del admin.
///
/// Se cargan bajo demanda (no están en el documento `usuarios`) y se pinta
/// también el hijo **legado**, el que las cuentas viejas todavía guardan dentro
/// de `usuarios/{uid}`. Es la misma composición que hace el panel del padre,
/// para que el admin y el padre no vean cosas distintas.
class _HijosDelPadre extends StatefulWidget {
  const _HijosDelPadre({required this.uid, required this.perfil});

  final String uid;
  final Map<String, dynamic> perfil;

  @override
  State<_HijosDelPadre> createState() => _HijosDelPadreState();
}

class _HijosDelPadreState extends State<_HijosDelPadre> {
  /// Una sola consulta por apertura de la hoja. `FutureBuilder` la reutiliza en
  /// cada reconstrucción; no se vuelve a pedir a Firestore.
  late final Future<List<Hijo>> _carga = _cargar();

  Future<List<Hijo>> _cargar() async {
    final List<Hijo> hijos = <Hijo>[];
    final Hijo? legado = Hijo.legado(widget.uid, widget.perfil);
    if (legado != null) hijos.add(legado);

    final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
        .instance
        .collection('estudiantes')
        .where('parentUid', isEqualTo: widget.uid)
        .get();
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snap.docs) {
      final Hijo? hijo = Hijo.desdeMapa(doc.id, doc.data());
      if (hijo != null) hijos.add(hijo);
    }
    return hijos;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Hijo>>(
      future: _carga,
      builder: (BuildContext context, AsyncSnapshot<List<Hijo>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          );
        }

        if (snap.hasError) {
          return _aviso('No se pudieron cargar los hijos de este padre.');
        }

        final List<Hijo> hijos = snap.data ?? const <Hijo>[];
        if (hijos.isEmpty) {
          return _aviso('Este padre todavía no registró hijos.');
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Text(
              hijos.length == 1 ? 'Hijo' : 'Hijos (${hijos.length})',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textStrong,
              ),
            ),
            const SizedBox(height: 8),
            for (final Hijo hijo in hijos) _buildHijo(hijo),
          ],
        );
      },
    );
  }

  Widget _aviso(String texto) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        texto,
        style: GoogleFonts.poppins(
          fontSize: 12.5,
          color: AppColors.textMuted,
        ),
      ),
    );
  }

  Widget _buildHijo(Hijo hijo) {
    final List<String> detalles = <String>[
      if (hijo.edad != null && hijo.edad! > 0) '${hijo.edad} años',
      if ((hijo.colegio ?? '').trim().isNotEmpty) hijo.colegio!,
    ];

    final String bus = hijo.tieneBus
        ? 'Bus ${hijo.busPlate}'
            '${(hijo.driverName ?? '').trim().isEmpty ? '' : ' · ${hijo.driverName}'}'
        : 'Sin bus vinculado';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.primaryPale,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.child_care_rounded, size: 18, color: AppColors.ink),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hijo.nombre,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textStrong,
                  ),
                ),
                if (detalles.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    detalles.join(' · '),
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  bus,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: hijo.tieneBus
                        ? AppColors.textStrong
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
