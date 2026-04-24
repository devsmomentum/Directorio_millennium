// lib/screens/coupons_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/currency_service.dart';
import '../widgets/screen_ad_banners.dart';

// Modelo de datos simple
class Coupon {
  final String id;
  final String title;
  final String storeName;
  final String imageUrl;
  final String code;
  final int amountAvailable;
  final double priceUsd;

  Coupon({
    required this.id,
    required this.title,
    required this.storeName,
    required this.imageUrl,
    required this.code,
    required this.amountAvailable,
    required this.priceUsd,
  });

  factory Coupon.fromJson(Map<String, dynamic> json) {
    return Coupon(
      id: json['id'] as String,
      title: json['title'] as String,
      storeName: json['stores']['name'] as String,
      imageUrl: json['image_url'] as String,
      code: json['code'] as String,
      amountAvailable: json['amount_available'] as int,
      priceUsd: (json['price_usd'] as num?)?.toDouble() ?? 0.0,
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
  double _bcvRate = 0.0;

  // 🚀 NUEVO: Canal para escuchar cambios en tiempo real
  RealtimeChannel? _subscription;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _setupRealtime(); // 🚀 Iniciamos la escucha en vivo
  }

  @override
  void dispose() {
    // 🚀 Limpiar la conexión al salir
    if (_subscription != null) {
      _client.removeChannel(_subscription!);
    }
    super.dispose();
  }

  // 🚀 NUEVO: Escuchar cambios en la tabla 'coupons' (Realtime)
  void _setupRealtime() {
    _subscription = _client
        .channel('public:coupons')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'coupons',
          callback: (payload) {
            if (mounted) {
              _fetchCoupons(); // Recarga la lista cuando hay cambios en la BD
            }
          },
        )
        .subscribe();
  }

  Future<void> _fetchData() async {
    // 🚀 Llamamos al servicio centralizado para la tasa
    final rate = await CurrencyService().getBcvRate();
    if (mounted) {
      setState(() {
        _bcvRate = rate;
      });
    }

    // Luego cargamos los cupones
    await _fetchCoupons();
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

  // 🚀 FLUJO 1: MODAL DEL QR PARA PAGAR
  void _showCouponModal(Coupon coupon) {
    final double priceBs = coupon.priceUsd * _bcvRate;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: const Color(0xFF00E5FF).withOpacity(0.3),
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                coupon.storeName.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF00E5FF),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                coupon.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 15,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text(
                      '\$${coupon.priceUsd.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(height: 40, width: 2, color: Colors.white10),
                    Text(
                      'Bs. ${priceBs.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.white, fontSize: 24),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: QrImageView(
                  data: coupon.code,
                  version: QrVersions.auto,
                  size: 200.0,
                  foregroundColor: Colors.black,
                  gapless: false,
                  embeddedImage: const NetworkImage(
                    'https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/mapas/plano_rg.png',
                  ),
                  embeddedImageStyle: const QrEmbeddedImageStyle(
                    size: Size(40, 40),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              const Text(
                "ACERCA TU QR DE PAGO AL LECTOR INFERIOR",
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      icon: const Icon(
                        Icons.qr_code_scanner,
                        color: Colors.black,
                      ),
                      label: const Text(
                        'SIMULAR ESCANEO K2',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _showEmailModal(coupon);
                      },
                    ),
                  ),
                  const SizedBox(width: 15),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white54,
                      size: 30,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🚀 FLUJO 2: MODAL PARA PEDIR CORREO Y DESCONTAR STOCK
  void _showEmailModal(Coupon coupon) {
    final TextEditingController emailController = TextEditingController();
    bool isProcessing = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Dialog(
            backgroundColor: const Color(0xFF111111),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            child: Container(
              width: 450,
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: Colors.greenAccent.withOpacity(0.5),
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: Colors.greenAccent,
                    size: 70,
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    '¡PAGO APROBADO!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Ingresa tu correo electrónico donde te enviaremos el código QR definitivo para canjear en la tienda.',
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
                        borderSide: const BorderSide(color: Colors.greenAccent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.greenAccent,
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          onPressed: isProcessing
                              ? null
                              : () async {
                                  if (emailController.text.isEmpty) return;
                                  setModalState(() => isProcessing = true);

                                  try {
                                    final int newAmount =
                                        coupon.amountAvailable - 1;
                                    await _client
                                        .from('coupons')
                                        .update({'amount_available': newAmount})
                                        .eq('id', coupon.id);

                                    // 🚀 PASO 3: ¡REGISTRAR LA TRANSACCIÓN FINANCIERA! (NUEVO)
                                    await _client.from('transactions').insert({
                                      'transaction_type': 'coupon',
                                      'item_id': coupon.id,
                                      'item_name': coupon.title,
                                      'amount_usd': coupon.priceUsd,
                                      'exchange_rate': _bcvRate,
                                      'amount_bs': (coupon.priceUsd * _bcvRate),
                                      'payment_method': 'simulated',
                                      'status': 'completed',
                                      'user_email': emailController.text,
                                      'kiosk_id':
                                          'K2-01-ENTRADA', // Identificador del Kiosco
                                    });

                                    if (mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '✅ Cupón enviado y pago registrado a ${emailController.text}',
                                          ),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (!mounted) return;
                                    setModalState(() => isProcessing = false);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Error procesando: $e'),
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
                                  'ENVIAR CUPÓN',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      TextButton(
                        onPressed: isProcessing
                            ? null
                            : () => Navigator.pop(context),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    ],
                  ),
                ],
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
                        'No hay ofertas disponibles.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(20),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 20,
                            mainAxisSpacing: 20,
                            childAspectRatio: 0.72,
                          ),
                      itemCount: _allCoupons.length,
                      itemBuilder: (context, index) {
                        final coupon = _allCoupons[index];
                        return _buildCouponCard(coupon);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCouponCard(Coupon coupon) {
    final priceBs = coupon.priceUsd * _bcvRate;
    final bool isAgotado = coupon.amountAvailable <= 0;

    return GestureDetector(
      onTap: isAgotado ? null : () => _showCouponModal(coupon),
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
                          child: Text(
                            '\$${coupon.priceUsd.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
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
                        Text(
                          'Ref: Bs. ${priceBs.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'TOCA PARA COMPRAR',
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
