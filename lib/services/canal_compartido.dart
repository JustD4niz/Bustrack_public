import 'dart:async';

/// Un stream compartido por varias pantallas que **repite el último evento** a
/// quien se suscribe tarde.
///
/// Existe por un detalle de Firestore: `Query.snapshots()` devuelve un stream
/// *broadcast* (ver `method_channel_query.dart`, `StreamController.broadcast`),
/// y un broadcast **no guarda el último evento** para los oyentes nuevos. Con un
/// caché ingenuo, la segunda pantalla que se suscribía al mismo documento —el
/// panel ya lo tenía abierto debajo— se quedaba esperando un cambio que podía no
/// llegar nunca, y su `StreamBuilder` se quedaba en `ConnectionState.waiting`:
/// "Mis datos" giraba para siempre.
///
/// Aquí hay una sola suscripción a la fuente, se guarda el último evento y se
/// replica a cada oyente nuevo. Cuando se va el último oyente la suscripción a la
/// fuente se cancela (no tiene sentido seguir pagando el listener) y se reabre
/// en la siguiente suscripción.
class CanalCompartido<T> {
  CanalCompartido(this._crear);

  /// Abre la suscripción real a la fuente. Se llama una vez por apertura.
  final Stream<T> Function() _crear;

  late final StreamController<T> _controlador =
      StreamController<T>.broadcast(onListen: _abrir, onCancel: _cerrar);

  /// Stream que reciben las pantallas. Es **siempre el mismo objeto**: los
  /// widgets comparan identidad para decidir si se resuscriben, así que crear un
  /// stream nuevo en cada llamada reabriría el listener en cada rebuild.
  late final Stream<T> stream = Stream<T>.multi((emisor) {
    final ultimo = _ultimo;
    if (_hayUltimo && ultimo != null) emisor.add(ultimo);

    final suscripcion = _controlador.stream.listen(
      emisor.add,
      onError: emisor.addError,
      onDone: emisor.close,
    );
    emisor.onCancel = suscripcion.cancel;
  }, isBroadcast: true);

  StreamSubscription<T>? _suscripcion;
  T? _ultimo;
  bool _hayUltimo = false;
  bool _terminado = false;

  void _abrir() {
    if (_suscripcion != null || _terminado) return;
    _suscripcion = _crear().listen(
      (evento) {
        _ultimo = evento;
        _hayUltimo = true;
        _controlador.add(evento);
      },
      // Los errores (por ejemplo `permission-denied`) se reenvían a la pantalla
      // en vez de tragárselos: cerrar el canal dejaría el spinner girando.
      onError: _controlador.addError,
      onDone: () {
        _terminado = true;
        _controlador.close();
      },
    );
  }

  void _cerrar() {
    _suscripcion?.cancel();
    _suscripcion = null;
  }

  /// Cierra el canal para siempre y suelta la fuente.
  void descartar() {
    _suscripcion?.cancel();
    _suscripcion = null;
    _terminado = true;
    if (!_controlador.isClosed) _controlador.close();
  }
}
