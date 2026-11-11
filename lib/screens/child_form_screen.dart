import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../main.dart' show AppColors;
import '../models/hijo.dart';
import '../services/hijos_service.dart';
import '../widgets/bus_ui.dart';
import 'scan_qr_screen.dart';

/// Formulario para agregar o editar un hijo.
///
/// El bus es **opcional**: un padre puede registrar a su hijo y vincularlo
/// después con el código del conductor. Vincular no reemplaza la placa por
/// dentro (`buses/{placa}` sigue existiendo), solo es la forma en que el padre
/// descubre cuál es su bus sin tener que escribirla.
///
/// Devuelve por `Navigator.pop` el id del hijo guardado, o `true` si se borró,
/// para que el panel pueda seleccionarlo o refrescar la selección.
class ChildFormScreen extends StatefulWidget {
  const ChildFormScreen({super.key, this.hijo});

  /// `null` para agregar; un [Hijo] para editar.
  final Hijo? hijo;

  @override
  State<ChildFormScreen> createState() => _ChildFormScreenState();
}

class _ChildFormScreenState extends State<ChildFormScreen> {
  late final TextEditingController _nombre;
  late final TextEditingController _edad;
  late final TextEditingController _colegio;
  late final TextEditingController _codigo;

  /// Vínculo resuelto en esta sesión de edición. Si es `null` se usa el que ya
  /// tenía el hijo.
  CodigoBus? _vinculado;
  bool _quitarVinculo = false;

  bool _isLoading = false;
  bool _verificando = false;

  bool get _esEdicion => widget.hijo != null;

  /// `true` si al guardar el hijo quedará con un bus.
  bool get _tendraBus {
    if (_quitarVinculo) return false;
    return _vinculado != null || (widget.hijo?.tieneBus ?? false);
  }

  String? get _placaMostrada =>
      _vinculado?.busPlate ?? widget.hijo?.busPlate;

  String? get _conductorMostrado =>
      _vinculado?.driverName ?? widget.hijo?.driverName;

  @override
  void initState() {
    super.initState();
    final hijo = widget.hijo;
    _nombre = TextEditingController(text: hijo?.nombre ?? '');
    _edad = TextEditingController(text: hijo?.edad?.toString() ?? '');
    _colegio = TextEditingController(text: hijo?.colegio ?? '');
    _codigo = TextEditingController(text: hijo?.codigo ?? '');
  }

