import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';

/// Distintivo cuadrado de Google, dibujado con un `Text` en vez de una imagen
/// para no meter otro asset al bundle.
const Widget insigniaGoogle = SizedBox(
  width: 22,
  height: 22,
  child: DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.all(Radius.circular(4)),
    ),
    child: Center(
      child: Text(
        'G',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Color(0xFF4285F4),
        ),
      ),
    ),
  ),
);

/// Botón secundario "Continuar con Google".
///
/// **Nunca debe verse igual al botón primario de la misma tarjeta.** Una
/// versión anterior los dibujó a los dos sólidos y separados por 10 px; los
/// usuários tocaban el equivocado y reportaban "el registro por correo
/// muestra un error de Google". Por eso este es blanco con borde `formAction`
/// y el primario es oscuro macizo.
class GoogleButton extends StatelessWidget {
  const GoogleButton({
    super.key,
    required this.onPressed,
    this.texto = 'Continuar con Google',
    this.cargando = false,
  });

  final VoidCallback? onPressed;
  final String texto;
  final bool cargando;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        height: 48,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppColors.formAction,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            side: const BorderSide(color: AppColors.formAction, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: cargando ? null : onPressed,
          // El `Stack` mantiene el contenido en el árbol (invisible mientras
          // carga) para que el botón no estreche y luego vuelva a crecer.
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: cargando ? 0 : 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    insigniaGoogle,
                    const SizedBox(width: 10),
                    FittedBox(
                      // Con la fuente del sistema agrandada la etiqueta se
                      // salía del botón.
                      fit: BoxFit.scaleDown,
                      child: Text(
                        texto,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.formAction,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (cargando)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.formAction,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
