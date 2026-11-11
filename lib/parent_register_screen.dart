import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'main.dart';
import 'models/hijo.dart';
import 'parent_home_screen.dart';
import 'screens/scan_qr_screen.dart';
import 'services/hijos_service.dart';
import 'widgets/bus_ui.dart';

/// Registro del padre: crea su ficha (`usuarios/{uid}`) y su primer hijo
/// (`estudiantes/{id}`).
///
/// Antes este formulario pedía la **placa** y el nombre del conductor, datos que
/// el padre no tiene por qué saber y que, escritos a mano, vinculaban el hijo al
/// bus equivocado sin avisar. Ahora pide el **código del conductor** (o el QR) y
/// es opcional: si no lo tiene a mano, el hijo queda registrado sin bus y se
/// puede vincular después desde "Mis Hijos".
class ParentRegisterScreen extends StatefulWidget {
  const ParentRegisterScreen({super.key});

  @override
  State<ParentRegisterScreen> createState() => _ParentRegisterScreenState();
}

class _ParentRegisterScreenState extends State<ParentRegisterScreen> {
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _childNameController = TextEditingController();
  final TextEditingController _childAgeController = TextEditingController();
  final TextEditingController _schoolNameController = TextEditingController();
  final TextEditingController _codigoController = TextEditingController();

  bool _isLoading = false;
  bool _verificando = false;

