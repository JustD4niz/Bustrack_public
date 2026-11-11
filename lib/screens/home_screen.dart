import 'package:flutter/material.dart';

import '../main.dart';
import '../widgets/landscape_painter.dart';

/// Panel de control principal de BusTrack, mostrado tras un inicio de
/// sesión exitoso.
///
/// Estructura (de arriba hacia abajo, todo dentro de un único
/// [CustomScrollView] para evitar cualquier overflow):
///   1. Un [SliverAppBar] expandible con el paisaje de fondo y el saludo.
///   2. Una tarjeta destacada de "estado en vivo" del bus.
///   3. Una cuadrícula responsiva de accesos rápidos.
///   4. Una lista de actividad reciente.
///
/// Cada sección entra con una animación de fade + slide escalonada,
/// orquestada por un único [AnimationController] compartido.
class PantallaPrincipalBusTrack extends StatefulWidget {
  const PantallaPrincipalBusTrack({super.key});

  @override
  State<PantallaPrincipalBusTrack> createState() =>
      _PantallaPrincipalBusTrackState();
}

class _PantallaPrincipalBusTrackState extends State<PantallaPrincipalBusTrack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;

  // Datos de ejemplo: en producción vendrían de un repositorio/servicio.
  final List<_AccesoRapido> _accesos = const [
    _AccesoRapido(
      icon: Icons.location_on_rounded,
      label: 'Rastrear bus',
      color: AppColors.primaryDeep,
    ),
    _AccesoRapido(
      icon: Icons.history_rounded,
      label: 'Historial de rutas',
      color: AppColors.primaryLight,
    ),
    _AccesoRapido(
      icon: Icons.notifications_active_rounded,
      label: 'Notificaciones',
      color: AppColors.accentWarmDeep,
    ),
    _AccesoRapido(
      icon: Icons.phone_in_talk_rounded,
      label: 'Contactar conductor',
      color: AppColors.safetyGreenDeep,
    ),
  ];

  final List<_EventoActividad> _actividad = const [
    _EventoActividad(
      icon: Icons.check_circle_rounded,
      color: AppColors.safetyGreen,
      titulo: 'Sofía abordó el bus',
      subtitulo: 'Parada Jacarandá · 6:58 a.m.',
    ),
    _EventoActividad(
      icon: Icons.directions_bus_filled_rounded,
      color: AppColors.primaryDeep,
      titulo: 'Ruta 4 en camino',
      subtitulo: 'Llegada estimada en 12 min',
    ),
    _EventoActividad(
      icon: Icons.info_rounded,
      color: AppColors.accentWarmDeep,
      titulo: 'Cambio de horario mañana',
      subtitulo: 'Salida 15 min más tarde por evento escolar',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  /// Construye un `Interval` distinto por índice, de forma que las
  /// secciones aparezcan en cascada en lugar de todas a la vez.
  Animation<double> _staggeredCurve(int index, {int totalSteps = 6}) {
    final start = (index / totalSteps).clamp(0.0, 0.85);
    final end = (start + 0.35).clamp(0.0, 1.0);
    return CurvedAnimation(
      parent: _entranceController,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
  }

  Widget _staggered({required int index, required Widget child}) {
    final curved = _staggeredCurve(index);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryDeep,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildAppBar(),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _staggered(index: 0, child: _buildEstadoEnVivo()),
                const SizedBox(height: 24),
                _staggered(
                  index: 1,
                  child: _buildTituloSeccion('Accesos rápidos'),
                ),
                const SizedBox(height: 12),
                _staggered(index: 2, child: _buildGridAccesos()),
                const SizedBox(height: 28),
                _staggered(
                  index: 3,
                  child: _buildTituloSeccion('Actividad reciente'),
                ),
                const SizedBox(height: 12),
                _staggered(index: 4, child: _buildListaActividad()),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// Cabecera expandible: el paisaje corporativo sirve de fondo mientras
  /// se despliega el saludo y el acceso a notificaciones.
  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: 200,
      backgroundColor: AppColors.primaryDeep,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedBuilder(
              animation: _entranceController,
              builder: (context, _) => CustomPaint(
                painter: LandscapePainter(
                  animationValue: _entranceController.value,
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.15),
                    AppColors.primaryDeep,
                  ],
                  stops: const [0.3, 1.0],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: _staggered(
                  index: 0,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.accentWarm,
                        child: Text(
                          'MF',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hola, María 👋',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Todo en orden con la ruta de hoy',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildBotonNotificaciones(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotonNotificaciones() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.glassFillDark,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: IconButton(
            icon: const Icon(
              Icons.notifications_none_rounded,
              color: AppColors.textPrimary,
            ),
            onPressed: () {},
          ),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              color: AppColors.accentWarm,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }

  /// Tarjeta destacada con el estado del bus en tiempo real: la pieza
  /// central del dashboard, con jerarquía visual clara (ícono, estado,
  /// ETA) y el verde de "seguridad" para transmitir confianza.
  Widget _buildEstadoEnVivo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.safetyGreen.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.directions_bus_filled_rounded,
              color: AppColors.safetyGreen,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.safetyGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Ruta 4 · En camino',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Llega a la parada Jacarandá en 12 min',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildTituloSeccion(String texto) {
    return Text(
      texto,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  /// Cuadrícula de accesos rápidos. Usa `SliverGridDelegateWithMaxCrossAxisExtent`
  /// (vía `GridView.shrinkWrap`) para que el número de columnas se adapte
  /// solo entre pantallas angostas (móvil) y anchas (tablet/web), sin
  /// necesidad de breakpoints manuales.
  Widget _buildGridAccesos() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _accesos.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 1.15,
      ),
      itemBuilder: (context, index) => _buildTarjetaAcceso(_accesos[index]),
    );
  }

  Widget _buildTarjetaAcceso(_AccesoRapido acceso) {
    return _TarjetaInteractiva(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.glassFillDark,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: acceso.color.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(acceso.icon, color: acceso.color, size: 22),
            ),
            Text(
              acceso.label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListaActividad() {
    return Column(
      children: _actividad
          .map(
            (evento) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildFilaActividad(evento),
            ),
          )
          .toList(),
    );
  }

  Widget _buildFilaActividad(_EventoActividad evento) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.glassFillDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: evento.color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(evento.icon, color: evento.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  evento.titulo,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  evento.subtitulo,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Envoltorio que da a cualquier tarjeta una animación táctil de escala
/// al presionarla, reforzando la sensación de interactividad en todo el
/// dashboard sin repetir la lógica de `GestureDetector` en cada tarjeta.
class _TarjetaInteractiva extends StatefulWidget {
  const _TarjetaInteractiva({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_TarjetaInteractiva> createState() => _TarjetaInteractivaState();
}

class _TarjetaInteractivaState extends State<_TarjetaInteractiva> {
  double _scale = 1.0;

  void _setScale(double value) => setState(() => _scale = value);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setScale(0.96),
      onTapUp: (_) => _setScale(1.0),
      onTapCancel: () => _setScale(1.0),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class _AccesoRapido {
  const _AccesoRapido({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;
}

class _EventoActividad {
  const _EventoActividad({
    required this.icon,
    required this.color,
    required this.titulo,
    required this.subtitulo,
  });

  final IconData icon;
  final Color color;
  final String titulo;
  final String subtitulo;
}
