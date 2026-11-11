import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart' show AppColors;
import 'bus_ui.dart';

/// Secciones del panel de administración. El orden es el que muestra el menú.
enum SeccionAdmin {
  /// Todos los usuarios, padres y conductores.
  usuarios,

  /// Conductores con `isApproved == false`: la cola de aprobación.
  pendientes,

  /// Conductores ya aprobados.
  aprobados,
}

/// Menú lateral del panel de administración, el que se abre con las tres
/// líneas de la banda superior.
///
/// Es una navegación de secciones, no de pantallas: las tres entradas
/// cambian la lista que muestra el mismo panel, porque "Usuarios totales",
/// "Solicitudes pendientes" y "Perfiles aprobados" son tres consultas sobre
/// `usuarios` y no tres pantallas distintas.
///
/// No usa el `NavbarWidget`/`NavbarModel` del export de FlutterFlow: este
/// proyecto no tiene `provider` ni `go_router`, y el menú se resuelve con un
/// `ValueChanged<SeccionAdmin>`, igual que la barra del panel de padres.
class AdminDrawer extends StatelessWidget {
  final SeccionAdmin actual;
  final ValueChanged<SeccionAdmin> onSeleccionar;

  const AdminDrawer({
    super.key,
    required this.actual,
    required this.onSeleccionar,
  });

  /// Etiqueta de cada entrada, en el orden del mockup.
  static const Map<SeccionAdmin, String> _etiquetas = {
    SeccionAdmin.usuarios: 'Usuarios totales',
    SeccionAdmin.pendientes: 'Solicitudes de Conductores pendientes',
    SeccionAdmin.aprobados: 'Perfiles de Conductores Aprobados',
  };

  @override
  Widget build(BuildContext context) {
    return Drawer(
      // El mismo fondo crema que el resto de la app, así que el menú se lee
      // como parte de la misma pantalla.
      backgroundColor: AppColors.background,
      width: 286,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildEncabezado(),
            const SizedBox(height: 10),
            for (final seccion in SeccionAdmin.values)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _buildEntrada(context, seccion),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              child: Text(
                'BusTrack · Administración',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Encabezado amarillo del menú con el icono del bus y el nombre de la app.
  Widget _buildEncabezado() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 22),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Row(
        children: [
          const BusIconBadge(
            icon: Icons.directions_bus_filled_rounded,
            size: 46,
            color: Colors.white,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'BusTrack',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Una entrada del menú: tarjeta blanca con icono. La sección activa va
  /// pintada en negro con el icono amarillo, para que se vea dónde está uno.
  Widget _buildEntrada(BuildContext context, SeccionAdmin seccion) {
    final bool activa = seccion == actual;
    final IconData icono = switch (seccion) {
      SeccionAdmin.usuarios => Icons.groups_rounded,
      SeccionAdmin.pendientes => Icons.pending_actions_rounded,
      SeccionAdmin.aprobados => Icons.verified_user_rounded,
    };

    return Material(
      color: activa ? AppColors.ink : AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // Cerrar y avisar en el mismo toque: el panel decide qué lista
          // mostrar y el `Navigator` cierra el cajón.
          Navigator.of(context).pop();
          onSeleccionar(seccion);
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                icono,
                size: 20,
                color: activa ? AppColors.primary : AppColors.ink,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _etiquetas[seccion]!,
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: activa ? FontWeight.w700 : FontWeight.w500,
                    color: activa ? Colors.white : AppColors.textStrong,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: activa
                    ? Colors.white.withValues(alpha: 0.7)
                    : AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
