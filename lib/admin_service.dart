import 'package:cloud_firestore/cloud_firestore.dart';

class AdminService {
  // 🔐 CAMBIA ESTE CORREO por tu correo personal real con el que iniciarás sesión como Admin
  static const String adminEmail = "danieljerez810@gmail.com";

  // 1. Verificar si un correo corresponde al administrador
  static bool isAdmin(String? email) {
    if (email == null) return false;
    return email.trim().toLowerCase() == adminEmail.toLowerCase();
  }

  // 2. Aprobar a un conductor en Firestore
  static Future<void> aprobarConductor(String uid) async {
    try {
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).update({
        'isApproved': true, // Al cambiar a true, se le da acceso a la app
        'estadoSolicitud': 'aprobado',
        'motivoRechazo': FieldValue.delete(),
        'revisadoEn': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Error al aprobar el conductor: $e');
    }
  }

  // 3. Rechazar una solicitud de conductor.
  //
  // Antes **borraba** el documento, así que el conductor tenía que registrarse
  // de cero y perdía sus adjuntos. Ahora se marca el estado con el motivo y el
  // login lo devuelve a la pantalla de revisión, donde puede corregir y
  // reenviar (ver `session_router.dart`).
  static Future<void> rechazarConductor(
    String uid, {
    String motivo = '',
  }) async {
    final String limpio = motivo.trim();
    try {
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).update({
        'isApproved': false,
        'estadoSolicitud': 'rechazado',
        'motivoRechazo': limpio.isEmpty
            ? 'El administrador rechazó la solicitud. Corrige tus datos y '
                'vuelve a enviarla.'
            : limpio,
        'revisadoEn': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Error al rechazar el conductor: $e');
    }
  }

  // 4. Borrar la ruta de un conductor: `rutas/{uid}` y su historial.
  //
  // Borrar un documento **no** borra sus subcolecciones, así que hay que
  // vaciar `rutas/{uid}/historial` primero; si no, quedaría huérfano y el
  // panel cargaría un recorrido que ya no tiene ruta a la que pertenecer.
  // Las reglas dan al admin `write` en `rutas/{uid}` y `delete` en el
  // historial, así que ambas partes están permitidas.
  static Future<void> eliminarRuta(String uid) async {
    try {
      final rutaRef = FirebaseFirestore.instance.collection('rutas').doc(uid);
      final historial = await rutaRef.collection('historial').get();
      for (final doc in historial.docs) {
        await doc.reference.delete();
      }
      await rutaRef.delete();
    } catch (e) {
      throw Exception('Error al eliminar la ruta: $e');
    }
  }

  // 5. Borrar los puntos de recogida de un padre.
  //
  // El padre puede tener varios hijos desde que existe `estudiantes`, y cada
  // uno guarda su punto en `recogida/{id del hijo}`. El hijo **legado** (cuentas
  // viejas, con los datos dentro de `usuarios/{uid}`) usa el uid del padre como
  // id, así que hay que borrar esa clave además de las de sus hijos nuevos.
  static Future<void> eliminarPuntoRecogida(String parentUid) async {
    final db = FirebaseFirestore.instance;
    try {
      await db.collection('recogida').doc(parentUid).delete();

      final hijos = await db
          .collection('estudiantes')
          .where('parentUid', isEqualTo: parentUid)
          .get();
      for (final hijo in hijos.docs) {
        await db.collection('recogida').doc(hijo.id).delete();
      }
    } catch (e) {
      throw Exception('Error al eliminar el punto de recogida: $e');
    }
  }
}
