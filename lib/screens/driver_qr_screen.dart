import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../main.dart' show AppColors;
import '../models/hijo.dart';
import '../services/hijos_service.dart';
import '../widgets/bus_ui.dart';

/// Panel del conductor para compartir el código con el que los padres vinculan
/// a sus hijos a este bus.
///
/// El código vive en `codigos/{codigo}` y se puede regenerar: el anterior queda
/// `activo: false`, así que un padre con el código viejo recibe "no existe o ya
/// fue desactivado" en vez de quedar vinculado en silencio a un bus que ya no
/// es. El QR solo lleva el código pelado; la app del padre lo normaliza.
class DriverQrScreen extends StatefulWidget {
  const DriverQrScreen({
    super.key,
    required this.placa,
    required this.conductor,
  });

  final String placa;
  final String conductor;

  @override
  State<DriverQrScreen> createState() => _DriverQrScreenState();
}

class _DriverQrScreenState extends State<DriverQrScreen> {
  CodigoBus? _codigo;
  String? _error;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _cargando = false;
        _error = 'Tu sesión venció. Vuelve a iniciar sesión.';
      });
      return;
    }
    if (widget.placa.trim().isEmpty) {
      setState(() {
        _cargando = false;
        _error = 'Tu perfil no tiene una placa asignada. Contacta al '
            'administrador.';
      });
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final CodigoBus codigo = await HijosService.asegurarCodigoConductor(
        driverUid: user.uid,
        placa: widget.placa,
        conductor: widget.conductor,
      );
      if (!mounted) return;
      setState(() {
        _codigo = codigo;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = _mensajeAlFallar(e);
      });
    }
  }

  Future<void> _regenerar() async {
    final CodigoBus? actual = _codigo;
    if (actual == null) return;

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('¿Cambiar el código?'),
        content: Text(
          'El código ${actual.codigo} dejará de funcionar. Los padres que ya '
          'vincularon a su hijo siguen vinculados; solo cambia el código para '
          'los nuevos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogo).pop(true),
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _cargando = true);
    try {
      final CodigoBus nuevo = await HijosService.regenerarCodigoConductor(
        driverUid: user.uid,
        placa: widget.placa,
        conductor: widget.conductor,
      );
      if (!mounted) return;
      setState(() {
        _codigo = nuevo;
        _cargando = false;
      });
      _avisar('Código actualizado.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _avisar(_mensajeAlFallar(e), esError: true);
    }
  }

  Future<void> _copiar({bool mensajeCompleto = false}) async {
    final CodigoBus? codigo = _codigo;
    if (codigo == null) return;
    final String texto = mensajeCompleto
        ? 'BusTrack · Bus ${codigo.busPlate}\n'
            'Código para vincular a tu hijo: ${codigo.codigo}'
            '${codigo.driverName == null ? '' : '\nConductor: ${codigo.driverName}'}'
        : codigo.codigo;
    await Clipboard.setData(ClipboardData(text: texto));
    if (mounted) {
      _avisar(
        mensajeCompleto
            ? 'Mensaje copiado. Pégalo en WhatsApp.'
            : 'Código copiado.',
      );
    }
  }

  void _avisar(String texto, {bool esError = false}) {
    if (!mounted) return;
    final ScaffoldMessengerState avisos = ScaffoldMessenger.of(context);
    avisos.clearSnackBars();
    avisos.showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: esError ? AppColors.danger : AppColors.success,
      ),
    );
  }

  String _mensajeAlFallar(Object e) {
    final String texto = e.toString();
    if (texto.contains('permission-denied')) {
      return 'La base de datos no permitió crear el código. Faltan desplegar '
          'las reglas de seguridad actualizadas.';
    }
    return 'No se pudo preparar el código. Revisa tu conexión e inténtalo otra '
        'vez.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const BusPageHeader(
              title: 'Código del bus',
              subtitle: 'Compártelo con los padres de tus estudiantes',
              trailing: BusIconBadge(
                icon: Icons.qr_code_2_rounded,
                size: 46,
                color: Colors.white,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: _buildCuerpo(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCuerpo() {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.only(top: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final String? error = _error;
    if (error != null) {
      return BusCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BusInfoBox(
              icon: Icons.error_outline_rounded,
              iconColor: AppColors.danger,
              child: Text(
                error,
                style: busText(size: 13, height: 1.35),
              ),
            ),
            const SizedBox(height: 16),
            BusPrimaryButton(
              label: 'Reintentar',
              icon: Icons.refresh_rounded,
              onPressed: _cargar,
            ),
          ],
        ),
      );
    }

    final CodigoBus codigo = _codigo!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BusCard(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.border, width: 2),
                ),
                child: QrImageView(
                  data: codigo.codigo,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: AppColors.ink,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Código del bus',
                style: busText(size: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 6),
              SelectableText(
                codigo.codigo,
                textAlign: TextAlign.center,
                style: busText(
                  size: 34,
                  weight: FontWeight.w800,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Bus ${codigo.busPlate}'
                '${codigo.driverName == null ? '' : ' · ${codigo.driverName}'}',
                textAlign: TextAlign.center,
                style: busText(
                  size: 13,
                  color: AppColors.textMuted,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        BusInfoBox(
          icon: Icons.info_outline_rounded,
          iconColor: AppColors.textMuted,
          child: Text(
            'El padre escanea este QR desde "Mis Hijos → Agregar hijo" o '
            'escribe el código. Cada hijo puede tener su propio bus.',
            style: busText(
              size: 12.5,
              color: AppColors.textMuted,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 16),
        BusPrimaryButton(
          label: 'Copiar código',
          icon: Icons.copy_rounded,
          onPressed: _copiar,
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.ink,
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: () => _copiar(mensajeCompleto: true),
          icon: const Icon(Icons.share_rounded, size: 18),
          label: const Text('Copiar mensaje para WhatsApp'),
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.danger,
            minimumSize: const Size.fromHeight(44),
          ),
          onPressed: _regenerar,
          icon: const Icon(Icons.autorenew_rounded, size: 18),
          label: const Text('Cambiar el código'),
        ),
      ],
    );
  }
}
