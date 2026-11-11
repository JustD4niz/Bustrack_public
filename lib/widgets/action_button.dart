import 'package:flutter/material.dart';

/// Botón de acción reutilizable, usado tanto en el formulario de login
/// como en el dashboard.
///
/// Soporta un color de fondo y de texto personalizados (para distinguir
/// visualmente una acción primaria de una secundaria, como
/// "Iniciar sesión" vs "Continuar con Google"), un borde opcional, un
/// ícono opcional y un estado de carga incorporado (`isLoading`) que
/// reemplaza el contenido por un spinner sin cambiar el tamaño del
/// botón, evitando saltos de layout.
///
/// Al presionarse, se escala ligeramente y eleva su sombra, dando una
/// sensación táctil premium.
class ActionButton extends StatefulWidget {
  const ActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.background,
    required this.foreground,
    this.border,
    this.icon,
    this.isLoading = false,
    this.height = 54,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color background;
  final Color foreground;
  final Color? border;
  final IconData? icon;
  final bool isLoading;
  final double height;

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    lowerBound: 0.0,
    upperBound: 0.05,
  );

  bool get _isEnabled => widget.onPressed != null && !widget.isLoading;

  void _onTapDown(TapDownDetails _) {
    if (_isEnabled) _pressController.forward();
  }

  void _onTapEnd() {
    if (_isEnabled) _pressController.reverse();
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final background = _isEnabled ? widget.background : Colors.grey.shade400;
    final foreground = _isEnabled ? widget.foreground : Colors.grey.shade100;

    return AnimatedBuilder(
      animation: _pressController,
      builder: (context, child) {
        final scale = 1 - _pressController.value;
        return Transform.scale(scale: scale, child: child);
      },
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: (_) => _onTapEnd(),
        onTapCancel: _onTapEnd,
        onTap: _isEnabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: widget.height,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
            border: widget.border != null
                ? Border.all(color: widget.border!, width: 1.4)
                : null,
            boxShadow: [
              if (_isEnabled)
                BoxShadow(
                  color: widget.background.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
            ],
          ),
          alignment: Alignment.center,
          child: widget.isLoading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(foreground),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, color: foreground, size: 22),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
