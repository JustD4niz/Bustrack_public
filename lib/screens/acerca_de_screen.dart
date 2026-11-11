import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../admin_service.dart';
import '../main.dart' show AppColors;
import '../widgets/bus_ui.dart';

/// Versión visible en "Acerca de".
///
/// Se mantiene a mano junto a `version:` de `pubspec.yaml`. Se evita
/// `package_info_plus` a propósito: sería un paquete más (y otro canal nativo)
/// solo para leer un texto que cambia cuando se sube el APK.
const String kBusTrackVersion = '1.0.0';

/// Pantalla "Acerca de": qué es BusTrack, quién lo administra y qué servicios
/// usa. Es la misma para el padre y el conductor.
class AcercaDeScreen extends StatelessWidget {
  const AcercaDeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            BusHeader(
              title: 'Acerca de',
              subtitle: 'BusTrack · Versión $kBusTrackVersion',
              titleSize: 21,
              fullBleed: true,
              leading: BusIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Volver',
                onTap: () => Navigator.of(context).maybePop(),
              ),
              trailing: const BusIconBadge(
                icon: Icons.info_outline_rounded,
                size: 46,
                color: Colors.white,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        BusCard(
                          padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
                          child: Column(
                            children: [
                              const BusIconBadge(
                                icon: Icons.directions_bus_filled_rounded,
                                size: 86,
                                iconSize: 46,
                                radius: 26,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'BusTrack',
                                style: GoogleFonts.poppins(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textStrong,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Versión $kBusTrackVersion',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Seguimiento en tiempo real del bus escolar: '
                                'el conductor comparte su ruta y los padres ven '
                                'dónde va su hijo, qué paradas faltan y cuándo '
                                'llega al punto de recogida.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  fontSize: 13.5,
                                  height: 1.45,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        BusSeccion(
                          titulo: 'Administración',
                          subtitulo: 'Aprobación de conductores y soporte',
                          icon: Icons.support_agent_rounded,
                          children: [
                            BusOpcion(
                              icon: Icons.email_outlined,
                              title: 'Correo del administrador',
                              subtitle: AdminService.adminEmail,
                              onTap: () => _copiarCorreo(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        BusSeccion(
                          titulo: 'Servicios',
                          subtitulo: 'Con qué funciona la app',
                          icon: Icons.cloud_outlined,
                          children: const [
                            _FilaServicio(
                              icon: Icons.lock_outline_rounded,
                              title: 'Firebase',
                              subtitle:
                                  'Cuentas, base de datos y reglas de acceso',
                            ),
                            _FilaServicio(
                              icon: Icons.map_outlined,
                              title: 'Google Maps',
                              subtitle: 'Mapa del bus y de los puntos de recogida',
                            ),
                            _FilaServicio(
                              icon: Icons.alt_route_rounded,
                              title: 'OpenStreetMap (OSRM)',
                              subtitle: 'Trazado de la ruta por calles, gratis y sin clave',
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Hecho para colegios y transportadores escolares.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copiarCorreo(BuildContext context) async {
    final ScaffoldMessengerState avisos = ScaffoldMessenger.of(context);
    await Clipboard.setData(
      const ClipboardData(text: AdminService.adminEmail),
    );
    avisos.clearSnackBars();
    avisos.showSnackBar(
      const SnackBar(
        content: Text('Correo copiado'),
        backgroundColor: AppColors.ink,
      ),
    );
  }
}

/// Fila informativa de los servicios: mismo aspecto que [BusOpcion] pero sin
/// acción. Los servicios no se tocan, así que no deben responder con un ripple.
class _FilaServicio extends StatelessWidget {
  const _FilaServicio({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primaryPale,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textStrong, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textStrong,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
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
