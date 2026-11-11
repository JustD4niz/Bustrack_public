import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

/// Error de Google ya traducido a algo que el usuario pueda entender.
///
/// El código crudo (`sign_in_failed`, `PlatformException(...)`) no le sirve a
/// nadie en un SnackBar. [GoogleAuthError] lleva el mensaje y, cuando el
/// problema se puede arreglar desde la consola de Firebase, lo dice.
class GoogleAuthError implements Exception {
  const GoogleAuthError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Inicia sesión / registro con Google en **cualquier** plataforma.
///
/// ## Por qué hace falta esto
///
/// `FirebaseAuth.signInWithPopup` es **solo web**: en Android, iOS y desktop el
/// canal de métodos lanza `UnimplementedError`, y el botón "Continuar con
/// Google" le mostraba ese error al usuario sin más.
///
/// Ni siquiera sirve cambiarlo por `signInWithRedirect`: ese también está
/// implementado únicamente en `firebase_auth_web`
/// (`firebase_auth_platform_interface`, `method_channel_firebase_auth.dart:417`
/// lanza literalmente *"signInWithRedirect() is only supported on web based
/// platforms"*) y en móvil da el mismo error que el popup.
///
/// ## Cómo funciona
///
/// 1. **Web**: `signInWithPopup` con `GoogleAuthProvider`. Firebase trae el
///    cliente OAuth de la configuración del proyecto, no hace falta pasar nada
///    desde Dart.
/// 2. **Móvil/desktop**: `google_sign_in` 7.x, cuyo `authenticate()` en Android
///    abre una **Chrome Custom Tab** (CredentialManager) y en iOS un
///    `ASWebAuthenticationSession`: se abre el navegador, se elige la cuenta
///    ahí y la app recibe el `idToken` al volver. Ese token se canjea en
///    Firebase con `GoogleAuthProvider.credential(idToken: ...)`.
///
/// Lo que devuelve es el mismo [User] de `FirebaseAuth` en los dos casos, así
/// que quien llama no sabe en qué plataforma está.
class GoogleAuth {
  const GoogleAuth._();

  /// `serverClientId` es el **Web OAuth client id** de tu proyecto de Firebase.
  ///
  /// Es un dato distinto del `clientId` de Android que trae
  /// `google-services.json`: el `idToken` que se pide debe tener como audiencia
  /// el cliente web del proyecto. Ese mismo cliente está declarado en
  /// `web/index.html`.
  ///
  /// En el repositorio público el valor es un marcador. Pásalo al compilar sin
  /// tocar el código:
  ///
  /// ```bash
  /// flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=<tu-client-id>.apps.googleusercontent.com
  /// ```
  ///
  /// Pasa además el `client_id` tipo 3 que ya viene en
  /// `android/app/google-services.json`, así que la app funciona aunque
  /// `google-services.json` se vuelva a descargar. Ver la nota de integración
  /// de `google_sign_in_android`: con el archivo presente no hace falta pasar
  /// nada desde Dart, y si se pasa, este valor manda.
  static const String _serverClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: 'TU_CLIENT_ID_WEB.apps.googleusercontent.com',
  );

  /// `initialize()` se memoiza porque el paquete lo pide exactamente una vez
  /// por proceso, y el login puede venir del botón de entrada, del registro o
  /// de un reintento.
  static Future<void>? _inicializacion;

  static Future<void> _asegurarInicializado() {
    return _inicializacion ??= GoogleSignIn.instance.initialize(
      serverClientId: _serverClientId,
    );
  }

  /// Devuelve el usuario de Firebase, o lanza [GoogleAuthError].
  ///
  /// Si el usuario cierra la pestaña de Google, [GoogleAuthError] con un
  /// mensaje neutro: no es un fallo y no debe scarear en rojo.
  static Future<User> iniciarSesion() async {
    if (kIsWeb) return _enWeb();
    return _enNativo();
  }

