import 'package:flutter/material.dart';

import '../main.dart' show AppColors;
import 'bus_ui.dart';

/// Un destino de [BusNavBar]: icono y etiqueta.
class BusNavDestino {
  const BusNavDestino({required this.icono, required this.etiqueta});

  final IconData icono;
  final String etiqueta;
}

/// Barra de navegación inferior flotante, compartida por el panel del padre y
/// el del conductor.
///
/// Es puramente visual: no conoce los datos ni los listeners, solo publica el
/// índice elegido a través de [onChanged]. Los destinos llegan como parámetro
/// para que cada panel tenga los suyos sin duplicar la barra.
///
/// No usa `font_awesome_flutter` (que sí traía el export de FlutterFlow): el
/// único icono de esa librería era `locationArrow`, y `Icons.navigation` es el
/// equivalente de Material más cercano. Agregar una dependencia de fuente
/// entera por un glifo no compensa.
class BusNavBar extends StatelessWidget {
  const BusNavBar({
    super.key,
    required this.destinos,
    required this.currentIndex,
    required this.onChanged,
  });

  /// Icono y etiqueta de cada destino, en orden. El primero es el que abre por
  /// defecto en los dos paneles.
  final List<BusNavDestino> destinos;

  /// Índice de la pestaña activa.
  final int currentIndex;

  /// Se dispara con el índice de la pestaña que el usuario acaba de tocar.
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    // El `SafeArea` va aquí y no en el `Scaffold` porque este widget también
    // se usa fuera de él.
    return SafeArea(
      top: false,
      child: Container(
        height: 70,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(26),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            for (var i = 0; i < destinos.length; i++)
              Expanded(
                child: _Pestana(
                  icono: destinos[i].icono,
                  etiqueta: destinos[i].etiqueta,
                  activa: i == currentIndex,
                  onTap: () => onChanged(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Un destino de la barra: icono encima, etiqueta debajo.
///
/// La pestaña activa se pinta como una píldora amarilla sólida. Sin esto la
/// barra no dice dónde estás.
class _Pestana extends StatelessWidget {
  final IconData icono;
  final String etiqueta;
  final bool activa;
  final VoidCallback onTap;

  const _Pestana({
    required this.icono,
    required this.etiqueta,
    required this.activa,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            // Todas las píldoras miden lo mismo: el ancho lo da la celda, no el
            // texto. Con ancho intrínseco "Recorrido" salía más ancha que
            // "Ruta" y el resaltado saltaba de tamaño al cambiar de pestaña.
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
            decoration: BoxDecoration(
              color: activa ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icono,
                  size: 22,
                  color: activa ? AppColors.ink : AppColors.textMuted,
                ),
                const SizedBox(height: 2),
                // En 360 dp cada destino mide ~72 dp: "Estudiantes" y "Mi
                // Perfil" no entran a tamaño fijo, así que se encogen en vez
                // de desbordar.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    etiqueta,
                    maxLines: 1,
                    style: busText(
                      size: 10.5,
                      weight: activa ? FontWeight.w700 : FontWeight.w500,
                      color: activa ? AppColors.ink : AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
