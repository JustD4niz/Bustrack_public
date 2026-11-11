import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/hijo.dart';

/// Operaciones sobre los hijos del padre (`estudiantes`) y los códigos de
/// vinculación de los conductores (`codigos`).
///
/// La app empezó con **un** hijo guardado dentro de `usuarios/{uid}`. Ese
/// formato se sigue leyendo con [Hijo.legado] y se sigue escribiendo desde aquí
/// cuando el hijo editado es legado, para no obligar a migrar cuentas viejas.
class HijosService {
  HijosService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Alfabeto sin caracteres que se confunden al dictar un código: sin `0/O`,
  /// sin `1/I/L`. Un padre suele recibir el código por WhatsApp o de viva voz.
  static const String _alfabeto = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  static final Random _azar = Random.secure();

  /// Deja un texto libre en la forma canónica de un código.
  ///
  /// Acepta el código pelado (`ABC234`), un enlace con `?codigo=ABC234` y un
  /// enlace con el código como último segmento (`https://.../vincular/ABC234`).
  /// El QR del conductor hoy lleva el código pelado, pero normalizar de más no
  /// cuesta nada y evita rechazar un QR generado por otra versión.
  static String normalizarCodigo(String texto) {
    final String limpio = texto.trim();
    if (limpio.isEmpty) return '';

    String candidato = limpio;
    final Uri? uri = Uri.tryParse(limpio);
    if (uri != null && uri.hasScheme) {
      final String? porParametro =
          uri.queryParameters['codigo'] ?? uri.queryParameters['code'];
      if (porParametro != null && porParametro.trim().isNotEmpty) {
        candidato = porParametro;
      } else if (uri.pathSegments.isNotEmpty &&
          uri.pathSegments.last.trim().isNotEmpty) {
        candidato = uri.pathSegments.last;
      } else if (uri.host.isNotEmpty) {
        candidato = uri.host;
      }
    }

    return candidato.replaceAll(RegExp('[^A-Za-z0-9]'), '').toUpperCase();
  }

  /// Un código válido tiene entre 4 y 12 caracteres alfanuméricos. El generador
  /// produce 6, pero se aceptan más para no invalidar códigos ya repartidos si
  /// algún día cambia el largo.
  static bool esCodigoValido(String codigo) =>
      RegExp(r'^[A-Z0-9]{4,12}$').hasMatch(codigo);

  /// Genera un código nuevo. La unicidad se comprueba contra Firestore en
  /// [asegurarCodigoConductor], no aquí.
  static String generarCodigo({int largo = 6}) {
    return List<String>.generate(
      largo,
      (_) => _alfabeto[_azar.nextInt(_alfabeto.length)],
    ).join();
  }

  /// Hijos nuevos del padre. Sin `orderBy` a propósito: un `where` por un solo
  /// campo no necesita índice compuesto y el orden se resuelve en Dart.
  static Stream<QuerySnapshot> consultaHijos(String parentUid) {
    return _db
        .collection('estudiantes')
        .where('parentUid', isEqualTo: parentUid)
        .snapshots();
  }

