import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Cambia 'bus_track_app' por el nombre real de tu carpeta de proyecto si
// te marca error aquí.
import 'package:bus_track_app/main.dart';
import 'package:bus_track_app/screens/login_screen.dart';

void main() {
  testWidgets('El splash muestra el logo y los dos accesos', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BusTrackApp());

    expect(find.text('BusTrack'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Registrarse'), findsOneWidget);
  });

  testWidgets('El login muestra el saludo y el botón de ingreso', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PantallaLoginPaisaje()));

    expect(find.text('Bienvenido'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });
}
