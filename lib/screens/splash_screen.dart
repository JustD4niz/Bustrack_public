import 'package:flutter/material.dart';

import '../main.dart';
import '../register_screen.dart';
import '../widgets/bus_ui.dart';
import 'login_screen.dart';

/// Pantalla de bienvenida (pantalla 1 del prototipo).
///
/// Logo BusTrack, ilustración del bus y los dos accesos: "Iniciar sesión"
/// (botón negro con icono amarillo) y "Registrarse" (botón blanco con borde).
/// No toca Firebase: solo navega, así que el test de widgets puede renderizarla
/// sin inicializar nada.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // Círculos decorativos claros, el mismo motivo de los encabezados.
            Positioned(
              top: -90,
              right: -70,
              child: _circulo(240, AppColors.primary.withValues(alpha: 0.22)),
            ),
            Positioned(
              bottom: -70,
              left: -60,
              child: _circulo(200, AppColors.primary.withValues(alpha: 0.16)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  Container(
                    width: 168,
                    height: 168,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(44),
                      boxShadow: const [
                        BoxShadow(
                          color: AppColors.shadow,
                          blurRadius: 28,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.directions_bus_filled,
                      size: 92,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'BusTrack',
                    style: busText(
                      size: 42,
                      weight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Tu tranquilidad, nuestra prioridad',
                    textAlign: TextAlign.center,
                    style: busText(
                      size: 14.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const BusStatusPill(label: 'Ruta escolar segura'),
                  const Spacer(flex: 3),
                  BusPrimaryButton(
                    label: 'Iniciar sesión',
                    icon: Icons.login_rounded,
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PantallaLoginPaisaje(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: AppColors.surface,
                        foregroundColor: AppColors.ink,
                        side: const BorderSide(
                          color: AppColors.ink,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RegisterScreen(),
                        ),
                      ),
                      icon: const Icon(
                        Icons.person_add_alt_1_rounded,
                        size: 20,
                        color: AppColors.primaryDeep,
                      ),
                      label: Text(
                        'Registrarse',
                        style: busText(
                          size: 15,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
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
