import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../main.dart' show AppColors;
import '../services/ubicacion_actual.dart';
import '../widgets/bus_ui.dart';

/// Selector de un punto sobre el mapa, tipo app de transporte: hay un pin fijo
/// en el centro de la pantalla y el usuario mueve el mapa por debajo para
/// colocarlo. Al confirmar, devuelve el `LatLng` del centro.
///
/// Lo usan el padre (punto de recogida de su hijo) y el conductor (colegio de
/// destino), así que es genérico: [titulo] y [textoBoton] cambian el texto, y
/// [colorPin] deja distinguir la recogida del destino.
///
/// Se devuelve `null` si el usuario sale sin confirmar.
class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({
    super.key,
    required this.titulo,
    this.textoBoton = 'Confirmar punto',
    this.centroInicial,
    this.colorPin = AppColors.ink,
    this.ayuda,
  });

  final String titulo;
  final String textoBoton;

  /// Punto donde abre el mapa. Si es `null` se intenta usar la ubicación actual
  /// del dispositivo y, si no se puede, un centro por defecto.
  final LatLng? centroInicial;

  final Color colorPin;
  final String? ayuda;

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  /// Bogotá, para cuando no hay permiso de ubicación ni se pasó un centro.
  static const LatLng _centroPorDefecto = LatLng(4.60971, -74.08175);

  GoogleMapController? _controlador;
  LatLng? _centro;

  /// `true` solo mientras se está intentando averiguar dónde abrir el mapa (es
  /// decir, cuando no se pasó un [MapPickerScreen.centroInicial]). Deshabilita
  /// el botón de confirmar para que no se confirme un punto que todavía no
  /// existe.
  ///
  /// **Siempre se inicializa con el valor real**: cuando el llamador sí pasa
  /// `centroInicial` no hay nada que resolver y debe quedar en `false` desde el
  /// inicio. Antes estaba en `true` fijo y el único que desbloqueaba el botón
  /// era `_resolverCentroInicial()`, que justo en ese caso no se llamaba: el
  /// botón quedaba apagado para siempre.
  bool _resolviendoCentro = false;

  /// `true` mientras "Mi ubicación" está buscando la posición, para que el
  /// botón muestre progreso y no se pueda pulsar dos veces.
  bool _buscandoUbicacion = false;

  @override
  void initState() {
    super.initState();
    _centro = widget.centroInicial;
    _resolviendoCentro = widget.centroInicial == null;
    if (widget.centroInicial == null) _resolverCentroInicial();
  }

  @override
  void dispose() {
    _controlador?.dispose();
    super.dispose();
  }

  /// Abre el mapa en la ubicación del teléfono si ya hay permiso concedido.
  ///
  /// No muestra el diálogo del sistema aquí: pedir el permiso desde
  /// `initState` haría que apareciera solo al abrir el mapa, incluso cuando el
  /// usuario únicamente venía a mover el pin. El permiso se pide al tocar
  /// "Mi ubicación", que es cuando de verdad se necesita.
  Future<void> _resolverCentroInicial() async {
    LatLng centro = _centroPorDefecto;
    final UbicacionObtenida ubicacion =
        await UbicacionActual.obtenerSiYaHayPermiso();
    final posicion = ubicacion.posicion;
    if (posicion != null) {
      centro = LatLng(posicion.latitude, posicion.longitude);
    }

    if (!mounted) return;
    setState(() {
      _centro = centro;
      _resolviendoCentro = false;
    });
    if (_controlador != null) {
      await _controlador!.animateCamera(CameraUpdate.newLatLng(centro));
    }
  }

  /// Lleva el mapa a la posición actual del teléfono.
  ///
  /// Antes llamaba a `Geolocator.getCurrentPosition` directamente, sin pedir el
  /// permiso: Android lo negaba siempre que el usuario no lo hubiera concedido
  /// antes desde otra pantalla, y el resultado era el mismo mensaje
  /// "No pudimos obtener tu ubicación actual" una y otra vez. [UbicacionActual]
  /// revisa GPS, pide el permiso y cae a la última posición conocida.
  Future<void> _irAMiUbicacion() async {
    if (_buscandoUbicacion) return;
    setState(() => _buscandoUbicacion = true);

    final UbicacionObtenida ubicacion = await UbicacionActual.obtener();

    if (!mounted) return;
    setState(() => _buscandoUbicacion = false);

    final posicion = ubicacion.posicion;
    if (posicion == null) {
      // Solo se ofrece el atajo cuando el usuario puede resolverlo desde los
      // ajustes del teléfono.
      final bool bloqueado = ubicacion.permiso == PermisoUbicacion.bloqueado;
      final bool sinGps = ubicacion.permiso == PermisoUbicacion.sinServicio;
      _avisar(
        ubicacion.advertencia ?? 'No pudimos obtener tu ubicación actual.',
        etiquetaAccion: bloqueado
            ? 'Ajustes'
            : sinGps
                ? 'Activar'
                : null,
        accion: bloqueado
            ? UbicacionActual.abrirAjustes
            : sinGps
                ? UbicacionActual.abrirAjustesDeUbicacion
                : null,
      );
      return;
    }

    final destino = LatLng(posicion.latitude, posicion.longitude);
    await _controlador?.animateCamera(CameraUpdate.newLatLng(destino));
    if (!mounted) return;
    setState(() => _centro = destino);

    // Posición de caché (GPS sin fix): se avisa para que el usuario no confunda
    // un punto viejo con su posición real.
    if (ubicacion.advertencia != null) {
      _avisar(ubicacion.advertencia!);
    }
  }

  void _avisar(
    String mensaje, {
    String? etiquetaAccion,
    Future<bool> Function()? accion,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: accion == null ? AppColors.danger : AppColors.inkSoft,
        duration: const Duration(seconds: 6),
        action: etiquetaAccion == null || accion == null
            ? null
            : SnackBarAction(
                label: etiquetaAccion,
                textColor: Colors.white,
                onPressed: accion,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final centro = _centro ?? _centroPorDefecto;

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: centro, zoom: 16),
            onMapCreated: (c) => _controlador = c,
            onCameraMove: (posicion) => _centro = posicion.target,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            myLocationButtonEnabled: false,
            myLocationEnabled: false,
            padding: const EdgeInsets.only(bottom: 210),
          ),
          // Pin fijo en el centro: el mapa se mueve por debajo y el centro es
          // el punto elegido.
          IgnorePointer(
            child: Align(
              alignment: const Alignment(0, -0.18),
              child: Icon(
                Icons.location_on,
                size: 52,
                color: widget.colorPin,
                shadows: const [
                  Shadow(color: Colors.black45, blurRadius: 6),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildBarraSuperior(),
                const Spacer(),
                _buildPanelInferior(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarraSuperior() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: [
          Material(
            color: AppColors.surface,
            shape: const CircleBorder(),
            elevation: 3,
            shadowColor: Colors.black26,
            child: BusIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Volver',
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Text(
                widget.titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textStrong,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelInferior() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BusInfoBox(
            icon: Icons.touch_app_rounded,
            iconColor: AppColors.textMuted,
            child: Text(
              widget.ayuda ??
                  'Mueve el mapa para poner el pin donde quieras y confirma.',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppColors.textStrong,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textStrong,
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  // Deshabilitado mientras busca: evita lanzar dos lecturas del
                  // GPS y deja claro que algo está pasando.
                  onPressed: _buscandoUbicacion ? null : _irAMiUbicacion,
                  icon: _buscandoUbicacion
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.my_location_rounded,
                          size: 18,
                          color: AppColors.ink,
                        ),
                  label: const Text('Mi ubicación'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: BusPrimaryButton(
                  label: widget.textoBoton,
                  icon: Icons.check_circle_rounded,
                  loading: _resolviendoCentro,
                  onPressed: () => Navigator.of(context).pop(_centro),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
