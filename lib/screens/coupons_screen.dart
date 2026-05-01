// lib/screens/coupons_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/coupon_service.dart';
import '../widgets/screen_ad_banners.dart';

class Coupon {
  final String id;
  final String title;
  final String storeName;
  final String imageUrl;
  final String code;
  final int amountAvailable;

  Coupon({
    required this.id,
    required this.title,
    required this.storeName,
    required this.imageUrl,
    required this.code,
    required this.amountAvailable,
  });

  factory Coupon.fromJson(Map<String, dynamic> json) {
    final stores = json['stores'];
    final storeName = stores is Map<String, dynamic>
        ? (stores['name'] as String?) ?? ''
        : '';
    return Coupon(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? 'Cupón Promocional',
      storeName: storeName,
      imageUrl: (json['image_url'] as String?) ?? '',
      code: (json['code'] as String?) ?? '',
      amountAvailable: (json['amount_available'] as num?)?.toInt() ?? 0,
    );
  }
}

class CouponsScreen extends StatefulWidget {
  const CouponsScreen({super.key});

  @override
  State<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends State<CouponsScreen> {
  final _client = Supabase.instance.client;
  List<Coupon> _allCoupons = [];
  bool _isLoading = true;

  RealtimeChannel? _subscription;

  @override
  void initState() {
    super.initState();
    _fetchCoupons();
    _setupRealtime();
  }

  @override
  void dispose() {
    if (_subscription != null) {
      _client.removeChannel(_subscription!);
    }
    super.dispose();
  }

  void _setupRealtime() {
    _subscription = _client
        .channel('public:coupons')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'coupons',
          callback: (payload) {
            if (mounted) {
              _fetchCoupons();
            }
          },
        )
        .subscribe();
  }

  Future<void> _fetchCoupons() async {
    try {
      final data = await _client
          .from('coupons')
          .select('*, stores(name)')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _allCoupons = (data as List).map((c) => Coupon.fromJson(c)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando cupones: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Modal único: pide correo y reclama el cupón vía Edge Function.
  void _showClaimModal(Coupon coupon) {
    final TextEditingController emailController = TextEditingController();
    bool isProcessing = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Dialog(
            backgroundColor: const Color(0xFF111111),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450),
              child: Container(
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: const Color(0xFF00E5FF).withOpacity(0.4),
                    width: 2,
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  const Icon(
                    Icons.local_activity_outlined,
                    color: Color(0xFF00E5FF),
                    size: 70,
                  ),
                  const SizedBox(height: 15),
                  Text(
                    coupon.storeName.isEmpty
                        ? 'CUPÓN'
                        : coupon.storeName.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF00E5FF),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    coupon.title,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Ingresa tu correo electrónico y te enviaremos el código de canjeo para que lo presentes en la tienda.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                  const SizedBox(height: 25),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'ejemplo@correo.com',
                      hintStyle: const TextStyle(color: Colors.white30),
                      prefixIcon: const Icon(
                        Icons.email_outlined,
                        color: Colors.white54,
                      ),
                      filled: true,
                      fillColor: Colors.black,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: const BorderSide(color: Colors.white10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: const BorderSide(
                          color: Color(0xFF00E5FF),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final submitButton = ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        onPressed: isProcessing
                            ? null
                            : () async {
                                final email = emailController.text.trim();
                                if (email.isEmpty) return;
                                setModalState(() => isProcessing = true);

                                try {
                                  await CouponService.instance
                                      .claimCatalogCoupon(
                                    couponId: coupon.id,
                                    email: email,
                                  );

                                  if (!mounted) return;
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '✅ ¡Cupón enviado a $email! Revisa tu bandeja.',
                                      ),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                } on ClaimCouponException catch (e) {
                                  if (!mounted) return;
                                  setModalState(() => isProcessing = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(e.message),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                } catch (e) {
                                  if (!mounted) return;
                                  setModalState(() => isProcessing = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error reclamando: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              },
                        child: isProcessing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.black,
                                  strokeWidth: 3,
                                ),
                              )
                            : const Text(
                                'RECLAMAR CUPÓN',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                      );

                      final cancelButton = TextButton(
                        onPressed: isProcessing
                            ? null
                            : () => Navigator.pop(context),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(color: Colors.white54),
                        ),
                      );

                      if (constraints.maxWidth < 360) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            submitButton,
                            const SizedBox(height: 12),
                            cancelButton,
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: submitButton),
                          const SizedBox(width: 15),
                          cancelButton,
                        ],
                      );
                    },
                  ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: ScreenAdBanners(
        showTop: false,
        showBottom: false,
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF00E5FF),
                      ),
                    )
                  : _allCoupons.isEmpty
                  ? const Center(
                      child: Text(
                        'No hay cupones disponibles.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        int crossAxisCount = 3;
                        double childAspectRatio = 0.72;

                        if (width < 900) {
                          crossAxisCount = 2;
                        }
                        if (width < 520) {
                          crossAxisCount = 1;
                          childAspectRatio = 0.85;
                        }

                        return GridView.builder(
                          padding: EdgeInsets.all(width < 520 ? 16 : 20),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: 20,
                            mainAxisSpacing: 20,
                            childAspectRatio: childAspectRatio,
                          ),
                          itemCount: _allCoupons.length,
                          itemBuilder: (context, index) {
                            final coupon = _allCoupons[index];
                            return _buildCouponCard(coupon);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCouponCard(Coupon coupon) {
    final bool isAgotado = coupon.amountAvailable <= 0;

    return GestureDetector(
      onTap: isAgotado ? null : () => _showClaimModal(coupon),
      child: Stack(
        children: [
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                color: const Color(0xFF00E5FF).withOpacity(0.1),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00E5FF).withOpacity(0.05),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              children: [
                Expanded(
                  flex: 3,
                  child: Stack(
                    children: [
                      Image.network(
                        coupon.imageUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.black26,
                          child: const Icon(
                            Icons.confirmation_number,
                            size: 50,
                            color: Colors.white24,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF007A),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'STOCK: ${coupon.amountAvailable}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'GRATIS',
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 8.0,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          coupon.storeName.toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFF00E5FF),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Flexible(
                          child: Text(
                            coupon.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'TOCA PARA RECLAMAR',
                          style: TextStyle(
                            color: Color(0xFF00E5FF),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (isAgotado)
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Center(
                child: Transform.rotate(
                  angle: -0.3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.redAccent, width: 4),
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.black87,
                    ),
                    child: const Text(
                      'AGOTADO',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
