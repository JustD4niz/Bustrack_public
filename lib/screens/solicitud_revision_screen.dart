import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart' show AppColors;
import '../services/google_auth.dart';
import '../services/session_prefs.dart';
import '../widgets/bus_ui.dart';
import 'driver_register_screen.dart';
import 'login_screen.dart';

/// Pantalla que ve el conductor cuando su solicitud está pendiente o fue
/// rechazada.
///
/// Es la **puerta** del conductor sin aprobar: `resolverDestinoDeSesion` la
/// devuelve en el login y en el arranque, así que reingresar ya no salta al
/// panel. Mientras el administrador no apruebe, la única salida es corregir la
/// solicitud (si fue rechazada) o cerrar sesión.
///
/// La tarjeta crece con su contenido y la columna se desplaza, que es lo que
/// hacen el login, el registro y la selección de roles.
class PantallaSolicitudRevision extends StatelessWidget {
  const PantallaSolicitudRevision({
    super.key,
    this.rechazo = false,
    this.motivoRechazo,
  });

  /// `true` si el administrador rechazó la solicitud. Cambia el texto, pinta el
  /// motivo y ofrece "Corregir y reenviar".
  final bool rechazo;

  /// Motivo escrito por el administrador al rechazar. Puede faltar en
  /// solicitudes rechazadas con una versión anterior de la app.
  final String? motivoRechazo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            BusHeader(
              title: rechazo ? 'Solicitud rechazada' : 'Solicitud enviada',
              subtitle: rechazo
                  ? 'Revisa el motivo y vuelve a enviarla'
                  : 'Tu registro está en manos del administrador',
              titleSize: 21,
              fullBleed: true,
              leading: BusIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Volver al inicio',
                // `pop` y no `pushAndRemoveUntil`: esta pantalla llega con
                // `pushReplacement` desde el registro del conductor, así que
                // debajo sigue estando la selección de rol, que es a donde
                // "volver al inicio" tiene sentido que lleve. Si en cambio
                // jalara al login con `pushAndRemoveUntil`, el conductor
                // cerraría sesión justo después de enviar la solicitud y
                // perdería la sesión de Firebase en memoria.
                //
                // Al arrancar, en cambio, esta pantalla es la raíz y `pop` no
                // hace nada: para salir está el botón "Cerrar sesión".
                onTap: () => Navigator.of(context).maybePop(),
              ),
              trailing: BusIconBadge(
                icon: rechazo
                    ? Icons.report_gmailerrorred_rounded
                    : Icons.mark_email_read_rounded,
                size: 46,
                color: Colors.white,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: _buildTarjeta(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tarjeta blanca con el bus, el título y el texto.
  Widget _buildTarjeta(BuildContext context) {
    return BusCard(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BusIconBadge(
            icon: rechazo
                ? Icons.assignment_late_rounded
                : Icons.directions_bus_filled_rounded,
            size: 112,
            iconSize: 60,
            radius: 34,
            color: rechazo ? AppColors.danger : AppColors.primary,
            iconColor: rechazo ? Colors.white : AppColors.ink,
          ),
          const SizedBox(height: 18),
          FittedBox(
            // La etiqueta no debe partirse ni desbordarse en pantallas angostas
            // con la fuente del sistema agrandada.
            fit: BoxFit.scaleDown,
            child: Text(
              rechazo ? 'Solicitud Rechazada' : 'Solicitud en Revisión',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textStrong,
              ),
            ),
          ),
          const SizedBox(height: 14),
          BusStatusPill(
            label: rechazo
                ? 'Estado: rechazada'
                : 'Estado: pendiente de aprobación',
            dotColor: rechazo ? AppColors.danger : AppColors.primary,
            icon: rechazo ? Icons.cancel_rounded : Icons.schedule_rounded,
          ),
          const SizedBox(height: 20),
          if (rechazo) ..._buildRechazo(context) else _buildPendiente(),
          const SizedBox(height: 22),
          _buildCerrarSesion(context),
        ],
      ),
    );
  }

  /// Texto de la solicitud pendiente: el mismo mensaje de cortesía de siempre.
  Widget _buildPendiente() {
    return Text(
      'Estimado Conductor\n\n'
      'en este momento su solicitud a BusTrack está siendo revisada por '
      'los administradores de la plataforma,\n'
      'en los próximos 5 días hábiles se dará respuesta a su '
      'solicitud.\n\n'
      'Atentamente\n\n'
      'Admin de BusTrack',
      textAlign: TextAlign.center,
      style: GoogleFonts.poppins(
        fontSize: 13.5,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.normal,
        color: AppColors.textMuted,
        height: 1.45,
      ),
    );
  }

  /// Motivo del rechazo + explicación de qué hacer + botón para reenviar.
  List<Widget> _buildRechazo(BuildContext context) {
    final String motivo = (motivoRechazo ?? '').trim();
    return <Widget>[
      Text(
        'El administrador revisó tu solicitud y encontró algo que debe '
        'corregirse antes de aprobarla.',
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(
          fontSize: 13.5,
          color: AppColors.textMuted,
          height: 1.45,
        ),
      ),
      const SizedBox(height: 14),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.danger.withValues(alpha: 0.35),
          ),
        ),
        child: Text(
          motivo.isEmpty
              ? 'El administrador no dejó un motivo específico. Revisa tus '
                    'datos y documentos, corrige lo que haga falta y reenvía '
                    'la solicitud.'
              : 'Motivo: $motivo',
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textStrong,
            height: 1.4,
          ),
        ),
      ),
      const SizedBox(height: 18),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                // El formulario vuelve precargado con la ficha y conserva los
                // adjuntos que ya estaban en el servidor.
                builder: (BuildContext _) =>
                    const PantallaRegistroConductor(reenviar: true),
              ),
            );
          },
          icon: const Icon(Icons.edit_rounded, size: 18),
          label: const Text('Corregir y reenviar'),
        ),
      ),
    ];
  }

  /// Cierra la sesión de verdad y vuelve al login.
  ///
  /// Al arrancar con una sesión de conductor rechazado esta pantalla es la
  /// ruta raíz, así que "atrás" no tiene a dónde ir: sin este botón el usuario
  /// quedaría atrapado.
  Widget _buildCerrarSesion(BuildContext context) {
    return TextButton.icon(
      onPressed: () async {
        // Se resuelven antes del primer `await`: después, `context` ya está
        // detrás de un async gap y la ruta va a desaparecer.
        final NavigatorState nav = Navigator.of(context);
        try {
          await GoogleAuth.cerrarSesion();
          await FirebaseAuth.instance.signOut();
        } catch (_) {
          // Si falla, igual se sale al login: es el único camino de salida.
        }
        await PreferenciasDeSesion.olvidarSesion();
        nav.pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (BuildContext _) => const PantallaLoginPaisaje(),
          ),
          (Route<dynamic> _) => false,
        );
      },
      icon: const Icon(Icons.logout_rounded, size: 18),
      label: const Text('Cerrar sesión'),
    );
  }
}
