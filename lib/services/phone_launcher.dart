import 'package:url_launcher/url_launcher.dart';

/// Llamada telefónica compartida por los paneles del padre y del conductor.
///
/// `tel:` solo admite dígitos y el `+` inicial, así que el número se normaliza
/// aquí y no en cada pantalla. Los padres escriben el teléfono como quieren
/// ("+57 300 123 4567", "3001234567"): exigir un formato en el registro los
/// dejaría sin poder guardar.
class PhoneLauncher {
  PhoneLauncher._();

  /// Deja el número en la forma que entiende `tel:`.
  static String normalizar(String telefono) {
    return telefono.replaceAll(RegExp(r'[^0-9+]'), '');
  }

  /// Abre el marcador del teléfono. Devuelve `false` si el número quedó vacío o
  /// si el sistema no pudo abrir la app de llamadas, para que la pantalla avise
  /// en vez de dejar el toque sin respuesta.
  static Future<bool> llamar(String telefono) async {
    final String numero = normalizar(telefono);
    if (numero.isEmpty) return false;
    try {
      return await launchUrl(
        Uri(scheme: 'tel', path: numero),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}
