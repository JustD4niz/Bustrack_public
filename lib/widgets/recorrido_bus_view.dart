import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart' show AppColors;
import '../services/document_stream.dart';
import 'bus_ui.dart';
import 'itinerario_timeline.dart';

/// Un punto de recogida del bus, leído de la colección `recogida` (ruta en
/// vivo) o del historial (`rutas/{uid}/historial`, ruta ya cerrada).
class _Parada {
  const _Parada({
    required this.id,
    required this.etiqueta,
    required this.recogido,
    required this.esMia,
    this.hora,
  });

  /// Id del hijo (`recogida/{id}`) o, para el hijo legado, el uid del padre.
  final String id;
  final String etiqueta;
  final bool recogido;
  final bool esMia;

  /// Hora a la que el bus pasó por este punto: la del historial o, en una ruta
  /// en vivo, la de `estadoParadas[id].subioEn`.
  final DateTime? hora;
}

/// Pestaña "Recorrido" del bus: el itinerario, compartido por el padre y el
/// conductor.
///
/// Reúne en una sola vista el icono del bus con el estado de la ruta (en
/// amarillo), la línea de tiempo "Ruta y Paradas" (los puntos de recogida y, al
/// final, el colegio de destino) y —si el padre miró el mapa— su propio punto
/// marcado como tal.
///
/// **No lleva mapa**: el mapa en vivo es otra pestaña de cada panel. Lee
/// `buses/{placa}` para llegar al conductor y a las paradas anónimas, y
/// `rutas/{driverUid}` para el destino y los recogidos.
///
/// La misma vista sirve para los dos paneles: el padre pasa [studentId] para que
/// su punto se marque como "(tu punto)" y el conductor no. Antes de iniciar la
/// ruta, `buses/{placa}` todavía no existe o no tiene `driverUid`, así que el
/// conductor pasa [driverUidRespaldo] con su propio uid para ver el destino que
/// ya dejó guardado en `rutas/{uid}`.
class RecorridoBusView extends StatelessWidget {
  const RecorridoBusView({
    super.key,
    required this.streams,
    required this.placa,
    this.studentId,
    this.driverUidRespaldo,
    this.titulo = 'Recorrido del bus',
    this.textoSinBus =
        'No tienes ninguna placa de bus asociada a tu cuenta.',
    this.textoSinRutaConductor = 'El conductor aún no ha planificado su ruta.',
  });

  final StreamsDeDocumento streams;

  /// Placa del bus, o `null`/vacía si todavía no tiene una asignada.
  final String? placa;

  /// Id del hijo seleccionado, para marcar cuál punto de recogida es el suyo.
  /// El conductor no lo pasa.
  final String? studentId;

  /// uid del conductor, para leer `rutas/{uid}` cuando `buses/{placa}` todavía
  /// no lo publica (ruta aún no iniciada).
  final String? driverUidRespaldo;

  final String titulo;

  /// Mensaje cuando no hay placa vinculada.
  final String textoSinBus;

  /// Mensaje cuando el conductor todavía no eligió colegio de destino.
  final String textoSinRutaConductor;

  @override
  Widget build(BuildContext context) {
    final placa = this.placa;
    if (placa == null || placa.isEmpty) {
      return _Aviso(texto: textoSinBus);
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: streams.de('buses/$placa'),
      builder: (context, snapBus) {
        final bus = (snapBus.hasData && snapBus.data!.exists)
            ? (snapBus.data!.data() as Map<String, dynamic>)
            : <String, dynamic>{};
        final driverUid = _texto(bus['driverUid']) ?? _texto(driverUidRespaldo);
        final estadoRuta = _texto(bus['estadoRuta']);
        final activa = bus['enMovimiento'] == true;
        final finalizada = (estadoRuta ?? '').toLowerCase() == 'finalizada';

        // Tres estados: ruta en curso → itinerario vivo; ruta ya cerrada →
        // último recorrido guardado ("Esta ruta se finalizó"); sin iniciar →
        // el plan que el conductor haya dejado (destino y paradas).
        if (finalizada && !activa) {
          return _buildFinalizada(driverUid, estadoRuta);
        }
        return _buildEnVivo(driverUid, estadoRuta, bus);
      },
    );
  }

