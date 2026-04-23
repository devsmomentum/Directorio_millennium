import 'dart:async';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Widget que muestra una cuenta regresiva de 10 segundos antes de que
/// el timeout de inactividad expulse al usuario de vuelta al home.
///
/// Al tocar la pantalla (capturado por el [Listener] padre en MainLayout),
/// se llama [onDismiss] para reiniciar el conteo completo.
class InactivityWarning extends StatefulWidget {
  /// Segundos restantes del countdown (se cuenta internamente desde este valor).
  final int countdownSeconds;

  /// Callback para cuando el usuario toca la pantalla (reiniciar timeout).
  final VoidCallback onDismiss;

  /// Callback para cuando el countdown llega a 0 (ejecutar la inactividad).
  final VoidCallback onTimeout;

  const InactivityWarning({
    Key? key,
    this.countdownSeconds = 10,
    required this.onDismiss,
    required this.onTimeout,
  }) : super(key: key);

  @override
  State<InactivityWarning> createState() => _InactivityWarningState();
}

class _InactivityWarningState extends State<InactivityWarning>
    with SingleTickerProviderStateMixin {
  late int _remaining;
  Timer? _timer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _remaining = widget.countdownSeconds;

    // Animación de pulso para el icono
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Iniciar countdown
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _remaining--;
      });
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Al tocar en cualquier parte del overlay, reiniciamos
      onTap: widget.onDismiss,
      onPanDown: (_) => widget.onDismiss(),
      child: Container(
        color: Colors.black.withAlpha(180),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 60),
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 48),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: AppColors.primary.withAlpha(80),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withAlpha(30),
                  blurRadius: 40,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icono animado con pulso
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.touch_app_rounded,
                      size: 36,
                      color: AppColors.warning,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Texto principal
                const Text(
                  '¿Sigues ahí?',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),

                const Text(
                  'La pantalla volverá al inicio por inactividad',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondaryMuted,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),

                // Countdown visual
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _remaining <= 3
                          ? AppColors.error
                          : AppColors.primary,
                      width: 3,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$_remaining',
                      style: TextStyle(
                        color: _remaining <= 3
                            ? AppColors.error
                            : AppColors.primary,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Botón para quedarse
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: widget.onDismiss,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'TOCA PARA CONTINUAR',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
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
}
