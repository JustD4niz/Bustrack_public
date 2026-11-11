import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart' show AppColors;
import '../services/document_stream.dart';
import '../services/phone_launcher.dart';
import 'bus_ui.dart';

/// Pestaña "Conductor" del panel del padre: quién lleva el bus y en qué estado.
///
/// Es lo que antes estaba en "Detalles del Vehículo", **sin el mapa** (el mapa
/// en vivo vive en la pestaña "Ruta"): la tarjeta del vehículo con el icono del
/// bus, la placa y el estado de la ruta en un chip amarillo, el nombre del
/// conductor y el botón para contactarlo.
///
/// Lee `buses/{placa}` en vivo. Si el documento todavía no trae datos, cae de
/// vuelta en lo que el padre anotó al registrarse para no mostrar un hueco.
class ParentVehiculoView extends StatelessWidget {
  const ParentVehiculoView({
    super.key,
    required this.streams,
    required this.placa,
    this.driverNameRegistrado,
  });

  final StreamsDeDocumento streams;

  /// Placa del bus del padre, o `null` si todavía no tiene una asignada.
  final String? placa;

  /// Conductor que el padre escribió en su registro. Se usa como respaldo
  /// mientras el bus no reporte uno propio.
  final String? driverNameRegistrado;

  @override
  Widget build(BuildContext context) {
    final placa = this.placa;
    if (placa == null || placa.isEmpty) {
      return const _Aviso(
        texto: 'No tienes ninguna placa de bus asociada a tu cuenta.',
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: streams.de('buses/$placa'),
      builder: (context, snapshot) {
        final datos = (snapshot.hasData && snapshot.data!.exists)
            ? (snapshot.data!.data() as Map<String, dynamic>)
            : <String, dynamic>{};

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTarjetaVehiculo(placa, datos),
                  const SizedBox(height: 16),
                  _buildTarjetaConductor(datos),
                  const SizedBox(height: 16),
                  _buildBotonContactar(context, datos),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Tarjeta principal: icono del bus, placa y estado de la ruta en una
  /// píldora negra con punto amarillo.
  Widget _buildTarjetaVehiculo(String placa, Map<String, dynamic> datos) {
    final nombre = _texto(datos['nombre']) ?? 'Bus Escolar';
    final String estado = _texto(datos['estadoRuta']) ?? 'Sin estado';
    final bool enRuta = estado.toLowerCase() == 'en ruta';

    return BusCard(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BusIconBadge(
                icon: Icons.directions_bus_filled_rounded,
                size: 72,
                iconSize: 42,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: GoogleFonts.poppins(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textStrong,
                      ),
                    ),
                    const SizedBox(height: 6),
                    BusInfoBox(
                      icon: Icons.badge_outlined,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        'Placa: $placa',
                        style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textStrong,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: BusStatusPill(
              label: estado,
              dotColor: enRuta ? AppColors.primary : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  /// Datos del conductor y, si el bus los reporta, telemetría de la ruta.
  Widget _buildTarjetaConductor(Map<String, dynamic> datos) {
    final conductor = _conductorVisible(datos);
    final ultima = _leerActualizacion(datos);
    final velocidad = _leerVelocidad(datos);

    return BusCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const BusIconBadge(
                icon: Icons.person_rounded,
                size: 42,
                color: AppColors.primaryPale,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Conductor',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textStrong,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Quién lleva el bus asignado a tu cuenta',
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
          const SizedBox(height: 14),
          _buildFila('Nombre Completo', conductor ?? 'Sin registrar'),
          if (ultima != null) _buildFila('Última Actualización', ultima),
          if (velocidad != null) _buildFila('Velocidad', '${velocidad.round()} km/h'),
        ],
      ),
    );
  }

  /// Abre el marcador con el número que el conductor publicó en `buses/{placa}`.
  /// Si todavía no lo ha publicado, el botón queda deshabilitado en vez de
  /// simular una llamada.
  Widget _buildBotonContactar(
    BuildContext context,
    Map<String, dynamic> datos,
  ) {
    final telefono = _texto(datos['conductorPhone']);
    final habilitado = telefono != null;
    return BusPrimaryButton(
      label: habilitado ? 'Contactar Conductor' : 'Conductor sin teléfono',
      icon: Icons.call_rounded,
      onPressed: habilitado ? () => _contactar(context, telefono) : null,
    );
  }

  Future<void> _contactar(BuildContext context, String telefono) async {
    final bool abierto = await PhoneLauncher.llamar(telefono);
    if (abierto || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo abrir el marcador.')),
    );
  }

  /// Conductor visible: el que reporta el bus (telemetría real) o, si no hay,
  /// el que el padre anotó al registrarse.
  String? _conductorVisible(Map<String, dynamic> datos) {
    final enVivo = _texto(datos['conductor']);
    if (enVivo != null) return enVivo;
    return _texto(driverNameRegistrado);
  }

  double? _leerVelocidad(Map<String, dynamic> datos) {
    final valor = datos['velocidad'];
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().trim() ?? '');
  }

  /// Acepta un `Timestamp` del servidor o un texto ya formateado. Devuelve
  /// `null` si el bus nunca ha reportado su posición.
  String? _leerActualizacion(Map<String, dynamic> datos) {
    final valor = datos['ultimaActualizacion'];
    if (valor == null) return null;
    if (valor is Timestamp) {
      final hora = valor.toDate().toLocal();
      final h = hora.hour.toString().padLeft(2, '0');
      final m = hora.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return _texto(valor);
  }

  /// Fila etiqueta / valor sobre una caja de datos amarillo pálido.
  Widget _buildFila(String etiqueta, String valor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.primaryPale,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              etiqueta,
              style: GoogleFonts.poppins(
                fontSize: 13.5,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: GoogleFonts.poppins(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _texto(dynamic valor) {
    if (valor == null) return null;
    final s = valor.toString().trim();
    return s.isEmpty ? null : s;
  }
}

/// Mensaje centrado, para cuando no hay placa asignada.
class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return BusEmptyState(
      text: texto,
      icon: Icons.directions_bus_filled_rounded,
    );
  }
}
