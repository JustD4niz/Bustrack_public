import 'package:flutter/material.dart';

import 'parent_register_screen.dart';

// import 'driver_register_screen.dart'; // Lo crearemos más adelante si lo necesitas

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Selecciona tu Rol - BusTrack'),
        automaticallyImplyLeading:
            false, // Evita que regresen a la pantalla de registro por error
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '¿Cómo vas a usar BusTrack?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Selecciona tu perfil para configurar tu cuenta correctamente.',
              style: TextStyle(color: Colors.grey, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),

            // Botón para Padre
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.family_restroom, size: 28),
                label: const Text(
                  'Soy Padre / Acudiente',
                  style: TextStyle(fontSize: 18),
                ),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ParentRegisterScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),

            // Botón para Conductor
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.directions_bus, size: 28),
                label: const Text(
                  'Soy Conductor',
                  style: TextStyle(fontSize: 18),
                ),
                onPressed: () {
                  // Aquí conectaremos la pantalla del conductor más adelante
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Próximamente: Registro de Conductor'),
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
