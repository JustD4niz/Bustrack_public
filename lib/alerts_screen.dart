import 'package:flutter/material.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> alertas = [
      {
        'titulo': 'Bus en camino',
        'descripcion': 'El bus ha salido de la institución.',
        'hora': '7:30 AM',
        'icono': Icons.directions_bus,
        'color': Colors.green,
      },
      {
        'titulo': 'Llegada a parada',
        'descripcion': 'El bus ha llegado a Parada 1.',
        'hora': '7:40 AM',
        'icono': Icons.check_circle_outline,
        'color': Colors.green,
      },
      {
        'titulo': 'Retraso en la ruta',
        'descripcion': 'Retraso de 5 minutos por tráfico.',
        'hora': '7:55 AM',
        'icono': Icons.warning_amber_rounded,
        'color': Colors.amber,
      },
      {
        'titulo': 'Desvío de ruta',
        'descripcion': 'El bus ha tomado un desvío.',
        'hora': '8:05 AM',
        'icono': Icons.alt_route,
        'color': Colors.redAccent,
      },
      {
        'titulo': 'Llegada',
        'descripcion': 'El bus ha llegado a su destino.',
        'hora': '8:15 AM',
        'icono': Icons.flag_outlined,
        'color': Colors.green,
      },
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Notificaciones',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: alertas.length,
        itemBuilder: (context, index) {
          final alerta = alertas[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (alerta['color'] as Color).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    alerta['icono'] as IconData,
                    color: alerta['color'] as Color,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            alerta['titulo']!,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            alerta['hora']!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        alerta['descripcion']!,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