  @override
  void dispose() {
    _nombre.dispose();
    _edad.dispose();
    _colegio.dispose();
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _escanear() async {
    final String? codigo = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const ScanQrScreen(),
      ),
    );
    if (codigo == null || !mounted) return;
    _codigo.text = codigo;
    await _verificarCodigo(codigo);
  }

  /// Resuelve el código contra Firestore y deja la placa lista para guardar.
  Future<void> _verificarCodigo(String texto) async {
    final String normalizado = HijosService.normalizarCodigo(texto);
    if (!HijosService.esCodigoValido(normalizado)) {
      _avisar('Escribe un código válido o escanea el QR del conductor.',
          esError: true);
      return;
    }

    setState(() => _verificando = true);
    try {
      final CodigoBus? encontrado =
          await HijosService.resolverCodigo(normalizado);
      if (!mounted) return;
      if (encontrado == null) {
        setState(() => _vinculado = null);
        _avisar(
          'Ese código no existe o el conductor lo cambió. Pídele el actual.',
          esError: true,
        );
        return;
      }
      setState(() {
        _vinculado = encontrado;
        _quitarVinculo = false;
        _codigo.text = encontrado.codigo;
      });
      _avisar(
        'Código verificado: bus ${encontrado.busPlate}'
        '${encontrado.driverName == null ? '' : ' · ${encontrado.driverName}'}.',
      );
    } catch (_) {
      if (!mounted) return;
      _avisar('No se pudo verificar el código. Revisa tu conexión.',
          esError: true);
    } finally {
      if (mounted) setState(() => _verificando = false);
    }
  }

  Future<void> _guardar() async {
    final String nombre = _nombre.text.trim();
    if (nombre.isEmpty) {
      _avisar('Escribe el nombre del estudiante.', esError: true);
      return;
    }

    final String edadTexto = _edad.text.trim();
    int? edad;
    if (edadTexto.isNotEmpty) {
      edad = int.tryParse(edadTexto);
      if (edad == null || edad < 3 || edad > 25) {
        _avisar('Ingresa una edad válida entre 3 y 25 años.', esError: true);
        return;
      }
    }

    final String codigoTexto = HijosService.normalizarCodigo(_codigo.text);
    final String? codigoActual = widget.hijo?.codigo;
    CodigoBus? vincular;

    // Solo se resuelve si el padre escribió un código distinto al que ya tenía
    // el hijo. Si no lo tocó, el vínculo actual se conserva sin consultar la
    // base (y sin fallar si el conductor regeneró el código).
    if (!_quitarVinculo &&
        codigoTexto.isNotEmpty &&
        codigoTexto != codigoActual) {
      if (!HijosService.esCodigoValido(codigoTexto)) {
        _avisar('El código del bus no es válido.', esError: true);
        return;
      }
      if (_vinculado?.codigo == codigoTexto) {
        vincular = _vinculado;
      } else {
        setState(() => _isLoading = true);
        try {
          vincular = await HijosService.resolverCodigo(codigoTexto);
        } catch (_) {
          if (mounted) setState(() => _isLoading = false);
          _avisar('No se pudo verificar el código. Revisa tu conexión.',
              esError: true);
          return;
        }
        if (vincular == null) {
          if (mounted) setState(() => _isLoading = false);
          _avisar('Ese código no existe o ya fue desactivado.', esError: true);
          return;
        }
        if (mounted) setState(() => _isLoading = false);
      }
    }

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _avisar('Tu sesión venció. Vuelve a iniciar sesión.', esError: true);
      return;
    }

    setState(() => _isLoading = true);
    if (!mounted) return;
    final NavigatorState nav = Navigator.of(context);
    try {
      if (_esEdicion) {
        final Hijo hijo = widget.hijo!;
        await HijosService.actualizarHijo(
          hijo: hijo,
          nombre: nombre,
          edad: edad,
          colegio: _colegio.text,
          vincular: vincular,
          quitarVinculo: _quitarVinculo,
        );
        if (!mounted) return;
        _avisar('Cambios guardados.');
        nav.pop(hijo.id);
      } else {
        final String id = await HijosService.crearHijo(
          parentUid: user.uid,
          nombre: nombre,
          edad: edad,
          colegio: _colegio.text,
          vinculacion: vincular,
        );
        if (!mounted) return;
        _avisar('${nombre.trim()} quedó registrado.');
        nav.pop(id);
      }
    } catch (e) {
      if (mounted) _avisar(_mensajeAlFallar(e), esError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _eliminar() async {
    final Hijo? hijo = widget.hijo;
    if (hijo == null) return;

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: Text('Eliminar a ${hijo.nombre}'),
        content: const Text(
          'Se borrarán sus datos y su punto de recogida. El historial de rutas '
          'ya cerradas no se modifica.',
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
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _isLoading = true);
    if (!mounted) return;
    final NavigatorState nav = Navigator.of(context);
    try {
      await HijosService.eliminarHijo(hijo);
      if (!mounted) return;
      nav.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _avisar(_mensajeAlFallar(e), esError: true);
      }
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
      return 'La base de datos no permitió guardar. Faltan desplegar las '
          'reglas de seguridad actualizadas.';
    }
    return 'No se pudo guardar. Revisa tu conexión e inténtalo otra vez.';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              BusPageHeader(
                title: _esEdicion ? 'Editar hijo' : 'Agregar hijo',
                subtitle: _esEdicion
                    ? 'Actualiza sus datos o su bus'
                    : 'Registra al estudiante que usarás en la app',
                trailing: const BusIconBadge(
                  icon: Icons.family_restroom_rounded,
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
                      child: BusCard(
                        padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSeccion('Datos del estudiante'),
                            const SizedBox(height: 12),
                            BusInputBox(
                              controller: _nombre,
                              label: 'Nombre completo',
                              icon: Icons.person_rounded,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 12),
                            BusInputBox(
                              controller: _edad,
                              label: 'Edad (opcional)',
                              icon: Icons.cake_outlined,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 12),
                            BusInputBox(
                              controller: _colegio,
                              label: 'Colegio (opcional)',
                              icon: Icons.account_balance_outlined,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 22),
                            _buildSeccion('Bus escolar (opcional)'),
                            const SizedBox(height: 10),
                            _buildEstadoVinculo(),
                            const SizedBox(height: 12),
                            BusInputBox(
                              controller: _codigo,
                              label: 'Código del conductor',
                              icon: Icons.qr_code_rounded,
                              textCapitalization: TextCapitalization.characters,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (v) => _verificarCodigo(v),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.ink,
                                      side: const BorderSide(
                                        color: AppColors.border,
                                      ),
                                      minimumSize:
                                          const Size.fromHeight(46),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: _verificando ? null : _escanear,
                                    icon: _verificando
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.qr_code_scanner_rounded,
                                            size: 18,
                                          ),
                                    label: const Text('Escanear QR'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.ink,
                                      side: const BorderSide(
                                        color: AppColors.border,
                                      ),
                                      minimumSize:
                                          const Size.fromHeight(46),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: _verificando
                                        ? null
                                        : () => _verificarCodigo(_codigo.text),
                                    icon: const Icon(
                                      Icons.verified_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('Verificar'),
                                  ),
                                ),
                              ],
                            ),
                            if (_tendraBus) ...[
                              const SizedBox(height: 8),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.danger,
                                  minimumSize: const Size.fromHeight(44),
                                ),
                                onPressed: _isLoading
                                    ? null
                                    : () => setState(() {
                                          _quitarVinculo = true;
                                          _vinculado = null;
                                          _codigo.clear();
                                        }),
                                icon: const Icon(
                                  Icons.link_off_rounded,
                                  size: 18,
                                ),
                                label: const Text('Quitar vínculo con el bus'),
                              ),
                            ],
                            const SizedBox(height: 18),
                            BusPrimaryButton(
                              label: _esEdicion
                                  ? 'Guardar cambios'
                                  : 'Registrar hijo',
                              icon: Icons.check_circle_rounded,
                              loading: _isLoading,
                              onPressed: _guardar,
                            ),
                            if (_esEdicion) ...[
                              const SizedBox(height: 8),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.danger,
                                  minimumSize: const Size.fromHeight(44),
                                ),
                                onPressed: _isLoading ? null : _eliminar,
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                ),
                                label: const Text('Eliminar hijo'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Caja que resume el vínculo actual o el que se acaba de verificar.
  Widget _buildEstadoVinculo() {
    if (!_tendraBus) {
      return BusInfoBox(
        icon: Icons.link_off_rounded,
        iconColor: AppColors.textMuted,
        child: Text(
          'Sin bus vinculado. Puedes registrarlo así y vincularlo después con '
          'el código que te dé el conductor.',
          style: busText(
            size: 12.5,
            color: AppColors.textMuted,
            height: 1.35,
          ),
        ),
      );
    }

    final String placa = _placaMostrada ?? '—';
    final String? conductor = _conductorMostrado;
    return BusInfoBox(
      icon: Icons.directions_bus_filled_rounded,
      iconColor: AppColors.ink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bus $placa',
            style: busText(size: 14, weight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            conductor == null
                ? 'Vinculado con el código del conductor'
                : 'Conductor: $conductor',
            style: busText(
              size: 12,
              color: AppColors.textMuted,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeccion(String texto) {
    return Row(
      children: [
        Container(
          width: 5,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            style: busText(size: 14, weight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
