import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../main.dart' show AppColors;
import '../services/document_stream.dart';
import '../widgets/bus_ui.dart';

/// Pantalla "Mis datos" del conductor.
///
/// El perfil del conductor quedó solo con opciones (mis datos, código del bus,
/// cambiar contraseña y cerrar sesión); los datos de la cuenta y del vehículo se
/// leen aquí, en vivo desde `usuarios/{uid}`.
///
/// Es de solo lectura: los datos se cargan en el registro y el conductor no los
/// edita desde la app. El teléfono, en cambio, sí se publica en `buses/{placa}`
/// al iniciar la ruta para que el padre pueda llamarlo.
class DriverDatosScreen extends StatelessWidget {
  const DriverDatosScreen({super.key, required this.streams, required this.uid});

  final StreamsDeDocumento streams;
  final String uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            BusHeader(
              title: 'Mis datos',
              subtitle: 'Tu cuenta y tu bus',
              titleSize: 21,
              fullBleed: true,
              leading: BusIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Volver',
                onTap: () => Navigator.of(context).maybePop(),
              ),
              trailing: const BusIconBadge(
                icon: Icons.badge_rounded,
                size: 46,
                color: Colors.white,
              ),
            ),
            Expanded(
              child: StreamBuilder<DocumentSnapshot>(
                stream: streams.de('usuarios/$uid'),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError ||
                      !snapshot.hasData ||
                      !snapshot.data!.exists) {
                    return const BusEmptyState(
                      text: 'No se pudieron cargar tus datos.',
                      icon: Icons.person_off_rounded,
                    );
                  }

                  final datos =
                      snapshot.data!.data() as Map<String, dynamic>;
                  return _buildContenido(datos);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContenido(Map<String, dynamic> datos) {
    final String nombre = _texto(datos['fullName']) ?? 'Conductor';
    final String? email = _texto(datos['email']);
    final String? telefono = _texto(datos['phone']);
    final String? documento = _textoDocumento(datos);
    final String? placa = _texto(datos['busPlate'])?.toUpperCase();
    final String? marca = _texto(datos['busBrand']);
    final String? modelo = _texto(datos['busModel']);
    final String? anio = _texto(datos['busYear']);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BusSeccion(
                titulo: 'Cuenta',
                subtitulo: 'Identidad con la que ingresas',
                icon: Icons.person_rounded,
                children: [
                  BusDato(etiqueta: 'Nombre', valor: nombre),
                  BusDato(
                    etiqueta: 'Correo',
                    valor: email ?? 'Sin correo registrado',
                  ),
                  if (documento != null)
                    BusDato(etiqueta: 'Documento', valor: documento),
                  BusDato(
                    etiqueta: 'Teléfono',
                    valor: telefono ?? 'Sin teléfono registrado',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              BusSeccion(
                titulo: 'Mi bus',
                subtitulo: 'Datos que ven los padres',
                icon: Icons.directions_bus_filled_rounded,
                children: [
                  BusDato(
                    etiqueta: 'Placa',
                    valor: placa ?? 'Sin placa asignada',
                  ),
                  if (marca != null) BusDato(etiqueta: 'Marca', valor: marca),
                  if (modelo != null) BusDato(etiqueta: 'Modelo', valor: modelo),
                  if (anio != null) BusDato(etiqueta: 'Año', valor: anio),
                ],
              ),
              const SizedBox(height: 16),
              BusInfoBox(
                icon: Icons.lock_outline_rounded,
                iconColor: AppColors.textMuted,
                child: Text(
                  'Si algún dato está mal, contacta al administrador: el '
                  'registro del conductor se corrige desde el panel de admin.',
                  style: busText(
                    size: 12,
                    color: AppColors.textMuted,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Documento de identidad: tipo y número, si el conductor los registró.
  String? _textoDocumento(Map<String, dynamic> datos) {
    final String? tipo = _texto(datos['docType']);
    final String? numero = _texto(datos['docNumber']);
    if (tipo == null && numero == null) return null;
    if (tipo == null) return numero;
    if (numero == null) return tipo;
    return '$tipo · $numero';
  }

  String? _texto(dynamic valor) {
    if (valor == null) return null;
    final String s = valor.toString().trim();
    return s.isEmpty ? null : s;
  }
}
