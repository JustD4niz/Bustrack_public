import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../admin_home_screen.dart';
import '../admin_service.dart';
import '../parent_home_screen.dart';
import '../screens/driver_ruta_screen.dart';
import '../screens/login_screen.dart';
import '../screens/role_selection_screen.dart';
import '../screens/solicitud_revision_screen.dart';
import '../screens/splash_screen.dart';
import 'google_auth.dart';
import 'session_prefs.dart';

/// A dónde va un usuario autenticado y cómo llegar ahí.
///
/// [dejarLoginDebajo] distingue los dos casos del login:
///
/// - `false` (admin, padre, conductor): se entra con `pushReplacement`, porque
///   ya no hay nada útil que hacer volviendo al formulario.
/// - `true` (usuario sin ficha): se entra con `push`, para que el login quede
///   debajo y el botón de atrás tenga a dónde volver mientras completa el rol.
///
/// Al arrancar la app con una sesión ya guardada no hay login debajo de nada:
/// ahí lo único que importa es [pantalla], que se convierte en la raíz.
class DestinoDeSesion {
  const DestinoDeSesion(this.pantalla, {this.dejarLoginDebajo = false});

  final Widget pantalla;
  final bool dejarLoginDebajo;
}

/// Decide a dónde va [user] mirando primero si es el admin y luego su ficha en
/// `usuarios/{uid}`.
///
/// Es la única copia de esta lógica: la usan tanto `login_screen.dart` (tras
/// iniciar sesión) como el arranque de la app (`session_router.dart`), para que
/// la sesión guardada y el login recién hecho terminen siempre en el mismo
/// panel.
Future<DestinoDeSesion> resolverDestinoDeSesion(User user) async {
  // Deja constancia de que esta cuenta quedó con sesión abierta. El arranque
  // usa esa nota para distinguir "aquí nunca se inició sesión" (bienvenida) de
  // "había sesión y Firebase no la restauró" (aviso con reintento).
  await PreferenciasDeSesion.recordarSesion(user.email);

  if (AdminService.isAdmin(user.email)) {
    return const DestinoDeSesion(AdminHomeScreen());
  }

  final DocumentSnapshot userDoc = await FirebaseFirestore.instance
      .collection('usuarios')
      .doc(user.uid)
      .get();

  if (!userDoc.exists) {
    return const DestinoDeSesion(
      RoleSelectionScreen(),
      dejarLoginDebajo: true,
    );
  }

  final String role = userDoc.get('role') ?? 'parent';

  // Un conductor tiene que estar aprobado para entrar al panel. Antes
  // `isApproved` solo filtraba la cola del administrador y el login lo
  // ignoraba; ahora es la puerta real. `PantallaSolicitudRevision` muestra el
  // motivo si fue rechazado y permite corregir y reenviar.
  if (role == 'driver' && userDoc.get('isApproved') != true) {
    return DestinoDeSesion(
      PantallaSolicitudRevision(
        rechazo: userDoc.get('estadoSolicitud') == 'rechazado',
        motivoRechazo: userDoc.get('motivoRechazo')?.toString(),
      ),
    );
  }

  return DestinoDeSesion(
    role == 'parent' ? const ParentHomeScreen() : const PantallaRutaConductor(),
  );
}

/// Pantalla raíz con la que arranca la app.
///
/// Mientras decide a dónde entrar muestra [_RestaurandoSesion] (no la
/// bienvenida), así que nunca hay pantalla en blanco ni la impresión de haber
/// cerrado sesión. Es un widget y no una función que se resuelve antes de
/// `runApp` porque la resolución toca la red: con la función anterior la app no
/// pintaba nada hasta terminar.
///
/// La sesión guardada se lee de `currentUser` y, si todavía no está, de la
/// primera emisión **no nula** de `authStateChanges()`: Firebase restaura el
/// usuario de forma asíncrona y el stream emite `null` un instante antes, así
/// que `authStateChanges().first` mandaba al login en cada arranque en frío.
class PantallaDeArranque extends StatefulWidget {
  const PantallaDeArranque({super.key});

  @override
  State<PantallaDeArranque> createState() => _PantallaDeArranqueState();
}

class _PantallaDeArranqueState extends State<PantallaDeArranque> {
  /// Se reasigna al reintentar; el `FutureBuilder` de `build` lo observa.
  Future<Widget>? _destino;

