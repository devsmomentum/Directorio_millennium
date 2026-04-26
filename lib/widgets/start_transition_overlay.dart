import 'package:flutter/material.dart';

/// Overlay de 3 segundos que se muestra al presionar COMENZAR:
///   - El logo "viaja" de la esquina superior derecha al centro.
///   - Crece hasta ocupar gran parte de la pantalla.
///   - El fondo se oscurece a negro.
/// Al finalizar invoca [onComplete] para que el caller navegue.
class StartTransitionOverlay extends StatefulWidget {
  final String logoUrl;
  final VoidCallback onComplete;
  final Duration duration;

  /// Altura del logo en la posición inicial (debe coincidir con la del Home).
  final double startLogoHeight;

  /// Multiplicador de tamaño final (relativo a [startLogoHeight]).
  /// Por defecto 6× → ~600px de alto en la mayoría de pantallas.
  final double endScale;

  /// Alineación del logo al inicio. Debe aproximarse a la posición real
  /// que ocupa el logo en el Home (esquina superior derecha).
  final Alignment startAlignment;

  const StartTransitionOverlay({
    super.key,
    required this.logoUrl,
    required this.onComplete,
    this.duration = const Duration(seconds: 3),
    this.startLogoHeight = 100.0,
    this.endScale = 6.0,
    this.startAlignment = const Alignment(0.92, -0.92),
  });

  @override
  State<StartTransitionOverlay> createState() => _StartTransitionOverlayState();
}

class _StartTransitionOverlayState extends State<StartTransitionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _bgOpacity;
  late final Animation<Alignment> _alignment;
  late final Animation<double> _scale;
  late final Animation<double> _glow;

  bool _completedDispatched = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    // Fondo a negro: dispara temprano y termina antes que el logo,
    // para que el logo brille sobre el negro al final.
    _bgOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.65, curve: Curves.easeIn),
    );

    // Trayectoria del logo: arranca con un pequeño retardo para que el
    // negro empiece a invadir antes (sensación cinematográfica).
    _alignment = AlignmentTween(
      begin: widget.startAlignment,
      end: Alignment.center,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.10, 0.85, curve: Curves.easeInOutCubic),
      ),
    );

    // Escala: crecimiento marcado con curva expoOut para impacto.
    _scale = Tween<double>(begin: 1.0, end: widget.endScale).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.10, 0.95, curve: Curves.easeOutCubic),
      ),
    );

    // Halo/glow: aparece al final para reforzar la entrada del logo.
    _glow = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.55, 1.0, curve: Curves.easeOut),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_completedDispatched) {
        _completedDispatched = true;
        widget.onComplete();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // Bloquea cualquier toque durante la animación.
      ignoring: false,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final logoHeight = widget.startLogoHeight * _scale.value;
          return Stack(
            fit: StackFit.expand,
            children: [
              // Fondo que se ennegrece progresivamente.
              ColoredBox(
                color: Colors.black.withValues(alpha: _bgOpacity.value),
              ),
              // Halo radial detrás del logo (aparece sobre el final).
              Align(
                alignment: _alignment.value,
                child: Container(
                  width: logoHeight * 1.6,
                  height: logoHeight * 1.6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.18 * _glow.value),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 1.0],
                    ),
                  ),
                ),
              ),
              // Logo animado.
              Align(
                alignment: _alignment.value,
                child: Image.network(
                  widget.logoUrl,
                  height: logoHeight,
                  fit: BoxFit.contain,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
