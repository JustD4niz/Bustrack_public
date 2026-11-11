import 'package:flutter/material.dart';

import '../main.dart';
import '../parent_register_screen.dart';
import '../widgets/bus_ui.dart';
import 'driver_register_screen.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            children: [
              BusHeader(
                title: '¿Cómo deseas registrarte?',
                subtitle: 'Elige tu perfil para configurar la experiencia '
                    'adecuada en BusTrack',
                titleSize: 24,
                leading: BusIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Volver',
                  // Esta pantalla siempre tiene al login debajo: o se llega con
                  // `push` desde `_enrutar` (login de una cuenta sin ficha), o el
                  // registro la reemplaza y el login ya estaba debajo. Por eso
                  // "atrás" sí funciona aquí.
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildRoleCard(
                            context,
                            icon: Icons.directions_car_filled_rounded,
                            titulo: 'Soy Conductor',
                            subtitulo: 'Registra tu vehículo y documentos '
                                'para ofrecer el servicio.',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const PantallaRegistroConductor(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildRoleCard(
                            context,
                            icon: Icons.family_restroom_rounded,
                            titulo: 'Soy Padre / Representante',
                            subtitulo: 'Realiza el seguimiento escolar y el '
                                'monitoreo del transporte.',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const ParentRegisterScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              'Podrás cambiar de perfil más adelante.',
                              style: busText(
                                size: 12,
                                color: AppColors.textMuted,
                              ),
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
      ),
    );
  }

  /// Tarjeta blanca con icono amarillo, título, subtítulo y flecha. Se usa
  /// `Row` + `Expanded` para que los textos largos envuelvan bien en pantallas
  /// angostas.
  Widget _buildRoleCard(
    BuildContext context, {
    required IconData icon,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
  }) {
    return BusCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
            child: Row(
              children: [
                BusIconBadge(icon: icon, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: busText(
                          size: 16,
                          weight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitulo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: busText(
                          size: 12.5,
                          color: AppColors.textMuted,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 22,
                  color: AppColors.ink,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