  @override
  void initState() {
    super.initState();
    _destino = _resolver();
  }

  Future<Widget> _resolver() async {
    // Si hay una sesión anotada se le da más margen a Firebase para restaurarla
    // y, si no lo logra, se muestra un aviso en vez de la bienvenida.
    final String? correoRecordado =
        await PreferenciasDeSesion.sesionRecordada();

    final User? usuario = await _usuarioConSesion(
      esperarSesion: correoRecordado != null,
    );
    if (usuario == null) {
      if (correoRecordado != null) {
        return _SesionNoRestaurada(
          correo: correoRecordado,
          onReintentar: _reintentar,
          onIniciarSesion: _irAlLogin,
        );
      }
      return const SplashScreen();
    }

    // "Recordarme": este es el primer punto donde se sabe con certeza que hay
    // usuario, así que aquí sí se puede aplicar la casilla desmarcada.
    final User? recordado =
        await PreferenciasDeSesion.aplicarPoliticaDeArranque(usuario);
    if (recordado == null) return const SplashScreen();

    // Primero la copia local del perfil: el arranque no espera a la red. Si no
    // está cacheada (cuenta nueva o caché limpiada) se pregunta al servidor.
    final Widget? desdeCache = await _destinoDesdeCache(recordado);
    if (desdeCache != null) return desdeCache;

    try {
      final DestinoDeSesion destino =
          await resolverDestinoDeSesion(recordado);
      return destino.pantalla;
    } catch (_) {
      // Sin red la ficha no se pudo leer. Antes esto devolvía al login a un
      // usuario que ya tenía sesión; ahora se ofrece reintentar **sin cerrar
      // la sesión**. Devolver `SplashScreen` aquí mostraba la bienvenida con
      // "Iniciar sesión"/"Registrarse" a alguien que seguía autenticado, que es
      // indistinguible de un cierre de sesión.
      return _SinConexion(
        correo: recordado.email,
        onReintentar: _reintentar,
        onCerrarSesion: _cerrarSesion,
      );
    }
  }

  void _reintentar() {
    setState(() => _destino = _resolver());
  }

  /// Sale del aviso de "sesión no restaurada" hacia el login.
  Future<void> _irAlLogin() async {
    // La nota de sesión ya no describe la realidad: Firebase no la restauró.
    await PreferenciasDeSesion.olvidarSesion();
    if (!mounted) return;
    setState(
      () => _destino = Future<Widget>.value(const PantallaLoginPaisaje()),
    );
  }

  Future<void> _cerrarSesion() async {
    try {
      await GoogleAuth.cerrarSesion();
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      // Si falla, igual se vuelve al login: es el único camino de salida.
    }
    await PreferenciasDeSesion.olvidarSesion();
    if (mounted) {
      setState(() => _destino = Future<Widget>.value(const SplashScreen()));
    }
  }

  /// Usuario con sesión guardada, o `null` si de verdad no hay nadie.
  ///
  /// `currentUser` es la fuente fiable en el arranque normal. Si todavía no
  /// está (restauración en curso), se espera a la primera emisión **no nula**
  /// del stream durante unos segundos: el `where` es justo lo que evita tomar
  /// el `null` inicial como "no hay sesión".
  ///
  /// [esperarSesion] viene de `sesionRecordada()`: sin sesión anotada lo normal
  /// es que no haya nadie, y esperar el margen largo dejaría a un usuario sin
  /// cuenta mirando "Restaurando…" en cada arranque.
  Future<User?> _usuarioConSesion({required bool esperarSesion}) async {
    final User? actual = FirebaseAuth.instance.currentUser;
    if (actual != null) return actual;

    try {
      return await FirebaseAuth.instance
          .authStateChanges()
          .where((User? u) => u != null)
          .first
          .timeout(
            esperarSesion
                ? const Duration(seconds: 6)
                : const Duration(seconds: 1),
          );
    } on TimeoutException {
      return null;
    }
  }

