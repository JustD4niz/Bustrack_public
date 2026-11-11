import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart' show AppColors;

/// Lenguaje visual compartido del rediseño "bus escolar".
///
/// Reúne las piezas que se repiten en todas las pantallas: el encabezado
/// amarillo con esquinas inferiores redondeadas, la línea punteada de
/// carretera, las tarjetas blancas con sombra suave, los campos y cajas en
/// amarillo pálido y las píldoras de estado negras con punto amarillo.
///
/// Todo es puramente visual: ninguno de estos widgets conoce Firestore, la
/// sesión ni la navegación. Las pantallas siguen siendo dueñas de su lógica.

/// Tipografía geométrica compartida por los textos del rediseño.
TextStyle busText({
  double? size,
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.textStrong,
  double? height,
  double? letterSpacing,
}) {
  return GoogleFonts.poppins(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );
}

/// Encabezado amarillo con esquinas inferiores redondeadas, círculos
/// decorativos claros y una línea punteada tipo carretera.
class BusHeader extends StatelessWidget {
  const BusHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 22),
    this.showRoad = true,
    this.titleSize = 24,
    this.fullBleed = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsets padding;
  final bool showRoad;
  final double titleSize;

  /// Cuando el encabezado va pegado al borde superior de la pantalla, las
  /// esquinas de arriba quedan rectas y solo redondean las de abajo.
  final bool fullBleed;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(fullBleed ? 0 : 26),
        bottom: const Radius.circular(34),
      ),
      child: Container(
        color: AppColors.primary,
        child: Stack(
          children: [
            Positioned(
              top: -46,
              right: -34,
              child: _circulo(150, Colors.white.withValues(alpha: 0.20)),
            ),
            Positioned(
              bottom: -44,
              left: -30,
              child: _circulo(124, AppColors.primarySoft.withValues(alpha: 0.65)),
            ),
            Positioned(
              top: 20,
              right: 92,
              child: _circulo(22, Colors.white.withValues(alpha: 0.38)),
            ),
            Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (leading != null) ...[
                        leading!,
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: busText(
                                size: titleSize,
                                weight: FontWeight.w800,
                                height: 1.15,
                                letterSpacing: -0.4,
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                subtitle!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: busText(
                                  size: 12.5,
                                  weight: FontWeight.w500,
                                  color: AppColors.ink.withValues(alpha: 0.72),
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: 12),
                        trailing!,
                      ],
                    ],
                  ),
                  if (showRoad) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 8,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _LineaCarreteraPainter(
                          color: AppColors.ink.withValues(alpha: 0.22),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _circulo(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Encabezado amarillo con botón de volver, para las pantallas de formulario.
class BusPageHeader extends StatelessWidget {
  const BusPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing,
    this.showRoad = true,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;
  final bool showRoad;

  @override
  Widget build(BuildContext context) {
    return BusHeader(
      title: title,
      subtitle: subtitle,
      showRoad: showRoad,
      titleSize: 21,
      leading: BusIconButton(
        icon: Icons.arrow_back_rounded,
        tooltip: 'Volver',
        onTap: onBack ?? () => Navigator.of(context).maybePop(),
      ),
      trailing: trailing,
    );
  }
}

/// Botón circular blanco translúcido para encabezados amarillos.
class BusIconButton extends StatelessWidget {
  const BusIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 44,
    this.background = Colors.white,
    this.foreground = AppColors.ink,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final double size;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Tooltip(
          message: tooltip ?? '',
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: foreground, size: size * 0.5),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta blanca muy redondeada con sombra suave.
class BusCard extends StatelessWidget {
  const BusCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.color = AppColors.surface,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Caja de datos en amarillo pálido, con icono opcional a la izquierda.
class BusInfoBox extends StatelessWidget {
  const BusInfoBox({
    super.key,
    required this.child,
    this.icon,
    this.iconColor = AppColors.ink,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    this.background = AppColors.primaryPale,
  });

  final Widget child;
  final IconData? icon;
  final Color iconColor;
  final EdgeInsetsGeometry padding;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 19, color: iconColor),
            const SizedBox(width: 10),
          ],
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Campo de formulario con icono a la izquierda en una caja de altura fija.
///
/// El texto queda centrado verticalmente: el `TextField` va con
/// `isCollapsed: true` (toma su altura intrínseca, la de una línea) dentro de
/// un `Row`, y el `Row` centra en cruz. Sin eso, un `TextField` estirado a los
/// 54 px de la caja pega el texto arriba.
class BusInputBox extends StatefulWidget {
  const BusInputBox({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.trailing,
    this.obscureText = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.height = 54,
  });

  final TextEditingController controller;

  /// Texto de ayuda que se ve mientras el campo está vacío.
  final String label;
  final IconData? icon;

  /// Acción opcional al final de la fila (por ejemplo, el ojo de
  /// visibilidad de una contraseña).
  final Widget? trailing;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final double height;

  @override
  State<BusInputBox> createState() => _BusInputBoxState();
}

class _BusInputBoxState extends State<BusInputBox> {
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Tocar el icono o el borde también enfoca: el `TextField` solo ocupa la
      // franja del texto y el resto de la caja quedaría muerta.
      behavior: HitTestBehavior.opaque,
      onTap: _focus.requestFocus,
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: AppColors.formField,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            if (widget.icon != null) ...[
              const SizedBox(width: 14),
              Icon(widget.icon, color: AppColors.ink, size: 22),
            ],
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  obscureText: widget.obscureText,
                  keyboardType: widget.keyboardType,
                  textCapitalization: widget.textCapitalization,
                  textInputAction: widget.textInputAction,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  style: busText(size: 14, color: AppColors.textStrong),
                  cursorColor: AppColors.ink,
                  decoration: InputDecoration(
                    filled: false,
                    isCollapsed: true,
                    hintText: widget.label,
                    hintStyle: busText(size: 13, color: AppColors.textMuted),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            if (widget.trailing != null) ...[
              widget.trailing!,
              const SizedBox(width: 4),
            ] else
              const SizedBox(width: 14),
          ],
        ),
      ),
    );
  }
}

/// Etiqueta de estado en píldora negra con punto amarillo.
class BusStatusPill extends StatelessWidget {
  const BusStatusPill({
    super.key,
    required this.label,
    this.dotColor = AppColors.primary,
    this.background = AppColors.ink,
    this.foreground = Colors.white,
    this.icon,
  });

  final String label;
  final Color dotColor;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 13, color: dotColor)
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: busText(
                size: 11.5,
                weight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cuadrado amarillo redondeado con un icono negro.
class BusIconBadge extends StatelessWidget {
  const BusIconBadge({
    super.key,
    required this.icon,
    this.size = 48,
    this.iconSize,
    this.color = AppColors.primary,
    this.iconColor = AppColors.ink,
    this.radius,
  });

  final IconData icon;
  final double size;
  final double? iconSize;
  final Color color;
  final Color iconColor;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius ?? size * 0.32),
      ),
      child: Icon(icon, color: iconColor, size: iconSize ?? size * 0.52),
    );
  }
}