  /// Itinerario en vivo: destino y recogidos de `rutas/{driverUid}` y las
  /// paradas anónimas que el conductor publica en
  /// `buses/{placa}.paradasPublicas`.
  Widget _buildEnVivo(
    String? driverUid,
    String? estadoRuta,
    Map<String, dynamic> bus,
  ) {
    return StreamBuilder<DocumentSnapshot>(
      stream: driverUid == null ? null : streams.de('rutas/$driverUid'),
      builder: (context, snapRuta) {
        final ruta = (snapRuta.hasData && snapRuta.data!.exists)
            ? (snapRuta.data!.data() as Map<String, dynamic>)
            : <String, dynamic>{};
        final destino = _leerDestino(ruta);
        final recogidos = _leerRecogidos(ruta);
        final paradas = _leerParadasPublicas(bus['paradasPublicas'], recogidos);
        return _marco(
          cabecera: _buildCabecera(estadoRuta),
          cuerpo: _buildRutaYParadas(destino, paradas),
        );
      },
    );
  }

  /// Recorrido ya finalizado: el último registro de
  /// `rutas/{driverUid}/historial`, con la hora de cada parada.
  Widget _buildFinalizada(String? driverUid, String? estadoRuta) {
    if (driverUid == null) {
      return _marco(
        cabecera: _buildCabecera(estadoRuta),
        cuerpo: _buildRutaYParadas(null, const <_Parada>[]),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: streams.deConsulta(
        'historial/$driverUid',
        () => FirebaseFirestore.instance
            .collection('rutas')
            .doc(driverUid)
            .collection('historial')
            .orderBy('finalizada', descending: true)
            .limit(1)
            .snapshots(),
      ),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const <QueryDocumentSnapshot>[];
        if (docs.isEmpty) {
          return _marco(
            cabecera: _buildCabecera(estadoRuta),
            cuerpo: _buildRutaYParadas(null, const <_Parada>[]),
          );
        }

        final historial = docs.first.data() as Map<String, dynamic>;
        final destino = _leerDestino(historial);
        final paradas = _leerParadasHistorial(historial);
        final finalizada = historial['finalizada'];

        return _marco(
          cabecera: _buildCabecera(estadoRuta),
          cuerpo: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildBannerFinalizada(finalizada),
              const SizedBox(height: 16),
              _buildRutaYParadas(destino, paradas),
            ],
          ),
        );
      },
    );
  }

  /// Marco común a las dos vistas: scroll, ancho máximo y las dos tarjetas.
  Widget _marco({required Widget cabecera, required Widget cuerpo}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cabecera,
              const SizedBox(height: 16),
              cuerpo,
            ],
          ),
        ),
      ),
    );
  }

  /// Banda en amarillo pálido con el aviso de que la ruta terminó y a qué hora.
  Widget _buildBannerFinalizada(dynamic finalizada) {
    final hora = finalizada is Timestamp
        ? ' · ${formatoHoraCorta(finalizada.toDate())}'
        : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primaryPale,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      child: Row(
        children: [
          const BusIconBadge(
            icon: Icons.check_rounded,
            size: 36,
            iconSize: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Esta ruta se finalizó$hora',
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

  /// Cabecera: icono del bus y el estado de la ruta en una píldora negra.
  Widget _buildCabecera(String? estadoRuta) {
    return BusCard(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      child: Row(
        children: [
          const BusIconBadge(
            icon: Icons.directions_bus_filled_rounded,
            size: 64,
            iconSize: 34,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textStrong,
                  ),
                ),
                const SizedBox(height: 8),
                _buildChipEstado(estadoRuta),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Píldora negra con punto amarillo y el estado de la ruta.
  Widget _buildChipEstado(String? estadoRuta) {
    final String estado = estadoRuta ?? 'Sin iniciar';
    final bool activa = estado.toLowerCase() == 'en ruta';
    return BusStatusPill(
      label: estado,
      dotColor: activa ? AppColors.primary : AppColors.textMuted,
    );
  }

  /// Tarjeta "Ruta y Paradas": línea de tiempo con los puntos de recogida y el
  /// colegio de destino al final.
  Widget _buildRutaYParadas(String? destino, List<_Parada> paradas) {
    final bool hayParadas = paradas.isNotEmpty;
    final bool vacio = destino == null && !hayParadas;

    final List<ParadaItinerario> puntos = [
      for (var i = 0; i < paradas.length; i++)
        ParadaItinerario(
          titulo: paradas[i].esMia
              ? '${paradas[i].etiqueta} (tu punto)'
              : paradas[i].etiqueta,
          subtitulo: paradas[i].recogido
              ? (paradas[i].hora == null
                  ? 'Ya recogido'
                  : 'Recogido · ${formatoHoraCorta(paradas[i].hora!)}')
              : 'Punto de recogida',
          completado: paradas[i].recogido,
          actual: _esSiguiente(paradas, i),
        ),
      if (destino != null)
        ParadaItinerario(
          titulo: destino,
          subtitulo: 'Colegio de destino',
          esDestino: true,
        ),
    ];

    return BusCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const BusIconBadge(
                icon: Icons.route_rounded,
                size: 38,
                color: AppColors.primaryPale,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ruta y Paradas',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textStrong,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (vacio)
            ItinerarioTimeline(
              paradas: const <ParadaItinerario>[],
              textoVacio: textoSinRutaConductor,
            )
          else
            ItinerarioTimeline(paradas: puntos),
        ],
      ),
    );
  }

  /// El primer punto pendiente es "el actual" de la ruta.
  bool _esSiguiente(List<_Parada> paradas, int indice) {
    if (paradas[indice].recogido) return false;
    for (var i = 0; i < indice; i++) {
      if (!paradas[i].recogido) return false;
    }
    return true;
  }

  String? _leerDestino(Map<String, dynamic> ruta) {
    final destino = ruta['destino'];
    if (destino is Map) {
      final nombre = _texto(destino['nombre']);
      if (nombre != null) return nombre;
    }
    return null;
  }

  /// uid → hora en que el conductor confirmó con "Ya recogí" que ese estudiante
  /// subió al bus. La hora puede faltar (documentos viejos), así que el mapa
  /// distingue "recogido" (`containsKey`) de "recogido a tal hora".
  ///
  /// Se leen las dos formas del documento: `estadoParadas` (la actual, escrita
  /// por "Ya recogí") y `recogidos` (la lista plana de versiones anteriores).
  Map<String, DateTime?> _leerRecogidos(Map<String, dynamic> ruta) {
    final mapa = <String, DateTime?>{};

    final estado = ruta['estadoParadas'];
    if (estado is Map) {
      estado.forEach((k, v) {
        if (v is! Map) return;
        final valor = v['subioEn'];
        if (valor == null) return;
        mapa[k.toString()] = valor is Timestamp ? valor.toDate() : null;
      });
    }

    final crudos = ruta['recogidos'];
    if (crudos is List) {
      for (final r in crudos) {
        mapa.putIfAbsent(r.toString(), () => null);
      }
    }
    return mapa;
  }

  /// Paradas anónimas publicadas por el conductor en
  /// `buses/{placa}.paradasPublicas` (`{id, lat, lng}`). Se cruzarlas con
  /// `recogidos` para saber cuáles ya se completaron.
  List<_Parada> _leerParadasPublicas(
    dynamic crudas,
    Map<String, DateTime?> recogidos,
  ) {
    final lista = <_Parada>[];
    if (crudas is! List) return lista;
    for (final item in crudas) {
      if (item is! Map) continue;
      final id = (item['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      lista.add(
        _Parada(
          id: id,
          etiqueta: 'Punto de recogida',
          recogido: recogidos.containsKey(id),
          esMia: studentId != null && id == studentId,
          hora: recogidos[id],
        ),
      );
    }
    return lista;
  }

  /// Paradas guardadas dentro de un registro del historial.
  List<_Parada> _leerParadasHistorial(Map<String, dynamic> historial) {
    final crudas = historial['paradas'];
    final lista = <_Parada>[];
    if (crudas is! List) return lista;
    for (final item in crudas) {
      if (item is! Map) continue;
      // Los registros nuevos guardan `studentId`; los viejos, solo `parentUid`.
      // Para el hijo legado ambos son el uid del padre, así que el respaldo
      // mantiene funcionando el historial ya escrito.
      final id = _texto(item['studentId']) ?? _texto(item['parentUid']) ?? '';
      final hora = item['hora'];
      lista.add(
        _Parada(
          id: id,
          etiqueta: _texto(item['etiqueta']) ?? 'Punto de recogida',
          recogido: item['recogido'] == true,
          esMia: studentId != null && id == studentId,
          hora: hora is Timestamp ? hora.toDate() : null,
        ),
      );
    }
    return lista;
  }

  String? _texto(dynamic valor) {
    if (valor == null) return null;
    final s = valor.toString().trim();
    return s.isEmpty ? null : s;
  }
}

/// Mensaje centrado, para cuando no hay placa que seguir.
class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return BusEmptyState(
      text: texto,
      icon: Icons.route_rounded,
    );
  }
}
