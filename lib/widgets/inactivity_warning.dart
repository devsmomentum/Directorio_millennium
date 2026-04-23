import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../theme/app_theme.dart';

/// Overlay minimalista de cuenta regresiva por inactividad.
///
/// Muestra un fondo con desenfoque (BackdropFilter), un número de cuenta
/// regresiva grande en el centro, un icono de "tap" animado y el texto
/// "Toque la pantalla para continuar".
///
/// **Cero botones**: cualquier toque en cualquier parte del overlay
/// invoca [onDismiss] para reiniciar el timer de inactividad completo.
///
/// Al llegar a 0, invoca [onTimeout] para ejecutar la lógica de retorno al
/// inicio (pop a la pantalla de publicidad).
class InactivityWarning extends StatefulWidget {
  /// Segundos desde los que arranca la cuenta regresiva (default 10).
  final int countdownSeconds;

  /// Callback para cuando el usuario toca la pantalla (reiniciar timeout).
  final VoidCallback onDismiss;

  /// Callback para cuando el countdown llega a 0 (ejecutar la inactividad).
  final VoidCallback onTimeout;

  const InactivityWarning({
    super.key,
    this.countdownSeconds = 10,
    required this.onDismiss,
    required this.onTimeout,
  });

  @override
  State<InactivityWarning> createState() => _InactivityWarningState();
}

class _InactivityWarningState extends State<InactivityWarning>
    with TickerProviderStateMixin {
  late int _remaining;
  Timer? _timer;

  // Controlador del pulso del ícono de tap
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Controlador de la animación de entrada (fade + scale)
  late AnimationController _entryController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  // Controlador de la animación del número cuando cambia
  late AnimationController _digitBounceController;
  late Animation<double> _digitScaleAnimation;

  @override
  void initState() {
    super.initState();
    _remaining = widget.countdownSeconds;

    // ── Animación de entrada (overlay aparece con fade-in + scale-up) ──
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOut,
    );
    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.easeOutBack),
    );
    _entryController.forward();

    // ── Animación de pulso continuo para el ícono de tap ──
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // ── Animación de "bounce" cuando el dígito cambia ──
    _digitBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _digitScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.25), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.25, end: 0.9), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 30),
    ]).animate(
      CurvedAnimation(
        parent: _digitBounceController,
        curve: Curves.easeInOut,
      ),
    );

    // ── Timer de cuenta regresiva (1 tick/segundo) ──
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _remaining--;
      });
      // Trigger del bounce cada segundo
      _digitBounceController.forward(from: 0);

      if (_remaining <= 0) {
        timer.cancel();
        widget.onTimeout();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    _entryController.dispose();
    _digitBounceController.dispose();
    super.dispose();
  }

  /// Color del número según los segundos restantes.
  Color get _countdownColor {
    if (_remaining <= 3) return AppColors.error;
    if (_remaining <= 5) return AppColors.warning;
    return AppColors.textPrimary;
  }

  /// Progreso circular (1.0 → 0.0) para el arco exterior.
  double get _progress => _remaining / widget.countdownSeconds;

  @override
  Widget build(BuildContext context) {
    return PointerInterceptor(
      child: GestureDetector(
        // Cualquier toque en cualquier parte del overlay reinicia el timeout
        behavior: HitTestBehavior.opaque,
        onTap: widget.onDismiss,
        onPanDown: (_) => widget.onDismiss(),
        child: Material(
          type: MaterialType.transparency,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Stack(
              fit: StackFit.expand,
              children: [
              // ── Capa 1: Desenfoque de fondo (BackdropFilter) ──
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  color: Colors.black.withAlpha(180),
                ),
              ),

              // ── Capa 2: Contenido centrado ──
              ScaleTransition(
                scale: _scaleAnimation,
                child: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // ── Contador circular grande ──
                            _buildCountdownCircle(),

                            const SizedBox(height: 28),

                            // ── Icono de tap con pulso ──
                            ScaleTransition(
                              scale: _pulseAnimation,
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.textPrimary.withAlpha(15),
                                  border: Border.all(
                                    color: AppColors.textPrimary.withAlpha(40),
                                    width: 1.5,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.touch_app_rounded,
                                  size: 28,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // ── Texto instructivo ──
                            Text(
                              'Toque la pantalla para continuar',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textPrimary.withAlpha(200),
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),

                            const SizedBox(height: 8),

                            Text(
                              'La pantalla volverá al inicio por inactividad',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textSecondaryMuted.withAlpha(180),
                                fontSize: 13,
                                height: 1.4,
                              ),
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
      ),
    );
  }

  /// Círculo grande con arco de progreso + número en el centro.
  Widget _buildCountdownCircle() {
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Arco de progreso (track de fondo)
          SizedBox(
            width: 120,
            height: 120,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: 4,
              valueColor: AlwaysStoppedAnimation<Color>(
                AppColors.textPrimary.withAlpha(25),
              ),
            ),
          ),
          // Arco de progreso (valor actual)
          SizedBox(
            width: 120,
            height: 120,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: _progress, end: _progress),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeInOut,
              builder: (context, value, _) {
                return CircularProgressIndicator(
                  value: value,
                  strokeWidth: 4,
                  strokeCap: StrokeCap.round,
                  valueColor: AlwaysStoppedAnimation<Color>(_countdownColor),
                );
              },
            ),
          ),
          // Número central animado
          AnimatedBuilder(
            animation: _digitScaleAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _digitScaleAnimation.value,
                child: child,
              );
            },
            child: Text(
              '$_remaining',
              style: TextStyle(
                color: _countdownColor,
                fontSize: 56,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
