import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'main.dart';
import 'screens/role_selection_screen.dart';
import 'services/google_auth.dart';
import 'services/session_prefs.dart';
import 'widgets/bus_ui.dart';
import 'widgets/google_button.dart';
import 'widgets/gradient_field.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  String _email = '';
  String _password = '';
  bool _isLoading = false;

  /// Crea la cuenta en Firebase Auth y continúa con la selección de rol.
  Future<void> _registrarUsuario() async {
    // `trim()` en el correo: un campo con solo espacios pasa la validación y
    // Firebase responde con un error de formato que no le dice al usuario qué
    // hizo mal.
    if (_email.trim().isEmpty || _password.isEmpty) {
      _mostrarAviso('Por favor completa todos los campos.', esError: true);
      return;
    }
    if (_password.length < 6) {
      _mostrarAviso(
        'La contraseña debe tener al menos 6 caracteres.',
        esError: true,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.trim(),
        password: _password,
      );
      if (mounted) _irASeleccionDeRol();
    } on FirebaseAuthException catch (e) {
      String mensaje = 'Error al registrarse';
      if (e.code == 'weak-password') {
        mensaje = 'La contraseña es muy débil (mínimo 6 caracteres).';
      } else if (e.code == 'email-already-in-use') {
        mensaje = 'Ya existe una cuenta registrada con este correo.';
      } else if (e.code == 'invalid-email') {
        mensaje = 'El formato del correo electrónico no es válido.';
      } else if (e.code == 'operation-not-allowed') {
        mensaje =
            'El proveedor de autenticación no está habilitado en Firebase.';
      }
      _mostrarAviso(mensaje, esError: true);
    } on FirebaseException catch (e) {
      // Firebase no inicializado o configuración incompleta. Sin este
      // bloque la excepción escapaba y el flujo se quedaba colgado.
      _mostrarAviso(
        'Firebase no está disponible: ${e.message ?? e.code}',
        esError: true,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Inicia sesión con Google y enlaza la cuenta con Firebase Auth.
  ///
  /// Delega en [GoogleAuth], que usa `signInWithPopup` en web y el selector de
  /// cuentas nativo en móvil. Antes este método llamaba a `signInWithPopup`
  /// directo, que en Android lanzaba `UnimplementedError` y le llegaba al
  /// usuario como un error sin explicación.
  Future<void> _registrarConGoogle() async {
    setState(() => _isLoading = true);

    try {
      await GoogleAuth.iniciarSesion();
      if (mounted) _irASeleccionDeRol();
    } on GoogleAuthError catch (e) {
      _mostrarAviso(e.message, esError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _irASeleccionDeRol() async {
    // La cuenta recién creada ya tiene sesión: se anota para que el arranque no
    // la confunda con "aquí nunca se inició sesión".
    await PreferenciasDeSesion.recordarSesion(
      FirebaseAuth.instance.currentUser?.email,
    );
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
    );
  }

  void _mostrarAviso(String mensaje, {required bool esError}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // Un error anterior (p. ej. el de Google) podía quedar en pantalla
    // mientras el usuario registraba con correo, y parecía que el flujo de
    // correo fallaba con el mensaje equivocado.
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError ? AppColors.danger : AppColors.success,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BusHeader(
                    title: 'Crea tu cuenta',
                    subtitle: 'Regístrate para empezar con BusTrack',
                    titleSize: 28,
                    leading: BusIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Volver',
                      onTap: () => Navigator.pop(context),
                    ),
                    trailing: BusIconBadge(
                      icon: Icons.person_add_alt_1_rounded,
                      size: 54,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildTarjetaCampos(),
                  const SizedBox(height: 16),
                  GoogleButton(
                    cargando: _isLoading,
                    onPressed: _registrarConGoogle,
                  ),
                  const SizedBox(height: 20),
                  _buildEnlaceLogin(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Tarjeta blanca con los dos campos y el botón primario.
  Widget _buildTarjetaCampos() {
    return BusCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const BusIconBadge(
                icon: Icons.mail_outline_rounded,
                size: 42,
                color: AppColors.primaryPale,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Datos de acceso',
                  style: busText(size: 17, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          GradientField(
            label: 'Correo Electrónico',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            onChanged: (v) => _email = v,
          ),
          const SizedBox(height: 14),
          GradientField(
            label: 'Contraseña',
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            onChanged: (v) => _password = v,
            onSubmitted: (_) => _isLoading ? null : _registrarUsuario(),
          ),
          const SizedBox(height: 18),
          _buildBoton('Registrarse', _registrarUsuario),
        ],
      ),
    );
  }

  /// Botón primario oscuro de ancho completo. Solo lo usa "Registrarse"; el de
  /// Google vive en [GoogleButton], que es blanco con borde para que no se
  /// confundan.
  Widget _buildBoton(String texto, VoidCallback? onPressed) {
    return BusPrimaryButton(
      label: texto,
      icon: Icons.person_add_alt_1_rounded,
      loading: _isLoading,
      onPressed: onPressed,
    );
  }

  Widget _buildEnlaceLogin() {
    return FittedBox(
      // `scaleDown`: con la fuente del sistema agrandada la fila se salía del
      // ancho disponible.
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '¿Ya tienes una cuenta? ',
            style: busText(
              size: 14,
              color: AppColors.textMuted,
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.maybePop(context),
            child: Text(
              'Inicia sesión',
              style: busText(
                size: 14,
                weight: FontWeight.w700,
                color: AppColors.textStrong,
              ).copyWith(decoration: TextDecoration.underline),
            ),
          ),
        ],
      ),
    );
  }
}
