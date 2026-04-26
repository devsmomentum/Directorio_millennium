import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/flash_coupon.dart';
import '../services/coupon_service.dart';

class ClaimCouponForm extends StatefulWidget {
  final FlashCoupon coupon;
  const ClaimCouponForm({super.key, required this.coupon});

  @override
  State<ClaimCouponForm> createState() => _ClaimCouponFormState();
}

class _ClaimCouponFormState extends State<ClaimCouponForm> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _idDocument = TextEditingController();
  final _email = TextEditingController();

  bool _isLoading = false;

  static final RegExp _emailRegex =
      RegExp(r'^[\w\.\-+]+@[\w\-]+(\.[\w\-]+)+$');

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _idDocument.dispose();
    _email.dispose();
    super.dispose();
  }

  String? _required(String? v, {String field = 'Este campo'}) {
    if (v == null || v.trim().isEmpty) return '$field es obligatorio';
    return null;
  }

  String? _validateEmail(String? v) {
    final base = _required(v, field: 'Correo');
    if (base != null) return base;
    if (!_emailRegex.hasMatch(v!.trim())) return 'Correo no válido';
    return null;
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);

    final payload = ClaimPayload(
      couponId: widget.coupon.id,
      firstName: _firstName.text.trim(),
      lastName: _lastName.text.trim(),
      idDocument: _idDocument.text.trim(),
      email: _email.text.trim(),
    );

    try {
      await CouponService.instance.claimCoupon(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Cupón enviado a tu correo! Revisa tu bandeja.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reclamar Flash Coupon'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.coupon.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (widget.coupon.priceUsd > 0)
                  Text(
                    'Valor: \$${widget.coupon.priceUsd.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _firstName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => _required(v, field: 'Nombre'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _lastName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Apellidos',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => _required(v, field: 'Apellidos'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _idDocument,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(15),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Cédula',
                    prefixIcon: Icon(Icons.credit_card),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => _required(v, field: 'Cédula'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateEmail,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isLoading ? null : _submit,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(
                    _isLoading ? 'Enviando...' : 'Enviar y recibir cupón',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Te enviaremos el cupón al correo. Solo quedan '
                  '${widget.coupon.amountAvailable} disponibles.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
