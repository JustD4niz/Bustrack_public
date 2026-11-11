import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';

import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'services/session_router.dart';

/// Punto de entrada de la aplicación BusTrack (transporte y seguridad
/// escolar). Configura el tema global, la tipografía y el sistema de
/// navegación compartido por todas las pantallas.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa Firebase usando las opciones de la plataforma actual
  // (generadas por FlutterFire CLI en firebase_options.dart).
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // La política de "Recordarme" ya no se aplica aquí: en este punto
  // `currentUser` todavía puede ser null porque Firebase restaura la sesión de
  // forma asíncrona, y la casilla desmarcada no llegaba a ejecutarse. Se aplica
  // en `PantallaDeArranque`, que espera a que la sesión esté disponible.

  // Barra de estado y navegación claras, acordes al fondo crema #FFF6DC.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Con la sesión guardada, el usuario entra directo a su panel en vez de
  // volver a ver el login cada vez que abre la app. La decisión la toma
  // `PantallaDeArranque`, que se muestra a sí misma el splash mientras resuelve
  // (así no hay pantalla en blanco esperando la red).
  runApp(const BusTrackApp(inicio: PantallaDeArranque()));
}

/// Paleta de colores corporativa centralizada.
///
/// Todos los archivos del proyecto (pantallas, painter, botones) deben
/// referenciar estos valores en lugar de escribir `Color(0xFF...)` de
/// forma dispersa, para que un futuro cambio de branding se propague
/// desde un único lugar.
///
/// Lenguaje visual "bus escolar": amarillo #FDB913 en encabezados, chips y
/// elemento activo; crema #FFF6DC de fondo; tarjetas blancas muy redondeadas
/// con sombra suave; negro #1A1A1A en botones, iconos y títulos.
class AppColors {
  AppColors._();

  // Amarillo principal: encabezados, chips y elemento activo de la barra.
  static const Color primary = Color(0xFFFDB913);
  static const Color primaryDeep = Color(0xFFE0A100);

  // Amarillo pálido para campos de datos y cajas informativas.
  static const Color primaryPale = Color(0xFFFFF4CC);
  static const Color primarySoft = Color(0xFFFFE7A3);

  // Fondos y superficies.
  static const Color background = Color(0xFFFFF6DC);
  static const Color cream = Color(0xFFFFF6DC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFF0E6CE);

  // Oscuro de botones principales y titulares.
  static const Color ink = Color(0xFF1A1A1A);
  static const Color inkSoft = Color(0xFF2E2E2E);

  // Estados. Verde solo para "correcto"; rojo solo para acciones destructivas.
  static const Color success = Color(0xFF2E9E5B);
  static const Color danger = Color(0xFFD93025);

  // Texto sobre fondos claros.
  static const Color textStrong = Color(0xFF1A1A1A);
  static const Color textMuted = Color(0xFF7C7565);

  // Sombra suave de las tarjetas blancas.
  static const Color shadow = Color(0x14000000);

  // --- Alias heredados: pantallas que aún no se rediseñan siguen
  // --- compilando y adoptan la paleta nueva sin tocar su código.
  static const Color primaryDark = Color(0xFFFFF1C2);
  static const Color primaryLight = Color(0xFFFFF6DC);
  static const Color accentWarm = primary;
  static const Color accentWarmDeep = primaryDeep;
  static const Color accentYellow = primary;
  static const Color surfaceLight = Color(0xFFFFF1C9);
  static const Color roadDark = ink;
  static const Color textDark = ink;

  static const Color safetyGreen = success;
  static const Color safetyGreenDeep = Color(0xFF1F7D46);

  static const Color formCard = surface;
  static const Color formAction = ink;
  static const Color formField = primaryPale;
  static const Color formLabel = textMuted;

  // Superficies de vidrio (glassmorphism), usadas por pantallas antiguas.
  static const Color glassFillDark = Color(0x1FFFFFFF);
  static const Color glassFillLight = Color(0xB8FFFFFF);
  static const Color glassBorder = Color(0x33FFFFFF);

  static const Color textPrimary = Color(0xFFF5F8FF);
  static const Color textSecondary = Color(0xB3F5F8FF);

  static const Color textOnLightPrimary = textStrong;
  static const Color textOnLightSecondary = textMuted;

  static const Color error = danger;
}

class BusTrackApp extends StatelessWidget {
  const BusTrackApp({super.key, this.inicio});

  /// Pantalla raíz. `main()` pasa aquí `PantallaDeArranque`, que decide entre el
  /// panel del usuario con sesión guardada y el splash. El valor por defecto
  /// mantiene el splash para los tests, que pumpean `BusTrackApp()` sin pasar
  /// por `main()`.
  final Widget? inicio;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BusTrack',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: inicio ?? const SplashScreen(),
    );
  }

  /// Construye el `ThemeData` global: esquema de color, tipografía Poppins
  /// (sans-serif geométrica) y estilo por defecto de tarjetas, campos de texto
  /// y botones.
  ThemeData _buildTheme() {
    final TextTheme texto = GoogleFonts.poppinsTextTheme();
    final TextTheme textoAjustado = texto.copyWith(
      bodyLarge: texto.bodyLarge?.copyWith(color: AppColors.textStrong),
      bodyMedium: texto.bodyMedium?.copyWith(color: AppColors.textStrong),
      titleLarge: texto.titleLarge?.copyWith(
        color: AppColors.textStrong,
        fontWeight: FontWeight.w700,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: GoogleFonts.poppins().fontFamily,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        onPrimary: AppColors.ink,
        secondary: AppColors.ink,
        onSecondary: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.textStrong,
        error: AppColors.danger,
      ),
      textTheme: textoAjustado,
      // Tarjetas blancas muy redondeadas con sombra suave.
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surface,
        margin: EdgeInsets.zero,
        shadowColor: AppColors.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
        ),
      ),
      // Campos de texto: amarillo pálido, radio 16 y foco negro.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.formField,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: TextStyle(
          color: AppColors.textMuted,
          fontFamily: GoogleFonts.poppins().fontFamily,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.ink, width: 1.5),
        ),
      ),
      // Botones principales negros con texto blanco y radio 18.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.ink.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          textStyle: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.ink, width: 1.5),
          textStyle: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.ink,
          textStyle: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: GoogleFonts.poppins(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (estados) => estados.contains(WidgetState.selected)
              ? AppColors.ink
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(AppColors.primary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        side: const BorderSide(color: AppColors.textMuted, width: 1.5),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _FadeSlidePageTransitionsBuilder(),
          TargetPlatform.iOS: _FadeSlidePageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Transición de página global: fade + desplazamiento vertical sutil,
/// más orgánica que el "slide" horizontal por defecto de Material.
/// Las pantallas pueden usar además su propia `PageRouteBuilder` (como
/// hace `login_screen.dart` al navegar al dashboard) cuando quieran dar
/// énfasis especial a una transición puntual.
class _FadeSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const _FadeSlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
