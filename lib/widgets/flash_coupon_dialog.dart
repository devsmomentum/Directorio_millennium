import 'dart:async';

import 'package:flutter/material.dart';

import '../models/flash_coupon.dart';
import '../theme/app_theme.dart';

class FlashCouponDialog extends StatefulWidget {
  final FlashCoupon coupon;
  final Duration countdown;

  const FlashCouponDialog({
    super.key,
    required this.coupon,
    this.countdown = const Duration(seconds: 20),
  });

  static Future<void> show(BuildContext context, FlashCoupon coupon) {
    return showDialog(
      context: context,
      // barrierDismissible en false asegura que el usuario no pueda cerrar
      // el diálogo tocando el fondo, obligando a interactuar con el widget.
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => FlashCouponDialog(coupon: coupon),
    );
  }

  @override
  State<FlashCouponDialog> createState() => _FlashCouponDialogState();
}

class _FlashCouponDialogState extends State<FlashCouponDialog> {
  Timer? _ticker;
  late DateTime _deadline;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _deadline = DateTime.now().add(widget.countdown);
    _remaining = widget.countdown;
    _ticker = Timer.periodic(const Duration(milliseconds: 100), _onTick);
  }

  void _onTick(Timer timer) {
    final left = _deadline.difference(DateTime.now());
    if (left <= Duration.zero) {
      timer.cancel();
      if (!mounted) return;
      setState(() => _remaining = Duration.zero);
    } else {
      if (!mounted) return;
      setState(() => _remaining = left);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }

  bool get _isExpired => _remaining <= Duration.zero;

  @override
  Widget build(BuildContext context) {
    final secondsLeft = _remaining.inSeconds +
        (_remaining.inMilliseconds % 1000 > 0 ? 1 : 0);
    final progress = _remaining.inMilliseconds /
        widget.countdown.inMilliseconds.clamp(1, 1 << 31);

    final countdownColor = _isExpired
        ? Colors.white24
        : (progress < 0.3 ? Colors.redAccent : AppColors.primary);

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Gradient header bar
            _GradientHeader(
              onClose: () => Navigator.of(context).pop(),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.coupon.imageUrl != null &&
                        widget.coupon.imageUrl!.isNotEmpty) ...[
                      // --- INICIO DE LA IMAGEN MODIFICADA ---
                      Center(
                        child: Container(
                          width: 100, // Tamaño validado para el contenedor
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.white, // Fondo blanco asegurado
                            shape: BoxShape.circle, // Contenedor redondo
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias, // Encapsula los bordes
                          child: Padding(
                            padding: const EdgeInsets.all(8.0), // Espacio para que el logo respire
                            child: Image.network(
                              widget.coupon.imageUrl!,
                              fit: BoxFit.contain, // Evita la distorsión del logo
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ),
                      // --- FIN DE LA IMAGEN MODIFICADA ---
                      const SizedBox(height: 16),
                    ],
                    Text(
                      widget.coupon.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // "Canje sin costo" badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.secondary.withValues(alpha: 0.4)),
                      ),
                      child: const Text(
                        'CANJE SIN COSTO',
                        style: TextStyle(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Photo instruction
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.photo_camera_outlined,
                            color: AppColors.primary,
                            size: 26,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Tómale una foto a este cupón y preséntala en la tienda para canjearlo.',
                              style: TextStyle(
                                color: AppColors.textPrimary
                                    .withValues(alpha: 0.95),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Countdown
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 72,
                          height: 72,
                          child: CircularProgressIndicator(
                            value: progress.clamp(0.0, 1.0),
                            strokeWidth: 5,
                            backgroundColor: AppColors.subtleBorder,
                            valueColor:
                                AlwaysStoppedAnimation(countdownColor),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _isExpired ? '0' : '$secondsLeft',
                              style: TextStyle(
                                color: countdownColor,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'seg',
                              style: TextStyle(
                                color: countdownColor.withValues(alpha: 0.7),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _ScarcityBanner(remaining: widget.coupon.amountAvailable),
                    if (_isExpired) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.lock_clock, size: 18),
                          label: const Text('Tiempo agotado'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white38,
                            side: const BorderSide(color: Colors.white12),
                            padding:
                                const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientHeader extends StatelessWidget {
  final VoidCallback onClose;
  const _GradientHeader({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.flash_on, color: Colors.white, size: 22),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '¡Flash Coupon!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 20, color: Colors.white70),
            padding: EdgeInsets.zero,
            tooltip: 'Cerrar sin reclamar',
          ),
        ],
      ),
    );
  }
}

class _ScarcityBanner extends StatelessWidget {
  final int remaining;
  const _ScarcityBanner({required this.remaining});

  @override
  Widget build(BuildContext context) {
    final critical = remaining <= 10;
    final color = critical ? Colors.redAccent : AppColors.warning;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Solo quedan $remaining cupones disponibles',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}