import 'package:bus_track_app/screens/driver_ruta_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Regresión del bug: la pestaña "Estudiantes" del conductor solo leía
/// `recogida`, así que un hijo vinculado al bus **sin punto de recogida** no
/// aparecía en ninguna parte y el conductor no sabía que existía.
///
/// La fusión es pura (`fusionarEstudiantes`), así que se prueba sin red ni
/// Firebase.
void main() {
  const LatLng punto = LatLng(4.65, -74.05);

  ParadaRecogida recogida({
    required String studentId,
    String etiqueta = 'Estudiante',
    String? parentName,
    String? parentPhone,
  }) {
    return ParadaRecogida(
      studentId: studentId,
      parentUid: 'padre-$studentId',
      punto: punto,
      etiqueta: etiqueta,
      parentName: parentName,
      parentPhone: parentPhone,
    );
  }

  group('fusionarEstudiantes', () {
    test('un hijo vinculado sin punto de recogida sí aparece', () {
      final lista = fusionarEstudiantes(
        vinculados: const <EstudianteBus>[
          EstudianteBus(
            studentId: 'a1',
            nombre: 'Ana',
            busPlate: 'ABC123',
          ),
        ],
        recogidas: const <ParadaRecogida>[],
        placa: 'ABC123',
      );

      expect(lista, hasLength(1));
      expect(lista.single.nombre, 'Ana');
      expect(lista.single.tienePunto, isFalse);
      expect(lista.single.parentPhone, isNull);
    });

    test('el punto de recogida aporta el teléfono del padre', () {
      final lista = fusionarEstudiantes(
        vinculados: const <EstudianteBus>[
          EstudianteBus(
            studentId: 'a1',
            nombre: 'Ana',
            busPlate: 'ABC123',
          ),
        ],
        recogidas: <ParadaRecogida>[
          recogida(
            studentId: 'a1',
            etiqueta: 'Ana',
            parentName: 'Marta',
            parentPhone: '3001234567',
          ),
        ],
        placa: 'ABC123',
      );

      expect(lista, hasLength(1));
      expect(lista.single.tienePunto, isTrue);
      expect(lista.single.parentName, 'Marta');
      expect(lista.single.parentPhone, '3001234567');
    });

    test('un punto sin fila en estudiantes (hijo legado) también aparece', () {
      final lista = fusionarEstudiantes(
        vinculados: const <EstudianteBus>[],
        recogidas: <ParadaRecogida>[
          recogida(studentId: 'uid-padre', etiqueta: 'Luis'),
        ],
        placa: 'ABC123',
      );

      expect(lista, hasLength(1));
      expect(lista.single.studentId, 'uid-padre');
      expect(lista.single.nombre, 'Luis');
      expect(lista.single.tienePunto, isTrue);
    });

    test('no duplica y ordena por nombre', () {
      final lista = fusionarEstudiantes(
        vinculados: const <EstudianteBus>[
          EstudianteBus(studentId: 'a1', nombre: 'Zoe', busPlate: 'ABC123'),
          EstudianteBus(studentId: 'a2', nombre: 'Ana', busPlate: 'ABC123'),
        ],
        recogidas: <ParadaRecogida>[
          recogida(studentId: 'a1', etiqueta: 'Zoe'),
        ],
        placa: 'ABC123',
      );

      expect(lista.map((e) => e.studentId), <String>['a2', 'a1']);
    });

    test('filtra los estudiantes de otra placa', () {
      final lista = fusionarEstudiantes(
        vinculados: const <EstudianteBus>[
          EstudianteBus(studentId: 'a1', nombre: 'Ana', busPlate: 'ABC123'),
          EstudianteBus(studentId: 'b1', nombre: 'Beto', busPlate: 'XYZ789'),
        ],
        recogidas: const <ParadaRecogida>[],
        placa: 'ABC123',
      );

      expect(lista.map((e) => e.studentId), <String>['a1']);
    });

    test('un documento viejo sin placa se incluye igual', () {
      final lista = fusionarEstudiantes(
        vinculados: const <EstudianteBus>[
          EstudianteBus(studentId: 'a1', nombre: 'Ana'),
        ],
        recogidas: const <ParadaRecogida>[],
        placa: 'ABC123',
      );

      expect(lista, hasLength(1));
    });
  });
}
