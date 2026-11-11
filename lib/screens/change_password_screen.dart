import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart' show AppColors;
import '../widgets/bus_ui.dart';

/// Cambio de contraseña dentro de la app para cuentas de correo/contraseña.
///
/// Firebase exige una autenticación reciente para `updatePassword`, así que
/// primero se reautentica con la contraseña actual (`reauthenticateWithCredential`)
/// y recién entonces se cambia. Un usuario que entró con Google no tiene
/// contraseña: en ese caso se avisa en vez de mostrar el formulario, porque
/// `updatePassword` fallaría con `requires-recent-login` sin explicación.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final TextEditingController _actual = TextEditingController();
  final TextEditingController _nueva = TextEditingController();
  final TextEditingController _confirmar = TextEditingController();

  bool _isLoading = false;
  bool _verActual = false;
  bool _verNueva = false;

  @override
  void dispose() {
    _actual.dispose();
    _nueva.dispose();
    _confirmar.dispose();
    super.dispose();
  }

  /// ¿La cuenta tiene proveedor de correo/contraseña? Una cuenta de Google no.
  bool get _tieneContrasena {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    return user.providerData.any((p) => p.providerId == 'password');
  }

  Future<void> _cambiar() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      _avisar('Tu sesión venció. Vuelve a iniciar sesión.', esError: true);
      return;
    }

    if (_actual.text.isEmpty || _nueva.text.isEmpty || _confirmar.text.isEmpty) {
      _avisar('Completa los tres campos.', esError: true);
      return;
    }
    if (_nueva.text.length < 6) {
      _avisar('La nueva contraseña debe tener al menos 6 caracteres.', esError: true);
      return;
    }
    if (_nueva.text != _confirmar.text) {
      _avisar('La nueva contraseña y su confirmación no coinciden.', esError: true);
      return;
    }

    setState(() => _isLoading = true);
    final NavigatorState nav = Navigator.of(context);

    try {
      final AuthCredential credencial = EmailAuthProvider.credential(
        email: user.email!,
        password: _actual.text,
      );
      await user.reauthenticateWithCredential(credencial);
      await user.updatePassword(_nueva.text);

      if (!mounted) return;
      _avisar('Contraseña actualizada.', esError: false);
      nav.pop();
    } on FirebaseAuthException catch (e) {
      if (mounted) _avisar(_mensaje(e.code), esError: true);
    } catch (_) {
      if (mounted) {
        _avisar('No se pudo cambiar la contraseña.', esError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _mensaje(String code) {
    switch (code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'La contraseña actual no es correcta.';
      case 'weak-password':
        return 'La nueva contraseña es demasiado débil.';
      case 'requires-recent-login':
        return 'Por seguridad, vuelve a iniciar sesión y prueba otra vez.';
      case 'too-many-requests':
        return 'Demasiados intentos. Espera un momento e inténtalo de nuevo.';
      case 'network-request-failed':
        return 'Sin conexión. Revisa tu internet.';
      default:
        return 'No se pudo cambiar la contraseña ($code).';
    }
  }

  void _avisar(String texto, {required bool esError}) {
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

  @override
  Widget build(BuildContext context) {
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
                          if (!_tieneContrasena)
                            _buildAvisoGoogle()
                          else
                            _buildTarjetaFormulario(),
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
      title: 'Cambiar contraseña',
      subtitle: 'Actualiza la clave con la que entras a BusTrack',
      titleSize: 21,
      fullBleed: true,
      leading: BusIconButton(
        icon: Icons.arrow_back_rounded,
        tooltip: 'Volver',
        onTap: () => Navigator.of(context).maybePop(),
      ),
      trailing: const BusIconBadge(
        icon: Icons.lock_reset_rounded,
        size: 46,
        color: Colors.white,
      ),
    );
  }

  Widget _buildAvisoGoogle() {
    return BusCard(
      padding: const EdgeInsets.all(18),
      child: BusInfoBox(
        icon: Icons.info_outline_rounded,
        iconColor: AppColors.ink,
        background: AppColors.primaryPale,
        child: Text(
          'Tu cuenta entra con Google, así que no tiene una contraseña de '
          'BusTrack. Si quieres cambiarla, hazlo desde tu cuenta de Google.',
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: AppColors.textStrong,
            height: 1.35,
          ),
        ),
      ),
    );
  }

  Widget _buildTarjetaFormulario() {
    return BusCard(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCampo(
            controller: _actual,
            label: 'Contraseña actual',
            icon: Icons.lock_outline,
            obscure: !_verActual,
            onToggleVer: () => setState(() => _verActual = !_verActual),
          ),
          const SizedBox(height: 12),
          _buildCampo(
            controller: _nueva,
            label: 'Nueva contraseña (mínimo 6 caracteres)',
            icon: Icons.lock_reset,
            obscure: !_verNueva,
            onToggleVer: () => setState(() => _verNueva = !_verNueva),
          ),
          const SizedBox(height: 12),
          _buildCampo(
            controller: _confirmar,
            label: 'Confirmar nueva contraseña',
            icon: Icons.lock_reset,
            obscure: !_verNueva,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _isLoading ? null : _cambiar(),
          ),
          const SizedBox(height: 20),
          _buildBoton(),
        ],
      ),
    );
  }

  Widget _buildCampo({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    VoidCallback? onToggleVer,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    return BusInputBox(
      controller: controller,
      label: label,
      icon: icon,
      obscureText: obscure,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      trailing: onToggleVer == null
          ? null
          : IconButton(
              tooltip: obscure ? 'Mostrar' : 'Ocultar',
              onPressed: onToggleVer,
              icon: Icon(
                obscure ? Icons.visibility_off : Icons.visibility,
                color: AppColors.textMuted,
                size: 20,
              ),
            ),
    );
  }

  Widget _buildBoton() {
    return BusPrimaryButton(
      label: 'Cambiar contraseña',
      icon: Icons.lock_reset_rounded,
      loading: _isLoading,
      onPressed: _cambiar,
    );
  }
}
