import 'dart:async';

import 'package:bus_track_app/services/canal_compartido.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deja correr las microtareas pendientes (los `StreamController` entregan los
/// eventos de forma asíncrona).
Future<void> _microtareas() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('CanalCompartido', () {
    test('devuelve siempre el mismo stream', () {
      final canal = CanalCompartido<int>(() => const Stream<int>.empty());
      expect(identical(canal.stream, canal.stream), isTrue);
    });

    test('el oyente que llega tarde recibe la última instantánea', () async {
      final fuente = StreamController<int>.broadcast();
      final canal = CanalCompartido<int>(() => fuente.stream);

      final primero = <int>[];
      final sub1 = canal.stream.listen(primero.add);
      await _microtareas();

      fuente.add(1);
      await _microtareas();
      expect(primero, <int>[1]);

      // Segunda pantalla sobre el mismo documento: sin replay se quedaría
      // cargando hasta que el documento cambie.
      final segundo = <int>[];
      final sub2 = canal.stream.listen(segundo.add);
      await _microtareas();
      expect(segundo, <int>[1]);

      fuente.add(2);
      await _microtareas();
      expect(primero, <int>[1, 2]);
      expect(segundo, <int>[1, 2]);

      await sub1.cancel();
      await sub2.cancel();
      await fuente.close();
    });

    test('reabre la fuente cuando se queda sin oyentes', () async {
      final fuente = StreamController<int>.broadcast();
      var aperturas = 0;
      final canal = CanalCompartido<int>(() {
        aperturas++;
        return fuente.stream;
      });

      final primero = <int>[];
      final sub1 = canal.stream.listen(primero.add);
      await _microtareas();
      fuente.add(1);
      await _microtareas();
      expect(aperturas, 1);

      // Al irse el último oyente se cancela la suscripción a la fuente.
      await sub1.cancel();
      await _microtareas();

      final segundo = <int>[];
      final sub2 = canal.stream.listen(segundo.add);
      await _microtareas();
      expect(aperturas, 2);
      // El replay cubre el hueco mientras el nuevo listener de Firestore llega.
      expect(segundo, <int>[1]);

      fuente.add(2);
      await _microtareas();
      expect(segundo, <int>[1, 2]);

      await sub2.cancel();
      await fuente.close();
    });

    test('reenvía los errores a la pantalla', () async {
      final fuente = StreamController<int>.broadcast();
      final canal = CanalCompartido<int>(() => fuente.stream);

      final errores = <Object>[];
      final sub = canal.stream.listen((_) {}, onError: errores.add);
      await _microtareas();

      fuente.addError(StateError('permission-denied'));
      await _microtareas();
      expect(errores, hasLength(1));

      await sub.cancel();
      await fuente.close();
    });

    test('descartar no vuelve a abrir la fuente', () async {
      final fuente = StreamController<int>.broadcast();
      var aperturas = 0;
      final canal = CanalCompartido<int>(() {
        aperturas++;
        return fuente.stream;
      });

      final recibidos = <int>[];
      final sub = canal.stream.listen(recibidos.add);
      await _microtareas();
      await sub.cancel();
      await _microtareas();

      canal.descartar();

      final otro = canal.stream.listen(recibidos.add);
      await _microtareas();
      expect(aperturas, 1);
      await otro.cancel();
      await fuente.close();
    });
  });
}
