import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';

/// Campo de texto de los formularios de acceso (login y registro).
///
/// Monta un `TextField` real sobre una barra amarillo pálido con la etiqueta
/// como placeholder que se desvanece al escribir, para no estorbar.
///
/// El widget administra su propio [TextEditingController] y [FocusNode];
/// quien lo usa recibe el valor mediante [onChanged] / [onSubmitted].
class GradientField extends StatefulWidget {
  const GradientField({
    super.key,
    required this.label,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.obscureText = false,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
  });

  /// Texto que actúa de placeholder. Ej. 'Correo Electrónico'.
  final String label;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final bool obscureText;
  final List<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<GradientField> createState() => _GradientFieldState();
}

class _GradientFieldState extends State<GradientField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: AppColors.formField,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: GestureDetector(
        // Toda la caja enfoca, no solo la franja del texto.
        behavior: HitTestBehavior.opaque,
        onTap: _focus.requestFocus,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // `isCollapsed` deja el `TextField` con la altura intrínseca de una
            // línea; el `Row` (centrado en cruz por defecto) lo coloca a media
            // altura de los 54 px. Estirarlo a la caja completa era lo que
            // dejaba el texto pegado arriba.
            Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    obscureText: widget.obscureText,
                    keyboardType: widget.keyboardType,
                    textInputAction: widget.textInputAction,
                    textCapitalization: widget.textCapitalization,
                    autofillHints: widget.autofillHints,
                    onChanged: widget.onChanged,
                    onSubmitted: widget.onSubmitted,
                    textAlign: TextAlign.start,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      color: AppColors.textStrong,
                    ),
                    cursorColor: AppColors.ink,
                    decoration: const InputDecoration(
                      filled: false,
                      isCollapsed: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
            Positioned.fill(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) {
                  // `trim()` y no `isEmpty`: al escribir solo espacios el campo
                  // ya no se ve en blanco, porque la etiqueta se desvanecería y
                  // lo único que habría debajo sería un espacio invisible.
                  final bool visible = value.text.trim().isEmpty;
                  return IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: visible ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
