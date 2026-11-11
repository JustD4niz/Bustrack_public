import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../register_screen.dart';
import '../services/google_auth.dart';
import '../services/session_prefs.dart';
import '../services/session_router.dart';
import '../widgets/bus_ui.dart';
import '../widgets/gradient_field.dart';
import '../widgets/google_button.dart';

class PantallaLoginPaisaje extends StatefulWidget {
  const PantallaLoginPaisaje({super.key});

  @override
  State<PantallaLoginPaisaje> createState() => _PantallaLoginPaisajeState();
}

class _PantallaLoginPaisajeState extends State<PantallaLoginPaisaje> {
  String _email = '';
  String _password = '';
  bool _isLoading = false;

  /// Marcada por defecto, igual que `PreferenciasDeSesion.recordarme()` cuando
  /// todavía no hay nada guardado. `initState` la sincroniza con lo que el
  /// usuario eligió la última vez.
  bool _recordarme = true;

  @override
  void initState() {
    super.initState();
    _cargarRecordarme();
  }

  Future<void> _cargarRecordarme() async {
    final bool valor = await PreferenciasDeSesion.recordarme();
    if (mounted) setState(() => _recordarme = valor);
  }

  /// Guarda la elección **antes** de iniciar sesión. En Android no se puede
  /// desactivar la persistencia de Firebase, así que la casilla se aplica al
  /// siguiente arranque (ver `session_prefs.dart`).
  Future<void> _guardarRecordarme() async {
    await PreferenciasDeSesion.guardarRecordarme(_recordarme);
  }