/// Botón principal negro con icono amarillo.
class BusPrimaryButton extends StatelessWidget {
  const BusPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 52,
    this.background = AppColors.ink,
    this.foreground = Colors.white,
    this.iconColor = AppColors.primary,
    this.loading = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;
  final Color background;
  final Color foreground;
  final Color iconColor;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        onPressed: loading ? null : onPressed,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: loading ? 0 : 1,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20, color: iconColor),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      label,
                      style: busText(
                        size: 15,
                        weight: FontWeight.w700,
                        color: foreground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (loading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Estado vacío o aviso, sobre tarjeta blanca.
class BusEmptyState extends StatelessWidget {
  const BusEmptyState({
    super.key,
    required this.text,
    this.icon = Icons.directions_bus_filled,
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
  });

  final String text;
  final IconData icon;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: margin,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(26),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BusIconBadge(icon: icon, size: 54, color: AppColors.primaryPale),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: busText(
                size: 14,
                color: AppColors.textMuted,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila tocable para las listas de opciones de un perfil.
///
/// Icono, título y, si se pasa, un subtítulo; a la derecha, un chevron (o el
/// widget que se pase en [trailing]). El fondo amarillo pálido la distingue de
/// la tarjeta blanca que la contiene.
class BusOpcion extends StatelessWidget {
  const BusOpcion({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.color = AppColors.textStrong,
    this.background = AppColors.primaryPale,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color color;
  final Color background;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: busText(
                        size: 14,
                        weight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: busText(
                          size: 11.5,
                          color: AppColors.textMuted,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing ??
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta blanca con título, subtítulo y una lista de hijos.
///
/// Es la sección que usan los perfiles para agrupar filas: "Opciones", "Mis
/// datos", "Mi bus"... El título lleva la misma barra amarilla corta que el
/// resto de tarjetas del rediseño.
class BusSeccion extends StatelessWidget {
  const BusSeccion({
    super.key,
    required this.titulo,
    required this.children,
    this.subtitulo,
    this.icon,
    this.padding = const EdgeInsets.fromLTRB(18, 18, 18, 18),
  });

  final String titulo;
  final String? subtitulo;
  final List<Widget> children;
  final IconData? icon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return BusCard(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                BusIconBadge(icon: icon!, size: 38, color: AppColors.primaryPale),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: busText(size: 19, weight: FontWeight.w700),
                    ),
                    if (subtitulo != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitulo!,
                        style: busText(
                          size: 12,
                          color: AppColors.textMuted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 34,
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final hijo in children)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: hijo),
        ],
      ),
    );
  }
}

/// Fila etiqueta / valor sobre una caja de datos amarillo pálido.
class BusDato extends StatelessWidget {
  const BusDato({
    super.key,
    required this.etiqueta,
    required this.valor,
    this.margen = EdgeInsets.zero,
  });

  final String etiqueta;
  final String valor;
  final EdgeInsetsGeometry margen;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margen,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.primaryPale,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              etiqueta,
              style: busText(size: 13.5, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: busText(
                size: 13.5,
                weight: FontWeight.w700,
                color: AppColors.textStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pinta la línea punteada tipo carretera que remata los encabezados.
class _LineaCarreteraPainter extends CustomPainter {
  const _LineaCarreteraPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const dash = 16.0;
    const gap = 10.0;
    final y = size.height / 2;
    for (double x = 0; x < size.width; x += dash + gap) {
      final end = (x + dash).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineaCarreteraPainter oldDelegate) =>
      oldDelegate.color != color;
}
