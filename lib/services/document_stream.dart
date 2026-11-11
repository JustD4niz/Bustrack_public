import 'package:cloud_firestore/cloud_firestore.dart';

import 'canal_compartido.dart';

/// Cachea un `snapshots()` por ruta, mientras viva la pantalla.
///
/// Por qué existe: `FirebaseFirestore.instance.doc(ruta).snapshots()` evaluado
/// dentro de `build` devuelve un objeto **nuevo** en cada reconstrucción, y
/// `StreamBuilder` decide si se resuscribe comparando la identidad de ese
/// objeto. Con el stream efímero, cada `setState` cancelaba la suscripción
/// anterior y abría otra, es decir, un listen target nuevo de Firestore por
/// tecla. Eso no es solo tráfico: en web el SDK JS llega a fallar con
/// "INTERNAL ASSERTION FAILED: Unexpected state" en `WatchChangeAggregator`.
///
/// El caché devuelve siempre la misma instancia, así que `StreamBuilder` ya no
/// se resuscribe al reconstruir. La clave es la ruta completa del documento,
/// porque dos pantallas mirando el mismo documento deben compartir la misma
/// suscripción.
///
/// La otra mitad del problema la resuelve [CanalCompartido]: `snapshots()` es un
/// stream *broadcast* y no repite el último evento, así que sin replay la
/// segunda pantalla que se suscribía al mismo documento se quedaba cargando
/// para siempre. Ver `lib/services/canal_compartido.dart`.
class StreamsDeDocumento {
  final Map<String, CanalCompartido<DocumentSnapshot>> _porRuta =
      <String, CanalCompartido<DocumentSnapshot>>{};

  final Map<String, CanalCompartido<QuerySnapshot>> _porConsulta =
      <String, CanalCompartido<QuerySnapshot>>{};

  Stream<DocumentSnapshot> de(String ruta) => _porRuta
      .putIfAbsent(
        ruta,
        () => CanalCompartido<DocumentSnapshot>(
          () => FirebaseFirestore.instance.doc(ruta).snapshots(),
        ),
      )
      .stream;

  /// Igual que [de], pero para `where(...)`. La clave la pone quien llama porque
  /// una consulta no tiene una ruta única: dos consultas distintas sobre la
  /// misma colección necesitan claves distintas, y la misma consulta debe
  /// reutilizar siempre la misma clave.
  Stream<QuerySnapshot> deConsulta(
    String clave,
    Stream<QuerySnapshot> Function() crear,
  ) =>
      _porConsulta
          .putIfAbsent(clave, () => CanalCompartido<QuerySnapshot>(crear))
          .stream;

  /// Cierra y vuelve a abrir los streams que el usuario abrió y ya no necesita
  /// (por ejemplo al quitar la placa de su perfil). Sin esto, el listener sigue
  /// escuchando documentos que la pantalla ya no muestra.
  void olvidar(String ruta) {
    _porRuta.remove(ruta)?.descartar();
  }
}
