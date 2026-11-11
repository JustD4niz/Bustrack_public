import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../main.dart';

/// Pintor personalizado que dibuja el paisaje corporativo de fondo:
/// cielo degradado, un resplandor cálido de horizonte, nubes suaves,
/// colinas superpuestas (para dar profundidad) y una carretera con
/// carriles en perspectiva.
///
/// Todos los colores provienen de [AppColors], de modo que un cambio de
/// paleta de marca se refleje aquí automáticamente.
class LandscapePainter extends CustomPainter {
  const LandscapePainter({this.animationValue = 0.0});

  /// Valor entre 0 y 1 usado para animar sutilmente la deriva de las
  /// nubes. Pasa 0 (valor por defecto) para un dibujo estático.
  final double animationValue;

  @override
  void paint(Canvas canvas, Size size) {
    _paintSky(canvas, size);
    _paintHorizonGlow(canvas, size);
    _paintClouds(canvas, size);
    _paintHills(canvas, size);
    _paintRoad(canvas, size);
  }

  void _paintSky(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        AppColors.primaryDeep,
        AppColors.primaryDark,
        AppColors.primaryLight.withValues(alpha: 0.9),
      ],
      stops: const [0.0, 0.55, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  /// Resplandor cálido cerca del horizonte: aporta el "acento cálido"
  /// pedido en el diseño sin recurrir a un sol literal, manteniendo el
  /// paisaje elegante y corporativo.
  void _paintHorizonGlow(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.58);
    final glow = RadialGradient(
      colors: [
        AppColors.accentWarm.withValues(alpha: 0.18),
        AppColors.accentWarm.withValues(alpha: 0.0),
      ],
    );
    final rect = Rect.fromCircle(center: center, radius: size.width * 0.6);
    canvas.drawRect(rect, Paint()..shader = glow.createShader(rect));
  }

  void _paintClouds(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.07);
    final drift = math.sin(animationValue * math.pi * 2) * 10;

    _drawCloud(
      canvas,
      paint,
      Offset(size.width * 0.2 + drift, size.height * 0.14),
      46,
    );
    _drawCloud(
      canvas,
      paint,
      Offset(size.width * 0.75 - drift, size.height * 0.22),
      34,
    );
    _drawCloud(
      canvas,
      paint,
      Offset(size.width * 0.5 + drift * 0.6, size.height * 0.08),
      26,
    );
  }

  void _drawCloud(Canvas canvas, Paint paint, Offset center, double r) {
    canvas.drawCircle(center, r, paint);
    canvas.drawCircle(center.translate(r * 0.8, r * 0.15), r * 0.7, paint);
    canvas.drawCircle(center.translate(-r * 0.8, r * 0.15), r * 0.6, paint);
  }

  void _paintHills(Canvas canvas, Size size) {
    // Colina trasera: más clara y difusa → sugiere lejanía.
    final backHill = Path()
      ..moveTo(0, size.height * 0.62)
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.52,
        size.width * 0.55,
        size.height * 0.60,
      )
      ..quadraticBezierTo(
        size.width * 0.8,
        size.height * 0.66,
        size.width,
        size.height * 0.58,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      backHill,
      Paint()..color = AppColors.primaryLight.withValues(alpha: 0.35),
    );

    // Colina delantera: más oscura y definida → primer plano.
    final frontHill = Path()
      ..moveTo(0, size.height * 0.72)
      ..quadraticBezierTo(
        size.width * 0.3,
        size.height * 0.64,
        size.width * 0.6,
        size.height * 0.71,
      )
      ..quadraticBezierTo(
        size.width * 0.85,
        size.height * 0.77,
        size.width,
        size.height * 0.68,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      frontHill,
      Paint()..color = AppColors.primaryDark.withValues(alpha: 0.92),
    );
  }

  void _paintRoad(Canvas canvas, Size size) {
    final roadTop = size.height * 0.86;
    final roadPath = Path()
      ..moveTo(size.width * 0.35, roadTop)
      ..lineTo(size.width * 0.65, roadTop)
      ..lineTo(size.width * 0.92, size.height)
      ..lineTo(size.width * 0.08, size.height)
      ..close();
    canvas.drawPath(roadPath, Paint()..color = AppColors.roadDark);

    // Carriles centrales: líneas discontinuas que convergen en
    // perspectiva, con el acento cálido, reforzando la sensación de
    // ruta activa y en movimiento.
    final lanePaint = Paint()
      ..color = AppColors.accentWarm.withValues(alpha: 0.85)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    const dashCount = 6;
    for (int i = 0; i < dashCount; i++) {
      final t0 = i / dashCount;
      final t1 = (i + 0.5) / dashCount;
      final start = Offset.lerp(
        Offset(size.width * 0.5, roadTop),
        Offset(size.width * 0.5, size.height),
        t0,
      )!;
      final end = Offset.lerp(
        Offset(size.width * 0.5, roadTop),
        Offset(size.width * 0.5, size.height),
        t1,
      )!;
      canvas.drawLine(start, end, lanePaint);
    }
  }

  @override
  bool shouldRepaint(covariant LandscapePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
