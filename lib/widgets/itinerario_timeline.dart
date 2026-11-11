import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart' show AppColors;
import 'bus_ui.dart';

/// Un punto del itinerario de un bus, ya resuelto por la pantalla que lo lee.
///
/// No conoce Firestore: la vista de recorrido decide si un punto está recogido,
/// cuál es el siguiente y cuál es el colegio de destino.
class ParadaItinerario {
  const ParadaItinerario({
    required this.titulo,
    required this.subtitulo,
    this.completado = false,
    this.actual = false,
    this.esDestino = false,
  });

  final String titulo;
  final String subtitulo;

  /// El bus ya pasó por aquí: el punto y la línea de arriba se pintan verdes.
  final bool completado;

  /// Es la parada pendiente más cercana: se resalta en amarillo.
  final bool actual;

  /// Colegio de destino, último punto del itinerario.
  final bool esDestino;
}

/// Hora corta en formato de 12 h (8:15 a. m.), en la zona del teléfono.
///
/// La usan el recorrido del padre y el del conductor para que la misma marca de
/// tiempo se lea igual en los dos paneles.
String formatoHoraCorta(DateTime fecha) {
  final local = fecha.toLocal();
  final h12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minuto = local.minute.toString().padLeft(2, '0');
  final sufijo = local.hour < 12 ? 'a. m.' : 'p. m.';
  return '$h12:$minuto $sufijo';
}

/// Línea de tiempo vertical del recorrido del bus.
///
/// Pinta un punto por parada, unido por un segmento que se vuelve verde a medida
/// que el bus avanza. El primer punto pendiente se resalta en amarillo y el
/// colegio de destino se dibuja con un círculo hueco y un icono de escuela.
///
/// Es puramente visual y compartida: la usan la pestaña "Recorrido" del padre y
/// la del conductor, para que el mismo viaje se vea igual en los dos paneles.
class ItinerarioTimeline extends StatelessWidget {
  const ItinerarioTimeline({
    super.key,
    required this.paradas,
    this.textoVacio = 'El conductor aún no ha planificado su ruta.',
    this.iconoVacio = Icons.route_outlined,
  });

  final List<ParadaItinerario> paradas;
  final String textoVacio;
  final IconData iconoVacio;

  @override
  Widget build(BuildContext context) {
    if (paradas.isEmpty) {
      return BusInfoBox(
        icon: iconoVacio,
        iconColor: AppColors.textMuted,
        child: Text(
          textoVacio,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: AppColors.textMuted,
            height: 1.3,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < paradas.length; i++)
          _Punto(
            parada: paradas[i],
            esPrimero: i == 0,
            esUltimo: i == paradas.length - 1,
            anteriorCompletada: i > 0 && paradas[i - 1].completado,
          ),
      ],
    );
  }
}

/// Un punto del itinerario con su segmento de línea.
class _Punto extends StatelessWidget {
  const _Punto({
    required this.parada,
    required this.esPrimero,
    required this.esUltimo,
    required this.anteriorCompletada,
  });

  final ParadaItinerario parada;
  final bool esPrimero;
  final bool esUltimo;

  /// El segmento de arriba se pinta verde solo si el punto anterior ya se
  /// recogió; el de abajo, si este lo está.
  final bool anteriorCompletada;

  @override
  Widget build(BuildContext context) {
    final bool completado = parada.completado;
    final bool destino = parada.esDestino;

    final Color colorPunto = completado
        ? AppColors.success
        : (destino
            ? AppColors.ink
            : (parada.actual ? AppColors.primary : AppColors.border));

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              if (!esPrimero)
                Container(
                  width: 2,
                  height: 15,
                  color:
                      anteriorCompletada ? AppColors.success : AppColors.border,
                ),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: destino && !completado
                      ? Colors.transparent
                      : colorPunto,
                  border: Border.all(
                    color: destino && !completado ? AppColors.ink : colorPunto,
                    width: 3,
                  ),
                  boxShadow: [
                    if (parada.actual)
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.55),
                        blurRadius: 8,
                        spreadRadius: 3,
                      ),
                  ],
                ),
              ),
              if (!esUltimo)
                Expanded(
                  child: Container(
                    width: 2,
                    color: completado ? AppColors.success : AppColors.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          parada.titulo,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight:
                                parada.actual && !completado
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                            color: AppColors.textStrong,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          parada.subtitulo,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: completado
                                ? AppColors.success
                                : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (completado)
                    const Icon(
                      Icons.check_circle,
                      size: 18,
                      color: AppColors.success,
                    )
                  else if (destino)
                    const Icon(
                      Icons.school_rounded,
                      size: 18,
                      color: AppColors.ink,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