  Future<void> _handleLogin() async {
    // `trim()` y no `isEmpty`: un campo con solo espacios pasa la validación y
    // luego Firebase responde con un error de formato que el usuario no entiende
    // ("El formato del correo no es válido").
    if (_email.trim().isEmpty || _password.isEmpty) {
      _mostrarAviso('Por favor completa todos los campos.', esError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _guardarRecordarme();
      // Intento de inicio de sesión con Firebase
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: _email.trim(),
            password: _password,
          );

      final User? user = userCredential.user;
      if (user != null && mounted) await _enrutar(user);
    } on FirebaseAuthException catch (e) {
      _mostrarAviso(_mensajeDeErrorDeAuth(e.code), esError: true);
    } on FirebaseException {
      _mostrarAviso(
        'Firebase no está disponible. Revisa tu conexión e inténtalo otra vez.',
        esError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Entra con Google. Necesario porque una cuenta creada con Google no tiene
  /// contraseña: sin este botón, ese usuario quedaba con una cuenta en Firebase
  /// que no podía volver a abrir.
  Future<void> _iniciarSesionConGoogle() async {
    setState(() => _isLoading = true);

    try {
      await _guardarRecordarme();
      final User user = await GoogleAuth.iniciarSesion();
      if (mounted) await _enrutar(user);
    } on GoogleAuthError catch (e) {
      _mostrarAviso(e.message, esError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Envía el correo de recuperación de contraseña de Firebase al email escrito.
  Future<void> _recuperarContrasena() async {
    final String correo = _email.trim();
    if (correo.isEmpty) {
      _mostrarAviso(
        'Escribe tu correo arriba y vuelve a tocar el enlace.',
        esError: true,
      );
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: correo);
      _mostrarAviso('Te enviamos un enlace a $correo.', esError: false);
    } on FirebaseAuthException catch (e) {
      _mostrarAviso(_mensajeDeErrorDeAuth(e.code), esError: true);
    } on FirebaseException {
      _mostrarAviso(
        'No pudimos enviar el correo. Revisa tu conexión.',
        esError: true,
      );
    }
  }

  /// Decide a qué pantalla va [user] y navega.
  ///
  /// Un usuario **sin** `usuarios/{uid}` se manda a la selección de rol en vez
  /// de quedarse quieto en el login, que era lo que pasaba con quien abría la
  /// app, elegía Google y cerraba antes de completar el formulario. Aquí se
  /// usa `push` y no `pushReplacement` para que login quede debajo y el botón
  /// de atrás tenga a dónde volver.
  ///
  /// La decisión de a dónde ir vive en `resolverDestinoDeSesion` para que la
  /// comparta con el arranque de la app con sesión guardada.
  Future<void> _enrutar(User user) async {
    final DestinoDeSesion destino = await resolverDestinoDeSesion(user);
    if (!mounted) return;

    final MaterialPageRoute<void> ruta = MaterialPageRoute<void>(
      builder: (context) => destino.pantalla,
    );
    if (destino.dejarLoginDebajo) {
      Navigator.push(context, ruta);
    } else {
      Navigator.pushReplacement(context, ruta);
    }
  }

  /// Traduce los códigos de Firebase Auth a algo accionable en vez del
  /// "Verifique sus credenciales" genérico, que no servía ni para una
  /// contraseña mal escrita ni para una cuenta que existe con otro método.
  String _mensajeDeErrorDeAuth(String code) {
    switch (code) {
      case 'invalid-email':
        return 'El formato del correo no es válido.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Correo o contraseña incorrectos.';
      case 'user-disabled':
        return 'Esta cuenta fue deshabilitada. Contacta al administrador.';
      case 'too-many-requests':
        return 'Demasiados intentos. Espera un momento e inténtalo de nuevo.';
      case 'network-request-failed':
        return 'Sin conexión a internet. Revisa tu red e inténtalo de nuevo.';
      default:
        return 'No pudimos iniciar sesión ($code).';
    }
  }

  /// Quita los avisos anteriores antes de mostrar el nuevo: sin esto el error
  /// de Google se quedaba arriba mientras el usuario reintentaba con correo y
  /// parecía que el correo fallaba con el mensaje equivocado.
  void _mostrarAviso(String mensaje, {required bool esError}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
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
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BusHeader(
                    title: 'Bienvenido',
                    subtitle: 'Inicia sesión para continuar',
                    titleSize: 28,
                    // La flecha solo se dibuja si de verdad hay una pantalla
                    // debajo. Al arrancar y al cerrar sesión el login es la ruta
                    // raíz (`pushAndRemoveUntil`), así que `maybePop()` no
                    // hacía nada y quedaba una flecha muerta. Sí hay debajo
                    // cuando se llega desde la bienvenida (`SplashScreen`).
                    leading: Navigator.of(context).canPop()
                        ? BusIconButton(
                            icon: Icons.arrow_back_rounded,
                            tooltip: 'Volver',
                            onTap: () => Navigator.maybePop(context),
                          )
                        : null,
                    trailing: BusIconBadge(
                      icon: Icons.family_restroom_rounded,
                      size: 54,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildTarjetaCredenciales(),
                  const SizedBox(height: 16),
                  GoogleButton(
                    texto: 'Ingresar con Google',
                    cargando: _isLoading,
                    onPressed: _iniciarSesionConGoogle,
                  ),
                  const SizedBox(height: 20),
                  _buildEnlaceRegistro(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Tarjeta blanca con el formulario real de correo y contraseña.
  Widget _buildTarjetaCredenciales() {
    return BusCard(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const BusIconBadge(
                icon: Icons.lock_outline_rounded,
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
            autofillHints: const [AutofillHints.password],
            onChanged: (v) => _password = v,
            onSubmitted: (_) => _isLoading ? null : _handleLogin(),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _recordarme,
                    onChanged: (v) =>
                        setState(() => _recordarme = v ?? false),
                    activeColor: AppColors.ink,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  Text(
                    'Recordarme',
                    style: busText(
                      size: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: _recuperarContrasena,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '¿Olvidaste tu contraseña?',
                    style: busText(
                      size: 13,
                      weight: FontWeight.w600,
                      color: AppColors.textStrong,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildBotonIngresar(),
        ],
      ),
    );
  }

  Widget _buildBotonIngresar() {
    return BusPrimaryButton(
      label: 'Iniciar sesión',
      icon: Icons.login_rounded,
      loading: _isLoading,
      onPressed: _handleLogin,
    );
  }

  Widget _buildEnlaceRegistro() {
    return FittedBox(
      // `scaleDown`: con la fuente del sistema agrandada la fila se salía del
      // ancho disponible.
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '¿No tienes una cuenta? ',
            style: busText(
              size: 14,
              color: AppColors.textMuted,
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RegisterScreen()),
              );
            },
            child: Text(
              'Regístrate',
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