  /// Cierra la sesión de Google. En web no hace nada: la sesión de Google la
  /// maneja el navegador y `signOut()` de Firebase alcanza.
  static Future<void> cerrarSesion() async {
    if (kIsWeb) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Si Google falla al cerrar sesión no vale la pena bloquear el cierre de
      // sesión de Firebase, que es el que importa.
    }
  }

  static Future<User> _enNativo() async {
    final GoogleSignIn cliente = GoogleSignIn.instance;

    // Solo web no lo soporta: ahí el SDK de Google no acepta UI propia, obliga
    // a usar su botón. Se comprueba antes de inicializar para no dejar el
    // paquete a medio instanciar en una plataforma que no va a usar.
    if (!cliente.supportsAuthenticate()) {
      throw const GoogleAuthError(
        'Este dispositivo no puede abrir el inicio de sesión de Google. '
        'Entra con tu correo y contraseña.',
      );
    }

    await _asegurarInicializado();

    final GoogleSignInAccount cuenta;
    try {
      cuenta = await cliente.authenticate();
    } on GoogleSignInException catch (e) {
      throw GoogleAuthError(_mensajeDeNativo(e));
    }

    final String? idToken = cuenta.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const GoogleAuthError(
        'Google no devolvió un token de sesión. Revisa que el proveedor '
        'Google esté habilitado en Firebase → Authentication.',
      );
    }

    try {
      final UserCredential credencial = await FirebaseAuth.instance
          .signInWithCredential(
            GoogleAuthProvider.credential(idToken: idToken),
          );
      final User? user = credencial.user;
      if (user == null) {
        throw const GoogleAuthError('Google no devolvió tu cuenta.');
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw GoogleAuthError(_mensajeDeFirebase(e.code));
    } on FirebaseException catch (e) {
      throw GoogleAuthError('Firebase no está disponible: ${e.code}');
    }
  }

  static Future<User> _enWeb() async {
    try {
      final GoogleAuthProvider provider = GoogleAuthProvider()
        ..addScope('email')
        ..addScope('profile');

      final UserCredential credencial = await FirebaseAuth.instance
          .signInWithPopup(provider);
      final User? user = credencial.user;
      if (user == null) {
        throw const GoogleAuthError('Google no devolvió tu cuenta.');
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw GoogleAuthError(_mensajeDeFirebase(e.code));
    } on FirebaseException catch (e) {
      throw GoogleAuthError('Firebase no está disponible: ${e.code}');
    } on GoogleAuthError {
      rethrow;
    } catch (e) {
      // En web `signInWithPopup` falla rápido si el navegador bloquea la
      // ventana emergente.
      throw GoogleAuthError(_mensajeDeNativoPopup(e));
    }
  }

  /// Traduce los códigos de Firebase Auth. Casi todos son de configuración, no
  /// de usuario, y la mitad solo se arregla desde la consola de Firebase.
  static String _mensajeDeFirebase(String code) {
    switch (code) {
      case 'operation-not-allowed':
      case 'provider-not-enabled':
        return 'Google no está habilitado en este proyecto de Firebase. '
            'Actívalo en Firebase → Authentication → Sign-in method → Google.';
      case 'invalid-credential':
      case 'account-exists-with-different-credential':
        return 'Esta cuenta de Google ya está vinculada a otro usuario de '
            'BusTrack.';
      case 'network-request-failed':
        return 'Sin conexión a internet. Revisa tu red e inténtalo de nuevo.';
      case 'web-domain-not-authorized':
        return 'Este dominio no está autorizado en Firebase. Agrega '
            'localhost:1309 en Authentication → Settings → Authorized domains.';
      default:
        return 'No pudimos conectarte con Google ($code).';
    }
  }

  /// Traduce los códigos de `google_sign_in` 7.x, que son un enum y no un
  /// `PlatformException` con todo el texto metido en el `toString()`.
  ///
  /// Casi todos son de configuración y **ningún cambio de código los arregla**:
  /// se resuelven en la consola de Firebase o en la de Google Cloud.
  static String _mensajeDeNativo(GoogleSignInException e) {
    switch (e.code) {
      case GoogleSignInExceptionCode.clientConfigurationError:
        return 'La app no está autorizada ante Google. Hay que registrar su '
            'huella de firma (SHA-1) en Firebase → Project settings → Your '
            'apps → com.practica.bus_track.';
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Google no está habilitado en este proyecto de Firebase. '
            'Actívalo en Firebase → Authentication → Sign-in method → Google.';
      // Ojo: `canceled` **también** aparece cuando el usuario sí eligió una
      // cuenta pero la configuración está mal. Es documentado: el
      // CredentialManager de Android devuelve "canceled" ante un SHA que no
      // cuadra, y el plugin no puede distinguirlo de un cierre real. Por eso
      // el mensaje no dice solo "cerraste".
      case GoogleSignInExceptionCode.canceled:
        return 'No pudimos iniciar sesión con Google. Si elegiste una cuenta y '
            'vuelve a pasar esto, revisa que la huella SHA-1 de la app esté '
            'registrada en Firebase.';
      case GoogleSignInExceptionCode.uiUnavailable:
        return 'No pudimos abrir la pantalla de Google. Reintentá en un '
            'instante.';
      case GoogleSignInExceptionCode.interrupted:
        return 'El inicio de sesión con Google se interrumpió. Inténtalo otra '
            'vez.';
      case GoogleSignInExceptionCode.userMismatch:
        return 'Ya hay otra cuenta de Google conectada en este dispositivo. '
            'Cerrá sesión en Google y volvé a intentarlo.';
      case GoogleSignInExceptionCode.unknownError:
        return 'No pudimos conectarte con Google. Revisa tu conexión e '
            'inténtalo otra vez.';
    }
  }

  /// La ruta de web no usa `google_sign_in`, así que sus errores llegan como
  /// excepción de Firebase o como `Exception` suelta cuando el navegador
  /// bloquea la ventana emergente.
  static String _mensajeDeNativoPopup(Object e) {
    return 'No pudimos abrir la ventana de Google. Revisa que no esté '
        'bloqueando las ventanas emergentes e inténtalo otra vez.';
  }
}