  /// Convierte los documentos de [consultaHijos] en [Hijo], descartando los que
  /// no tienen nombre. El orden es por nombre para que el selector no cambie
  /// de orden con cada snapshot.
  static List<Hijo> hijosDesdeSnapshot(QuerySnapshot? snap) {
    final lista = <Hijo>[];
    if (snap == null) return lista;
    for (final doc in snap.docs) {
      final datos = doc.data();
      if (datos is! Map) continue;
      final hijo = Hijo.desdeMapa(
        doc.id,
        Map<String, dynamic>.from(datos),
      );
      if (hijo != null) lista.add(hijo);
    }
    lista.sort(
      (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
    );
    return lista;
  }

  /// Lista completa de hijos del padre: el legado (si lo hay) primero y después
  /// los documentos de `estudiantes`.
  ///
  /// El legado va primero para que una cuenta vieja siga abriendo en el mismo
  /// hijo que antes, incluso si con el tiempo agregó otros. Lo usan el panel y
  /// la pantalla "Mis hijos"; tenerlo en un solo sitio evita que las dos listas
  /// se ordenen distinto.
  static List<Hijo> listaCompleta({
    required String parentUid,
    required Map<String, dynamic> perfil,
    QuerySnapshot? snap,
  }) {
    final lista = <Hijo>[];
    final legado = Hijo.legado(parentUid, perfil);
    if (legado != null) lista.add(legado);
    lista.addAll(hijosDesdeSnapshot(snap));
    return lista;
  }

  /// Resuelve el código que comparte el conductor. Devuelve `null` si no existe
  /// o si fue desactivado.
  static Future<CodigoBus?> resolverCodigo(String texto) async {
    final String codigo = normalizarCodigo(texto);
    if (!esCodigoValido(codigo)) return null;

    final snap = await _db.collection('codigos').doc(codigo).get();
    if (!snap.exists) return null;
    return CodigoBus.desdeDoc(snap);
  }

  /// Crea un hijo. Si [vinculacion] no es `null`, nace ya asociado al bus.
  /// Devuelve el id del documento, que es la clave de `recogida`.
  static Future<String> crearHijo({
    required String parentUid,
    required String nombre,
    int? edad,
    String? colegio,
    CodigoBus? vinculacion,
  }) async {
    final doc = await _db.collection('estudiantes').add(<String, dynamic>{
      'parentUid': parentUid,
      'nombre': nombre.trim(),
      'edad': ?edad,
      'colegio': ?_limpiar(colegio),
      if (vinculacion != null) ...<String, dynamic>{
        'busPlate': vinculacion.busPlate,
        'driverUid': vinculacion.driverUid,
        'driverName': vinculacion.driverName,
        'codigo': vinculacion.codigo,
      },
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// Actualiza los datos de un hijo. [vincular] reemplaza el bus; con
  /// [quitarVinculo] se borra el vínculo actual. Sin ninguno de los dos, el bus
  /// que ya tenía se conserva.
  ///
  /// Si el hijo es legado, los datos se escriben en `usuarios/{uid}` (el único
  /// sitio donde existen) y se sincroniza el punto de recogida para que el
  /// conductor no siga viendo el nombre o la placa viejos.
  static Future<void> actualizarHijo({
    required Hijo hijo,
    required String nombre,
    int? edad,
    String? colegio,
    CodigoBus? vincular,
    bool quitarVinculo = false,
  }) async {
    final Map<String, dynamic> datos = <String, dynamic>{
      'nombre': nombre.trim(),
      'edad': edad ?? FieldValue.delete(),
      'colegio': _limpiar(colegio) ?? FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (vincular != null) {
      datos.addAll(<String, dynamic>{
        'busPlate': vincular.busPlate,
        'driverUid': vincular.driverUid,
        'driverName': vincular.driverName,
        'codigo': vincular.codigo,
      });
    } else if (quitarVinculo) {
      datos.addAll(<String, dynamic>{
        'busPlate': FieldValue.delete(),
        'driverUid': FieldValue.delete(),
        'driverName': FieldValue.delete(),
        'codigo': FieldValue.delete(),
      });
    }

    if (hijo.esLegado) {
      await _db.collection('usuarios').doc(hijo.id).update(<String, dynamic>{
        'childName': datos['nombre'],
        'childAge': edad ?? FieldValue.delete(),
        'schoolName': _limpiar(colegio) ?? FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (vincular != null) ...<String, dynamic>{
          'busPlate': vincular.busPlate,
          'driverName': vincular.driverName,
        },
        if (quitarVinculo) ...<String, dynamic>{
          'busPlate': FieldValue.delete(),
          'driverName': FieldValue.delete(),
        },
      });
    } else {
      await _db.collection('estudiantes').doc(hijo.id).update(datos);
    }

    // El punto de recogida guarda su propia copia del nombre y la placa. Si se
    // edita el hijo y no se sincroniza, el conductor ve el dato viejo.
    await _sincronizarRecogida(
      hijoId: hijo.id,
      cambios: <String, dynamic>{
        'childName': nombre.trim(),
        'studentId': hijo.id,
        if (vincular != null) 'busPlate': vincular.busPlate,
        // Las reglas de `recogida` dejan leer al conductor del bus
        // (`driverUid`), así que al cambiar de vínculo hay que actualizarlo o
        // el punto seguiría visible para el conductor anterior.
        if (vincular != null) 'driverUid': vincular.driverUid,
        if (quitarVinculo) 'busPlate': FieldValue.delete(),
        if (quitarVinculo) 'driverUid': FieldValue.delete(),
      },
    );
  }

  /// Borra un hijo y su punto de recogida. La ruta activa no se toca: si el
  /// conductor ya lo había recogido, el historial conserva la parada.
  static Future<void> eliminarHijo(Hijo hijo) async {
    if (hijo.esLegado) {
      // No se puede borrar un documento `usuarios` a la ligera: es la cuenta.
      // Se quitan solo los campos del hijo legado.
      await _db.collection('usuarios').doc(hijo.id).update(<String, dynamic>{
        'childName': FieldValue.delete(),
        'childAge': FieldValue.delete(),
        'schoolName': FieldValue.delete(),
        'busPlate': FieldValue.delete(),
        'driverName': FieldValue.delete(),
      });
    } else {
      await _db.collection('estudiantes').doc(hijo.id).delete();
    }

    try {
      await _db.collection('recogida').doc(hijo.id).delete();
    } catch (_) {
      // Si no había punto marcado o las reglas lo impiden, el hijo ya quedó
      // borrado; no vale dejar la pantalla atascada por esto.
    }
  }

  /// Devuelve el código activo del conductor para esa placa y, si no tiene,
  /// crea uno nuevo.
  ///
  /// Busca por `driverUid` (un solo campo, sin índice compuesto) y filtra en
  /// Dart por placa y `activo`. Un conductor con dos buses tiene un código por
  /// cada uno, así que no se puede reutilizar el primero que aparezca.
  static Future<CodigoBus> asegurarCodigoConductor({
    required String driverUid,
    required String placa,
    required String conductor,
  }) async {
    final String placaNormal = placa.trim().toUpperCase();
    if (placaNormal.isEmpty) {
      throw ArgumentError('La placa es obligatoria para generar un código.');
    }

    final existentes = await _db
        .collection('codigos')
        .where('driverUid', isEqualTo: driverUid)
        .get();

    for (final doc in existentes.docs) {
      final datos = doc.data();
      final String delDoc =
          (datos['busPlate'] ?? '').toString().trim().toUpperCase();
      if (datos['activo'] == true && delDoc == placaNormal) {
        return CodigoBus(
          codigo: doc.id,
          busPlate: placaNormal,
          driverUid: driverUid,
          driverName: _nombreDelDoc(datos, conductor),
        );
      }
    }

    final CodigoBus? nuevo = await _crearCodigoUnico(
      driverUid: driverUid,
      placa: placaNormal,
      conductor: conductor,
    );
    if (nuevo == null) {
      throw StateError('No se pudo generar un código único.');
    }
    return nuevo;
  }

  /// Invalida el código actual del bus y crea otro. El anterior se marca
  /// `activo: false` en vez de borrarse: así un padre que lo tenía guardado
  /// recibe "código no válido" en lugar de que su hijo apunte a nada.
  static Future<CodigoBus> regenerarCodigoConductor({
    required String driverUid,
    required String placa,
    required String conductor,
  }) async {
    final String placaNormal = placa.trim().toUpperCase();
    final existentes = await _db
        .collection('codigos')
        .where('driverUid', isEqualTo: driverUid)
        .get();

    for (final doc in existentes.docs) {
      final datos = doc.data();
      final String delDoc =
          (datos['busPlate'] ?? '').toString().trim().toUpperCase();
      if (datos['activo'] == true && delDoc == placaNormal) {
        await doc.reference.set(
          <String, dynamic>{'activo': false},
          SetOptions(merge: true),
        );
      }
    }

    final CodigoBus? nuevo = await _crearCodigoUnico(
      driverUid: driverUid,
      placa: placaNormal,
      conductor: conductor,
    );
    if (nuevo == null) {
      throw StateError('No se pudo generar un código único.');
    }
    return nuevo;
  }

  /// Pide un código al azar y confirma que no existe antes de escribirlo. La
  /// probabilidad de colisión es baja, pero dos conductores generando a la vez
  /// podrían pisarse; ocho intentos son de sobra.
  static Future<CodigoBus?> _crearCodigoUnico({
    required String driverUid,
    required String placa,
    required String conductor,
  }) async {
    for (var intento = 0; intento < 8; intento++) {
      final String codigo = generarCodigo();
      final ref = _db.collection('codigos').doc(codigo);
      final snap = await ref.get();
      if (snap.exists) continue;

      await ref.set(<String, dynamic>{
        'busPlate': placa,
        'driverUid': driverUid,
        'conductor': conductor.trim(),
        'activo': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return CodigoBus(
        codigo: codigo,
        busPlate: placa,
        driverUid: driverUid,
        driverName: conductor.trim(),
      );
    }
    return null;
  }

  static String _nombreDelDoc(Map<String, dynamic> datos, String respaldo) {
    final String nombre = (datos['conductor'] ?? datos['driverName'] ?? '')
        .toString()
        .trim();
    return nombre.isEmpty ? respaldo.trim() : nombre;
  }

  /// Copia el teléfono del padre a todos sus puntos de recogida.
  ///
  /// El conductor no puede leer `usuarios/{uid}` (las reglas solo dejan al
  /// dueño y al admin), así que el número con el que llama al padre viaja dentro
  /// de `recogida`. Al editar el perfil hay que refrescarlo o el conductor
  /// seguiría viendo el teléfono viejo hasta que el padre moviera su pin.
  static Future<void> sincronizarTelefonoPadre({
    required String parentUid,
    required String telefono,
  }) async {
    final String numero = telefono.trim();
    if (numero.isEmpty) return;
    try {
      final snap = await _db
          .collection('recogida')
          .where('parentUid', isEqualTo: parentUid)
          .get();
      if (snap.docs.isEmpty) return;

      final lote = _db.batch();
      for (final doc in snap.docs) {
        lote.update(doc.reference, <String, dynamic>{
          'parentPhone': numero,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await lote.commit();
    } catch (_) {
      // El perfil ya quedó guardado; un fallo aquí solo deja el teléfono viejo
      // en los puntos de recogida hasta que el padre vuelva a mover el pin.
    }
  }

  /// Actualiza `recogida/{hijoId}` solo si el padre ya marcó un punto.
  static Future<void> _sincronizarRecogida({
    required String hijoId,
    required Map<String, dynamic> cambios,
  }) async {
    try {
      final ref = _db.collection('recogida').doc(hijoId);
      final snap = await ref.get();
      if (!snap.exists) return;
      await ref.set(
        <String, dynamic>{
          ...cambios,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // El hijo ya quedó guardado; un fallo aquí solo deja el nombre viejo en
      // el mapa del conductor hasta que el padre vuelva a marcar el punto.
    }
  }

  static String? _limpiar(String? valor) {
    final String? limpio = textoDeFirestore(valor);
    return limpio;
  }
}
