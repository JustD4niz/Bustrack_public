import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../main.dart' show AppColors;
import '../models/hijo.dart';
import '../services/document_stream.dart';
import '../services/hijos_service.dart';
import '../widgets/bus_ui.dart';
import 'child_form_screen.dart';

/// Pantalla "Mis hijos" del padre.
///
/// Antes la lista vivía incrustada en la pestaña "Mi Perfil". Ahora el perfil
/// quedó solo con opciones y los hijos se administran aquí: tocar un hijo vuelve
/// al panel con ese hijo seleccionado, y el lápiz abre el formulario para
/// editarlo, vincularlo a un bus o eliminarlo.
///
/// Escucha `estudiantes` en vivo con el mismo caché de streams que el panel, así
/// que editar un hijo aquí no obliga a recargar nada al volver.
class ParentHijosScreen extends StatefulWidget {
  const ParentHijosScreen({
    super.key,
    required this.streams,
    required this.parentUid,
    required this.datosPerfil,
    this.seleccionadoId,
  });

  final StreamsDeDocumento streams;
  final String parentUid;

  /// Documento `usuarios/{uid}` ya leído, para sintetizar el hijo legado.
  final Map<String, dynamic> datosPerfil;

  final String? seleccionadoId;

  @override
  State<ParentHijosScreen> createState() => _ParentHijosScreenState();
}

class _ParentHijosScreenState extends State<ParentHijosScreen> {
  String? _seleccionadoId;

  @override
  void initState() {
    super.initState();
    _seleccionadoId = widget.seleccionadoId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            BusHeader(
              title: 'Mis hijos',
              subtitle: 'Los estudiantes que sigues desde tu cuenta',
              titleSize: 21,
              fullBleed: true,
              leading: BusIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Volver',
                onTap: () => Navigator.of(context).maybePop(),
              ),
              trailing: const BusIconBadge(
                icon: Icons.family_restroom_rounded,
                size: 46,
                color: Colors.white,
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: widget.streams.deConsulta(
                  'estudiantes/${widget.parentUid}',
                  () => HijosService.consultaHijos(widget.parentUid),
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final List<Hijo> hijos = HijosService.listaCompleta(
                    parentUid: widget.parentUid,
                    perfil: widget.datosPerfil,
                    snap: snapshot.data,
                  );
                  return _buildContenido(hijos);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContenido(List<Hijo> hijos) {
    final String subtitulo;
    if (hijos.isEmpty) {
      subtitulo = 'Sin hijos registrados';
    } else if (hijos.length == 1) {
      subtitulo = '1 hijo registrado';
    } else {
      subtitulo = '${hijos.length} hijos registrados';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BusSeccion(
                titulo: 'Mis hijos',
                subtitulo: subtitulo,
                icon: Icons.family_restroom_rounded,
                children: [
                  if (hijos.isEmpty)
                    BusInfoBox(
                      icon: Icons.person_add_alt_1_rounded,
                      iconColor: AppColors.textMuted,
                      child: Text(
                        'Agrega a tu hijo para seguir la ruta del bus y marcar '
                        'su punto de recogida.',
                        style: busText(
                          size: 12.5,
                          color: AppColors.textMuted,
                          height: 1.35,
                        ),
                      ),
                    ),
                  for (final Hijo hijo in hijos)
                    _buildFilaHijo(hijo),
                ],
              ),
              const SizedBox(height: 12),
              if (hijos.isNotEmpty)
                Text(
                  'Toca un hijo para ver su ruta en el panel.',
                  textAlign: TextAlign.center,
                  style: busText(
                    size: 12,
                    color: AppColors.textMuted,
                    height: 1.3,
                  ),
                ),
              const SizedBox(height: 16),
              BusPrimaryButton(
                label: 'Agregar hijo',
                icon: Icons.person_add_alt_1_rounded,
                onPressed: _agregarHijo,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Renglón de un hijo. Tocarlo vuelve al panel con ese hijo seleccionado; el
  /// lápiz abre la edición sin salir de esta pantalla.
  Widget _buildFilaHijo(Hijo hijo) {
    final bool activo = hijo.id == _seleccionadoId;

    final String detalle;
    if (hijo.tieneBus) {
      detalle = 'Bus ${hijo.busPlate}'
          '${hijo.colegio == null ? '' : ' · ${hijo.colegio}'}';
    } else {
      detalle = 'Sin bus vinculado';
    }

    return Material(
      color: activo ? AppColors.primaryPale : AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(hijo.id),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(
            children: [
              Icon(
                activo
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: activo ? AppColors.primaryDeep : AppColors.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hijo.nombre,
                      style: busText(size: 14, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detalle,
                      style: busText(
                        size: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Editar a ${hijo.nombre}',
                icon: const Icon(Icons.edit_outlined, size: 20),
                color: AppColors.textMuted,
                onPressed: () => _editarHijo(hijo),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Alta de un hijo. Si se guardó, vuelve al panel con él seleccionado, que es
  /// lo que el padre quiere ver después de agregarlo.
  Future<void> _agregarHijo() async {
    final String? id = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const ChildFormScreen(),
      ),
    );
    if (!mounted || id == null) return;
    Navigator.of(context).pop(id);
  }

  /// Edición. El formulario devuelve el id guardado o `true` si se eliminó.
  Future<void> _editarHijo(Hijo hijo) async {
    final Object? resultado = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => ChildFormScreen(hijo: hijo),
      ),
    );
    if (!mounted || resultado == null) return;

    if (resultado == true) {
      if (_seleccionadoId == hijo.id) {
        setState(() => _seleccionadoId = null);
      }
      return;
    }
    if (resultado is String) {
      setState(() => _seleccionadoId = resultado);
    }
  }
}
