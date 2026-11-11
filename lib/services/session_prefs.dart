import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'google_auth.dart';

/// Preferencia "Recordarme" del login y memoria de la última sesión abierta.
///
/// ## Por qué hace falta un archivo aparte
///
/// En Android/iOS Firebase Auth **siempre** persiste la sesión: no existe un
/// `setPersistence` nativo (solo web, y en móvil lanza `UnimplementedError`).
/// Es decir, la casilla "Recordarme" no puede decidir si Firebase guarda el
/// token; lo que sí puede es que la app **cierre la sesión al arrancar** cuando
/// el usuario pidió no ser recordado. Eso es lo que hace
/// [aplicarPoliticaDeArranque].
///
/// Esa política **no** se aplica en `main()`: ahí `currentUser` todavía puede
/// ser `null` porque Firebase restaura la sesión de forma asíncrona, así que la
/// casilla desmarcada nunca llegaba a ejecutarse. Se aplica en
/// `PantallaDeArranque`, que es el primer punto donde se sabe con certeza si hay
/// usuario.
///
/// ## Memoria de la última sesión
///
/// Además de la casilla se guarda el correo de la última cuenta que quedó con
/// sesión abierta ([recordarSesion]). No sustituye a Firebase ni permite entrar
/// sin token: sirve para distinguir "esta persona nunca inició sesión" (mostrar
/// la bienvenida) de "esta persona tenía sesión y Firebase no la restauró"
/// (mostrar un aviso con reintento, en vez de fingir que se cerró la sesión).
class PreferenciasDeSesion {
  PreferenciasDeSesion._();

  static const String _claveRecordarme = 'recordarme';
  static const String _claveSesion = 'sesion_correo';

  /// `true` por defecto: en un teléfono personal lo esperable es no tener que
  /// iniciar sesión cada vez. La casilla del login aparece marcada la primera
  /// vez y refleja lo que el usuario eligió después.
  static Future<bool> recordarme() async {
    try {
      final preferencias = await SharedPreferences.getInstance();
      return preferencias.getBool(_claveRecordarme) ?? true;
    } catch (_) {
      // Si el almacenamiento local falla, se mantiene el comportamiento
      // histórico (recordar la sesión) en vez de dejar entrar siempre.
      return true;
    }
  }

  static Future<void> guardarRecordarme(bool valor) async {
    try {
      final preferencias = await SharedPreferences.getInstance();
      await preferencias.setBool(_claveRecordarme, valor);
    } catch (_) {
      // No es crítico: el login ya ocurrió. Como mucho se recordará la sesión
      // cuando el usuario pidió no hacerlo.
    }
  }

  /// Correo de la última cuenta que quedó con sesión abierta, o `null`.
  ///
  /// No es una credencial: no hay token ni contraseña guardados aquí.
  static Future<String?> sesionRecordada() async {
    try {
      final preferencias = await SharedPreferences.getInstance();
      final String? correo = preferencias.getString(_claveSesion);
      return (correo == null || correo.isEmpty) ? null : correo;
    } catch (_) {
      return null;
    }
  }

  /// Anota que [correo] tiene sesión abierta. Se llama en cada login, en el
  /// registro y en cada arranque en el que Firebase sí restauró al usuario.
  static Future<void> recordarSesion(String? correo) async {
    if (correo == null || correo.isEmpty) return;
    try {
      final preferencias = await SharedPreferences.getInstance();
      await preferencias.setString(_claveSesion, correo);
    } catch (_) {
      // Solo alimenta el aviso de arranque; si falla, la app sigue funcionando.
    }
  }

  /// Borra la memoria de sesión. Se llama al cerrar sesión de verdad, nunca al
  /// restaurar una sesión existente.
  static Future<void> olvidarSesion() async {
    try {
      final preferencias = await SharedPreferences.getInstance();
      await preferencias.remove(_claveSesion);
    } catch (_) {
      // Ídem: no es crítico.
    }
  }

  /// Aplica la casilla "Recordarme" a la sesión que Firebase acaba de
  /// restaurar.
  ///
  /// Devuelve el usuario si hay que dejarlo entrar (o `null` si no hay sesión o
  /// si el usuario pidió no ser recordado). Nunca lanza: un fallo de
  /// `shared_preferences` no debe impedir abrir la app.
  static Future<User?> aplicarPoliticaDeArranque(User? user) async {
    final bool recordar = await recordarme();

    if (recordar) {
      // Refresca la memoria: este es el caso normal de un arranque con sesión.
      await recordarSesion(user?.email);
      return user;
    }

    // La casilla desmarcada manda, incluso si Firebase todavía no había
    // terminado de restaurar al usuario cuando se llamó a esta función.
    if (user != null) {
      try {
        if (!kIsWeb) await GoogleAuth.cerrarSesion();
      } catch (_) {
        // El cierre de Google no debe bloquear el de Firebase.
      }
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {
        // Si el cierre falla, es menos malo dejar la sesión que bloquear la app
        // en un estado del que el usuario no puede salir.
        return user;
      }
    }

    await olvidarSesion();
    return null;
  }
}
