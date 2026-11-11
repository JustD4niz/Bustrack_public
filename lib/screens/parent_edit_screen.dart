import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../main.dart' show AppColors;
import '../services/hijos_service.dart';
import '../widgets/bus_ui.dart';

/// Edición de los datos de contacto del padre (`usuarios/{uid}`).
///
/// Los datos del estudiante y su bus ya no viven aquí: con varios hijos, cada
/// uno se edita en `ChildFormScreen` desde la tarjeta "Mis Hijos". Este
/// formulario toca solo el nombre y el teléfono de la cuenta.
///
/// Recibe [datos] (el documento ya leído por el panel) para precargar los
/// campos y guarda con `update()`. Las reglas de Firestore permiten al dueño
/// editar su ficha siempre que no cambie `role` ni se ponga `isApproved: true`;
/// aquí ninguna de las dos entra.
class ParentEditScreen extends StatefulWidget {
  const ParentEditScreen({super.key, required this.datos});

  /// Documento `usuarios/{uid}` del padre, tal como viene de Firestore.
  final Map<String, dynamic> datos;

  @override
  State<ParentEditScreen> createState() => _ParentEditScreenState();
}

class _ParentEditScreenState extends State<ParentEditScreen> {
  late final TextEditingController _fullName;
  late final TextEditingController _phone;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fullName = TextEditingController(text: _texto(widget.datos['fullName']));
    _phone = TextEditingController(text: _texto(widget.datos['phone']));
  }

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    super.dispose();
  }

  String _texto(dynamic valor) => valor?.toString().trim() ?? '';

  Future<void> _guardar() async {
    if (_fullName.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      _avisar('Completa tu nombre y tu teléfono.', esError: true);
      return;
    }

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _avisar('Tu sesión venció. Vuelve a iniciar sesión.', esError: true);
      return;
    }

    setState(() => _isLoading = true);
    final NavigatorState nav = Navigator.of(context);
    try {
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .update(<String, dynamic>{
        'fullName': _fullName.text.trim(),
        'phone': _phone.text.trim(),
      });

      // El teléfono que ve el conductor vive copiado en `recogida`, porque las
      // reglas no le dejan leer `usuarios/{uid}`. Se refresca aquí para que
      // llamar al padre no siga marcando el número viejo.
      await HijosService.sincronizarTelefonoPadre(
        parentUid: user.uid,
        telefono: _phone.text.trim(),
      );

      if (!mounted) return;
      _avisar('Cambios guardados.', esError: false);
      nav.pop();
    } on FirebaseException catch (e) {
      if (mounted) _avisar(_mensajeDeErrorDeFirestore(e), esError: true);
    } catch (_) {
      if (mounted) {
        _avisar('No se pudieron guardar los cambios.', esError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _avisar(String texto, {required bool esError}) {
    if (!mounted) return;
    final ScaffoldMessengerState avisos = ScaffoldMessenger.of(context);
    avisos.clearSnackBars();
    avisos.showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: esError ? AppColors.danger : AppColors.success,
      ),
    );
  }

  String _mensajeDeErrorDeFirestore(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'No pudimos guardar los cambios porque las reglas de la base de '
            'datos no lo permiten.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Sin conexión con la base de datos. Revisa tu internet.';
      default:
        return 'No se pudieron guardar los cambios (${e.code}).';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildEncabezado(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: BusCard(
                        padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSeccion('Datos de contacto'),
                            const SizedBox(height: 12),
                            BusInputBox(
                              controller: _fullName,
                              label: 'Nombre completo',
                              icon: Icons.person_rounded,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 12),
                            BusInputBox(
                              controller: _phone,
                              label: 'Número de teléfono',
                              icon: Icons.call_rounded,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) =>
                                  _isLoading ? null : _guardar(),
                            ),
                            const SizedBox(height: 20),
                            BusPrimaryButton(
                              label: 'Guardar cambios',
                              icon: Icons.save_rounded,
                              loading: _isLoading,
                              onPressed: _guardar,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEncabezado(BuildContext context) {
    return BusHeader(
      title: 'Editar información',
      subtitle: 'Actualiza tus datos de contacto',
      titleSize: 21,
      fullBleed: true,
      leading: BusIconButton(
        icon: Icons.arrow_back_rounded,
        tooltip: 'Volver',
        onTap: () => Navigator.of(context).maybePop(),
      ),
      trailing: const BusIconBadge(
        icon: Icons.edit_rounded,
        size: 46,
        color: Colors.white,
      ),
    );
  }

  Widget _buildSeccion(String texto) {
    return Row(
      children: [
        Container(
          width: 5,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            style: busText(size: 14, weight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
