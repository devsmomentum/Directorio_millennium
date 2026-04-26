import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/flash_coupon.dart';
import 'claim_coupon_form.dart';

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
      barrierDismissible: false,
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

  Future<void> _onClaim() async {
    if (_isExpired) return;

    // Pausamos el ticker mientras el usuario llena el formulario:
    // la urgencia ya cumplió su propósito al hacer clic en Reclamar.
    _ticker?.cancel();

    final claimed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ClaimCouponForm(coupon: widget.coupon),
        fullscreenDialog: true,
      ),
    );

    if (!mounted) return;
    if (claimed == true) {
      Navigator.of(context).pop();
    } else {
      setState(() => _remaining = Duration.zero);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondsLeft = _remaining.inSeconds +
        (_remaining.inMilliseconds % 1000 > 0 ? 1 : 0);
    final progress = _remaining.inMilliseconds /
        widget.countdown.inMilliseconds.clamp(1, 1 << 31);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.flash_on, color: Colors.amber, size: 28),
                  const SizedBox(width: 6),
                  Text(
                    '¡Flash Coupon!',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (widget.coupon.imageUrl != null &&
                  widget.coupon.imageUrl!.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    widget.coupon.imageUrl!,
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                widget.coupon.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (widget.coupon.priceUsd > 0) ...[
                const SizedBox(height: 6),
                Text(
                  'Valor: \$${widget.coupon.priceUsd.toStringAsFixed(2)}',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: widget.coupon.qrPayload,
                  size: 140,
                  version: QrVersions.auto,
                ),
              ),
              const SizedBox(height: 18),
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 84,
                    height: 84,
                    child: CircularProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      strokeWidth: 6,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(
                        _isExpired ? Colors.grey : Colors.redAccent,
                      ),
                    ),
                  ),
                  Text(
                    _isExpired ? '0' : '$secondsLeft',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ScarcityBanner(remaining: widget.coupon.amountAvailable),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isExpired ? null : _onClaim,
                  icon: Icon(_isExpired ? Icons.lock_clock : Icons.local_offer),
                  label: Text(_isExpired ? 'Tiempo agotado' : 'Reclamar cupón'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor:
                        _isExpired ? Colors.grey : Colors.redAccent,
                  ),
                ),
              ),
              if (_isExpired) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ],
            ],
          ),
        ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: (critical ? Colors.red : Colors.orange).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: critical ? Colors.red : Colors.orange.shade800,
          ),
          const SizedBox(width: 6),
          Text(
            'Solo quedan $remaining cupones disponibles',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: critical ? Colors.red : Colors.orange.shade900,
            ),
          ),
        ],
      ),
    );
  }
}
