import 'package:cloud_firestore/cloud_firestore.dart';

/// Un hijo registrado por un padre.
///
/// La app nació con **un solo hijo por padre**, guardado dentro de la ficha
/// `usuarios/{uid}` (`childName`, `childAge`, `schoolName`, `busPlate`). Ese
/// formato sigue vivo para las cuentas que ya existen y no se migra a la fuerza:
/// se sintetiza con [Hijo.legado].
///
/// Los hijos nuevos viven en `estudiantes/{id}`, uno por documento, así que un
/// padre puede tener varios y cada uno puede ir en un bus distinto.
///
/// ## Por qué [id] es la clave de todo
///
/// La parada de un hijo se guarda en `recogida/{id}` y su estado en
/// `rutas/{driverUid}.estadoParadas[id]`. Para el hijo legado, [id] es el uid del
/// padre, que es exactamente la clave que usaba la versión anterior. Así sus
/// puntos de recogida, su historial y sus textos siguen funcionando sin tocar
/// ningún documento viejo.
class Hijo {
  const Hijo({
    required this.id,
    required this.nombre,
    this.edad,
    this.colegio,
    this.busPlate,
    this.driverName,
    this.driverUid,
    this.codigo,
    this.esLegado = false,
  });

  /// Id del documento en `estudiantes`, o el uid del padre si [esLegado].
  final String id;

  final String nombre;
  final int? edad;
  final String? colegio;

  /// Placa del bus al que está vinculado, o `null` si todavía no tiene.
  final String? busPlate;

  final String? driverName;
  final String? driverUid;

  /// Código con el que se vinculó el bus. Se conserva para poder mostrar de
  /// dónde salió la vinculación; no se usa para volver a resolverla.
  final String? codigo;

  /// `true` si viene de la ficha vieja `usuarios/{uid}` y no de `estudiantes`.
  final bool esLegado;

  bool get tieneBus => (busPlate ?? '').trim().isNotEmpty;

  /// Hijo a partir de un documento de `estudiantes/{id}`.
  static Hijo? desdeDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final datos = doc.data();
    if (datos == null) return null;
    return desdeMapa(doc.id, datos);
  }

  /// Igual que [desdeDoc] pero desde el mapa ya leído. El panel del padre
  /// recibe `QuerySnapshot` sin tipo (es el tipo que cachea
  /// `StreamsDeDocumento`), así que normaliza aquí en vez de castear en la
  /// pantalla.
  static Hijo? desdeMapa(String id, Map<String, dynamic> datos) {
    final String? nombre =
        textoDeFirestore(datos['nombre'] ?? datos['childName']);
    if (nombre == null) return null;

    return Hijo(
      id: id,
      nombre: nombre,
      edad: enteroDeFirestore(datos['edad'] ?? datos['childAge']),
      colegio: textoDeFirestore(datos['colegio'] ?? datos['schoolName']),
      busPlate: textoDeFirestore(datos['busPlate'])?.toUpperCase(),
      driverName: textoDeFirestore(datos['driverName']),
      driverUid: textoDeFirestore(datos['driverUid']),
      codigo: textoDeFirestore(datos['codigo']),
    );
  }

  /// Hijo sintetizado a partir de la ficha vieja del padre.
  ///
  /// Devuelve `null` si el padre nunca registró un hijo. El [id] es el uid del
  /// padre a propósito: es la clave que ya usaban `recogida/{uid}` y el
  /// `estadoParadas` del conductor.
  static Hijo? legado(String parentUid, Map<String, dynamic> perfil) {
    final String? nombre = textoDeFirestore(perfil['childName']);
    if (nombre == null) return null;

    return Hijo(
      id: parentUid,
      nombre: nombre,
      edad: enteroDeFirestore(perfil['childAge']),
      colegio: textoDeFirestore(perfil['schoolName']),
      busPlate: textoDeFirestore(perfil['busPlate'])?.toUpperCase(),
      driverName: textoDeFirestore(perfil['driverName']),
      esLegado: true,
    );
  }
}

/// El código que el conductor comparte con los padres para vincular un hijo a su
/// bus, resuelto desde `codigos/{codigo}`.
class CodigoBus {
  const CodigoBus({
    required this.codigo,
    required this.busPlate,
    this.driverUid,
    this.driverName,
  });

  final String codigo;
  final String busPlate;
  final String? driverUid;
  final String? driverName;

  static CodigoBus? desdeDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final datos = doc.data();
    if (datos == null || datos['activo'] != true) return null;

    final String? placa = textoDeFirestore(datos['busPlate'])?.toUpperCase();
    if (placa == null) return null;

    return CodigoBus(
      codigo: doc.id,
      busPlate: placa,
      driverUid: textoDeFirestore(datos['driverUid']),
      driverName: textoDeFirestore(datos['conductor'] ?? datos['driverName']),
    );
  }
}

/// Normaliza un valor de Firestore a texto no vacío, o `null`.
String? textoDeFirestore(dynamic valor) {
  if (valor == null) return null;
  final String s = valor.toString().trim();
  return s.isEmpty ? null : s;
}

/// Acepta un `int` de Firestore o un texto numérico y devuelve `null` si no es
/// un entero válido.
int? enteroDeFirestore(dynamic valor) {
  if (valor is int) return valor;
  if (valor is num) return valor.toInt();
  return int.tryParse(valor?.toString().trim() ?? '');
}
