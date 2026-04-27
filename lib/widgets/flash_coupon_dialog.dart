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
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.flash_on, color: Colors.amber, size: 26),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '¡Flash Coupon!',
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    right: 0,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 20),
                      padding: EdgeInsets.zero,
                      color: Colors.grey.shade500,
                      tooltip: 'Cerrar sin reclamar',
                    ),
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
                    height: 100,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Text(
                widget.coupon.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Canje sin costo',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: widget.coupon.qrPayload,
                  size: 120,
                  version: QrVersions.auto,
                ),
              ),
              const SizedBox(height: 14),
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 72,
                    height: 72,
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
              const SizedBox(height: 10),
              _ScarcityBanner(remaining: widget.coupon.amountAvailable),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isExpired ? null : _onClaim,
                  icon: Icon(_isExpired ? Icons.lock_clock : Icons.local_offer),
                  label: Text(_isExpired ? 'Tiempo agotado' : 'Reclamar cupón'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor:
                        _isExpired ? Colors.grey : Colors.redAccent,
                  ),
                ),
              ),
              if (_isExpired) ...[
                const SizedBox(height: 6),
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
          Flexible(
            child: Text(
              'Solo quedan $remaining cupones disponibles',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: critical ? Colors.red : Colors.orange.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
