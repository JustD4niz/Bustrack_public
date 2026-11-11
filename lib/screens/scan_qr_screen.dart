import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart' show AppColors;
import '../services/hijos_service.dart';
import '../widgets/bus_ui.dart';

/// Escáner de QR para vincular un hijo al bus de un conductor.
///
/// Devuelve por `Navigator.pop` el **código normalizado** (no el texto crudo del
/// QR), o `null` si el usuario cierra sin escanear. La pantalla no resuelve el
/// código contra Firestore: de eso se encarga quien la abre, para que un QR de
/// otro producto no se confunda con un bus válido.
///
/// La cámara se pide en tiempo de ejecución. `CAMERA` está declarado en el
/// manifiesto (ver `android/app/src/main/AndroidManifest.xml`) porque, a
/// diferencia del selector de fotos, el escáner **sí** abre la cámara desde la
/// app y necesita el permiso.
class ScanQrScreen extends StatefulWidget {
  const ScanQrScreen({super.key});

  @override
  State<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends State<ScanQrScreen> {
  late final MobileScannerController _controlador = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _linterna = false;
  bool _procesando = false;
  String? _aviso;

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  void _alDetectar(BarcodeCapture captura) {
    if (_procesando || !mounted) return;
    String? crudo;
    for (final barcode in captura.barcodes) {
      final String valor = (barcode.rawValue ?? '').trim();
      if (valor.isNotEmpty) {
        crudo = valor;
        break;
      }
    }
    if (crudo == null) return;

    final String codigo = HijosService.normalizarCodigo(crudo);
    if (!HijosService.esCodigoValido(codigo)) {
      // Un QR de una página web o de otro producto: se avisa una vez y se
      // sigue escaneando. `noDuplicates` evita repetir el mismo aviso en cada
      // frame.
      setState(() => _aviso = 'Ese código no es de BusTrack. Prueba con el QR '
          'del conductor.');
      return;
    }

    _procesando = true;
    Navigator.of(context).pop(codigo);
  }

  Future<void> _alternarLinterna() async {
    try {
      await _controlador.toggleTorch();
      if (mounted) setState(() => _linterna = !_linterna);
    } catch (_) {
      // Algunos dispositivos no tienen linterna; el escáner sigue funcionando.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  BusIconButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Cerrar',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Escanear QR del bus',
                      style: busText(
                        size: 18,
                        weight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  BusIconButton(
                    icon: _linterna
                        ? Icons.flashlight_off_rounded
                        : Icons.flashlight_on_rounded,
                    tooltip: _linterna ? 'Apagar linterna' : 'Encender linterna',
                    onTap: _alternarLinterna,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _controlador,
                      onDetect: _alDetectar,
                      errorBuilder: (context, error) =>
                          _buildErrorCamara(error),
                    ),
                    const _MarcoDeEscaneo(),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 24,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          _aviso ??
                              'Apunta al QR que muestra el conductor en su '
                                  'panel. También puedes escribir el código a '
                                  'mano.',
                          textAlign: TextAlign.center,
                          style: busText(
                            size: 12.5,
                            color: _aviso == null
                                ? AppColors.textMuted
                                : AppColors.danger,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Mensaje legible cuando la cámara no arranca. El caso importante es
  /// `permissionDenied`: sin `CAMERA` en el manifiesto, Android ni siquiera
  /// muestra el diálogo y el usuario solo ve una pantalla negra.
  Widget _buildErrorCamara(MobileScannerException error) {
    final String texto;
    var permiso = false;
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        permiso = true;
        texto = 'No diste permiso para usar la cámara. Actívalo en los ajustes '
            'del teléfono y vuelve a intentarlo.';
      case MobileScannerErrorCode.unsupported:
        texto = 'Este dispositivo no tiene una cámara compatible con el '
            'escáner. Escribe el código a mano.';
      default:
        texto = 'No se pudo abrir la cámara. Escribe el código a mano.';
    }

    return Container(
      color: AppColors.ink,
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_rounded,
              color: AppColors.primary,
              size: 52,
            ),
            const SizedBox(height: 16),
            Text(
              texto,
              textAlign: TextAlign.center,
              style: busText(
                size: 14,
                color: Colors.white,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            BusPrimaryButton(
              label: 'Escribir el código',
              icon: Icons.keyboard_rounded,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            // Reintentar aquí no sirve si el permiso quedó denegado para
            // siempre: Android ya no muestra el diálogo y `start()` vuelve a
            // fallar. La vía es la pantalla de ajustes de la app.
            if (permiso) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(44),
                ),
                onPressed: () => openAppSettings(),
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: const Text('Abrir ajustes de la app'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Esquinas amarillas que delimitan la zona de escaneo. Puramente visual.
class _MarcoDeEscaneo extends StatelessWidget {
  const _MarcoDeEscaneo();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.primary, width: 4),
            borderRadius: BorderRadius.circular(28),
          ),
        ),
      ),
    );
  }
}
