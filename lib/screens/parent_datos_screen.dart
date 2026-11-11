import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../main.dart' show AppColors;
import '../services/document_stream.dart';
import '../widgets/bus_ui.dart';
import 'parent_edit_screen.dart';

/// Pantalla "Mis datos" del padre: nombre, correo y teléfono de la cuenta.
///
/// Antes esta información vivía incrustada en la pestaña "Mi Perfil", junto a
/// los hijos y las opciones. Ahora el perfil quedó solo con opciones y los datos
/// se abren desde ahí.
///
/// Escucha `usuarios/{uid}` en vivo: al volver de [ParentEditScreen] los campos
/// ya llegan actualizados sin recargar nada a mano.
class ParentDatosScreen extends StatelessWidget {
  const ParentDatosScreen({super.key, required this.streams});

  /// Caché de `snapshots()` compartido con el panel para no abrir un listener
  /// duplicado del mismo documento.
  final StreamsDeDocumento streams;

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            BusHeader(
              title: 'Mis datos',
              subtitle: 'Información de tu cuenta',
              titleSize: 21,
              fullBleed: true,
              leading: BusIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Volver',
                onTap: () => Navigator.of(context).maybePop(),
              ),
              trailing: const BusIconBadge(
                icon: Icons.person_rounded,
                size: 46,
                color: Colors.white,
              ),
            ),
            Expanded(
              child: user == null
                  ? const BusEmptyState(
                      text: 'Tu sesión venció. Vuelve a iniciar sesión.',
                      icon: Icons.person_off_rounded,
                    )
                  : StreamBuilder<DocumentSnapshot>(
                      stream: streams.de('usuarios/${user.uid}'),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            !snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
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
                        return _buildContenido(context, datos);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContenido(
    BuildContext context,
    Map<String, dynamic> datos,
  ) {
    final String nombre = _texto(datos['fullName']) ?? 'Padre de familia';
    final String? email = _texto(datos['email']);
    final String? telefono = _texto(datos['phone']);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BusSeccion(
                titulo: 'Datos de contacto',
                subtitulo: 'Así te ve el conductor de tu bus',
                icon: Icons.contact_page_rounded,
                children: [
                  BusDato(etiqueta: 'Nombre', valor: nombre),
                  BusDato(
                    etiqueta: 'Correo',
                    valor: email ?? 'Sin correo registrado',
                  ),
                  BusDato(
                    etiqueta: 'Teléfono',
                    valor: telefono ?? 'Sin teléfono registrado',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              BusPrimaryButton(
                label: 'Editar mis datos',
                icon: Icons.edit_outlined,
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => ParentEditScreen(datos: datos),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _texto(dynamic valor) {
    if (valor == null) return null;
    final String s = valor.toString().trim();
    return s.isEmpty ? null : s;
  }
}