  /// Destino a partir de la copia local de `usuarios/{uid}`, para entrar sin
  /// esperar a la red. Devuelve `null` si la ficha no está cacheada; en ese caso
  /// el llamador pregunta al servidor (o muestra [_SinConexion] si tampoco hay
  /// conexión), nunca la bienvenida.
  Future<Widget?> _destinoDesdeCache(User user) async {
    if (AdminService.isAdmin(user.email)) {
      return const AdminHomeScreen();
    }

    try {
      final DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .get(const GetOptions(source: Source.cache));
      if (!userDoc.exists) return null;

      final String role = userDoc.get('role') ?? 'parent';

      // Misma puerta que `resolverDestinoDeSesion`: el arranque no debe dejar
      // entrar a un conductor sin aprobar por la vía del caché.
      if (role == 'driver' && userDoc.get('isApproved') != true) {
        return PantallaSolicitudRevision(
          rechazo: userDoc.get('estadoSolicitud') == 'rechazado',
          motivoRechazo: userDoc.get('motivoRechazo')?.toString(),
        );
      }

      return role == 'parent'
          ? const ParentHomeScreen()
          : const PantallaRutaConductor();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _destino,
      builder: (BuildContext context, AsyncSnapshot<Widget> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // Nunca la bienvenida mientras se resuelve: verla un instante y saltar
          // al panel se confunde con "me sacó de la cuenta".
          return const _RestaurandoSesion();
        }
        return snapshot.data ?? const SplashScreen();
      },
    );
  }
}

/// Pantalla puente del arranque.
///
/// Antes ese hueco lo ocupaba [SplashScreen], la bienvenida con "Iniciar
/// sesión"/"Registrarse". En un teléfono lento el tránsito duraba segundos y el
/// usuario creía que la sesión se había perdido; si alcanzaba a tocar "Iniciar
/// sesión", además aterrizaba en el formulario con la sesión ya restaurada.
/// Esto deja claro que solo está cargando.
class _RestaurandoSesion extends StatelessWidget {
  const _RestaurandoSesion();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFFFF6DC),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 84,
                height: 84,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFFFDB913),
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                  ),
                  child: Icon(
                    Icons.directions_bus_filled,
                    size: 48,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
              SizedBox(height: 22),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Restaurando tu sesión…',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF7C7565),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aviso para cuando la app esperaba una sesión guardada y Firebase no la
/// restauró (token revocado, datos de la app restaurados sin el token, etc.).
///
/// No es la bienvenida: el usuario ya tenía cuenta y merece saber que sus datos
/// siguen ahí. Tampoco entra sola al panel, porque sin token Firestore
/// rechazaría cada lectura.
class _SesionNoRestaurada extends StatelessWidget {
  const _SesionNoRestaurada({
    required this.correo,
    required this.onReintentar,
    required this.onIniciarSesion,
  });

  final String correo;
  final VoidCallback onReintentar;
  final Future<void> Function() onIniciarSesion;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF6DC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.lock_reset_rounded,
                    size: 56,
                    color: Color(0xFF7C7565),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No pudimos restaurar tu sesión',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tu cuenta ($correo) sigue existiendo; solo se perdió la '
                    'sesión guardada en este teléfono. Vuelve a iniciar sesión '
                    'y todo quedará como lo dejaste.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Color(0xFF7C7565),
                    ),
                  ),
                  const SizedBox(height: 22),
                  ElevatedButton.icon(
                    onPressed: onIniciarSesion,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Iniciar sesión'),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: onReintentar,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pantalla de emergencia del arranque: hay sesión, pero no se pudo leer la
/// ficha para saber a qué panel entrar.
///
/// No es el login. Mostrar la bienvenida aquí hacía creer al usuario que lo
/// habían sacado de su cuenta; esto deja claro que sigue dentro y solo falta
/// conexión, con un botón para reintentar y otro para cerrar sesión de verdad.
class _SinConexion extends StatelessWidget {
  const _SinConexion({
    required this.correo,
    required this.onReintentar,
    required this.onCerrarSesion,
  });

  final String? correo;
  final VoidCallback onReintentar;
  final Future<void> Function() onCerrarSesion;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF6DC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.wifi_off_rounded,
                    size: 56,
                    color: Color(0xFF7C7565),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Seguimos dentro de tu cuenta',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No pudimos cargar tu perfil porque no hay conexión o el '
                    'servidor no respondió.'
                    '${correo == null ? '' : '\n\nSesión: $correo'}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Color(0xFF7C7565),
                    ),
                  ),
                  const SizedBox(height: 22),
                  ElevatedButton.icon(
                    onPressed: onReintentar,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reintentar'),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: onCerrarSesion,
                    child: const Text('Cerrar sesión'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
