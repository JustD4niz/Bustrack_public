import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificacionesEnabled = true;
  bool _sonidosEnabled = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Ajustes',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
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
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text(
                      'Notificaciones',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    value: _notificacionesEnabled,
                    activeThumbColor: Colors.amber,
                    onChanged: (val) =>
                        setState(() => _notificacionesEnabled = val),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    title: const Text(
                      'Sonidos',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    value: _sonidosEnabled,
                    activeThumbColor: Colors.amber,
                    onChanged: (val) => setState(() => _sonidosEnabled = val),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _buildSettingRow('Idioma', 'Español'),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _buildSettingRow('Unidad de distancia', 'Kilómetros (km)'),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _buildNavigationRow('Centro de ayuda'),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _buildNavigationRow('Acerca de'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 15,
              color: Colors.black87,
            ),
          ),
          Row(
            children: [
              Text(
                value,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Colors.grey,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationRow(String title) {
    return ListTile(
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 15,
          color: Colors.black87,
        ),
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios_rounded,
        size: 14,
        color: Colors.grey,
      ),
      onTap: () {},
    );
  }
}