  /// Código ya resuelto contra Firestore. Se conserva para no volver a leerlo
  /// al guardar.
  CodigoBus? _vinculacion;

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _childNameController.dispose();
    _childAgeController.dispose();
    _schoolNameController.dispose();
    _codigoController.dispose();
    super.dispose();
  }

  Future<void> _escanearCodigo() async {
    final String? codigo = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const ScanQrScreen()),
    );
    if (codigo == null || !mounted) return;
    _codigoController.text = codigo;
    await _verificarCodigo(codigo, avisarExito: true);
  }

  Future<bool> _verificarCodigo(
    String texto, {
    bool avisarExito = false,
  }) async {
    final String normalizado = HijosService.normalizarCodigo(texto);
    if (normalizado.isEmpty) {
      // Sin código no es un error: el hijo se registra sin bus.
      setState(() => _vinculacion = null);
      return true;
    }
    if (!HijosService.esCodigoValido(normalizado)) {
      _avisar('El código del bus no es válido.', esError: true);
      return false;
    }

    setState(() => _verificando = true);
    try {
      final CodigoBus? encontrado =
          await HijosService.resolverCodigo(normalizado);
      if (!mounted) return false;
      if (encontrado == null) {
        setState(() => _vinculacion = null);
        _avisar(
          'Ese código no existe o el conductor lo cambió. Revísalo o deja el '
          'campo vacío para vincularlo después.',
          esError: true,
        );
        return false;
      }
      setState(() {
        _vinculacion = encontrado;
        _codigoController.text = encontrado.codigo;
      });
      if (avisarExito) {
        _avisar(
          'Código verificado: bus ${encontrado.busPlate}.',
        );
      }
      return true;
    } catch (_) {
      if (mounted) {
        _avisar('No se pudo verificar el código. Revisa tu conexión.',
            esError: true);
      }
      return false;
    } finally {
      if (mounted) setState(() => _verificando = false);
    }
  }

  Future<void> _guardarDatosPadre() async {
    final String nombrePadre = _fullNameController.text.trim();
    final String telefono = _phoneController.text.trim();
    final String nombreHijo = _childNameController.text.trim();

    if (nombrePadre.isEmpty || telefono.isEmpty || nombreHijo.isEmpty) {
      _avisar('Completa tu nombre, tu teléfono y el nombre del estudiante.',
          esError: true);
      return;
    }

    final String edadTexto = _childAgeController.text.trim();
    int? edad;
    if (edadTexto.isNotEmpty) {
      edad = int.tryParse(edadTexto);
      if (edad == null || edad < 3 || edad > 25) {
        _avisar('Ingresa una edad válida entre 3 y 25 años.', esError: true);
        return;
      }
    }

    // Se resuelve el código antes de escribir nada: si el padre se equivocó,
    // no queda una ficha de padre a medias obligándolo a empezar de nuevo.
    final String codigoTexto = HijosService.normalizarCodigo(_codigoController.text);
    if (codigoTexto.isNotEmpty && _vinculacion?.codigo != codigoTexto) {
      final bool valido = await _verificarCodigo(codigoTexto);
      if (!valido || !mounted) return;
    }
    // Si el campo quedó vacío pero había un código verificado de antes (el
    // padre lo borró), el hijo se registra sin bus.
    final CodigoBus? vinculacion =
        codigoTexto.isEmpty ? null : _vinculacion;

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _avisar('Tu sesión venció. Vuelve a iniciar sesión.', esError: true);
      return;
    }

    setState(() => _isLoading = true);
    final NavigatorState nav = Navigator.of(context);
    try {
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .set(<String, dynamic>{
        'uid': user.uid,
        'email': user.email,
        'fullName': nombrePadre,
        'phone': telefono,
        'role': 'parent',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await HijosService.crearHijo(
        parentUid: user.uid,
        nombre: nombreHijo,
        edad: edad,
        colegio: _schoolNameController.text,
        vinculacion: vinculacion,
      );

      if (!mounted) return;
      _avisar('¡Perfil guardado con éxito!');
      nav.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const ParentHomeScreen()),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _avisar(
        e.code == 'auth/network-request-failed'
            ? 'Sin conexión. Revisa tu internet e inténtalo otra vez.'
            : 'Tu sesión venció. Cierra sesión e ingrésala de nuevo.',
        esError: true,
      );
    } on FirebaseException catch (e) {
      if (mounted) _avisar(_mensajeDeErrorDeFirestore(e), esError: true);
    } catch (_) {
      if (mounted) {
        _avisar('No se pudo guardar tu perfil. Inténtalo otra vez.',
            esError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

  /// Traduce el fallo de Firestore a algo que el padre pueda entender.
  String _mensajeDeErrorDeFirestore(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'No pudimos guardar tu perfil porque las reglas de la base de '
            'datos no lo permiten. Hay que desplegar las reglas actualizadas.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Sin conexión con la base de datos. Revisa tu internet.';
      case 'failed-precondition':
        return 'Firestore respondió con un error de configuración del proyecto.';
      default:
        return 'No se pudo guardar tu perfil (${e.code}).';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Quita el foco al tocar fuera de los campos: en web mantiene el teclado
    // virtual cerrado y evita que la tarjeta quede cubierta.
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildEncabezado(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildBannerInformativo(),
                          const SizedBox(height: 16),
                          _buildTarjetaFormulario(context),
                        ],
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

  Widget _buildEncabezado(BuildContext context) {
    return BusHeader(
      title: 'Registro de Padre',
      subtitle: 'Registra a tu hijo para seguir su ruta escolar',
      titleSize: 21,
      fullBleed: true,
      leading: BusIconButton(
        icon: Icons.arrow_back_rounded,
        tooltip: 'Volver',
        onTap: () => Navigator.of(context).maybePop(),
      ),
      trailing: const BusIconBadge(
        icon: Icons.family_restroom_rounded,
        size: 46,
        color: Colors.white,
      ),
    );
  }

  Widget _buildBannerInformativo() {
    return BusInfoBox(
      icon: Icons.qr_code_2_rounded,
      iconColor: AppColors.ink,
      child: Text(
        'Si el conductor te dio un código o un QR, úsalo al final para '
        'vincular el bus. Si no lo tienes, registra a tu hijo ahora y '
        'vincula después.',
        style: busText(
          size: 12.5,
          color: AppColors.textStrong,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _buildTarjetaFormulario(BuildContext context) {
    return BusCard(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSeccion('1. Tus datos'),
          const SizedBox(height: 12),
          BusInputBox(
            controller: _fullNameController,
            label: 'Nombre completo',
            icon: Icons.person_rounded,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          BusInputBox(
            controller: _phoneController,
            label: 'Número de teléfono',
            icon: Icons.call_rounded,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 22),
          _buildSeccion('2. Datos del estudiante'),
          const SizedBox(height: 12),
          BusInputBox(
            controller: _childNameController,
            label: 'Nombre del estudiante',
            icon: Icons.school_rounded,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          BusInputBox(
            controller: _childAgeController,
            label: 'Edad (opcional)',
            icon: Icons.cake_outlined,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          BusInputBox(
            controller: _schoolNameController,
            label: 'Colegio (opcional)',
            icon: Icons.account_balance_outlined,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 22),
          _buildSeccion('3. Bus escolar (opcional)'),
          const SizedBox(height: 12),
          BusInputBox(
            controller: _codigoController,
            label: 'Código que te dio el conductor',
            icon: Icons.qr_code_rounded,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            onSubmitted: (v) => _verificarCodigo(v, avisarExito: true),
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
            onPressed: _verificando ? null : _escanearCodigo,
            icon: _verificando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.qr_code_scanner_rounded, size: 20),
            label: Text(
              _vinculacion == null
                  ? 'Escanear QR del conductor'
                  : 'Bus ${_vinculacion!.busPlate} verificado',
            ),
          ),
          const SizedBox(height: 20),
          BusPrimaryButton(
            label: 'Guardar y Continuar',
            icon: Icons.check_circle_rounded,
            loading: _isLoading,
            onPressed: _guardarDatosPadre,
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
