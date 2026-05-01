// lib/screens/services_screen.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/analytics_service.dart'; // 🚀 Importamos el rastreador
import '../services/currency_service.dart';
import '../widgets/screen_ad_banners.dart';
import '../theme/app_theme.dart';
import 'parking_payment_screen.dart';

class ServiceModel {
  final String id;
  final String title;
  final String provider;
  final String description;
  final String imageUrl;
  final bool isActive;

  ServiceModel({
    required this.id,
    required this.title,
    required this.provider,
    required this.description,
    required this.imageUrl,
    required this.isActive,
  });

  factory ServiceModel.fromJson(Map<String, dynamic> json) {
    return ServiceModel(
      id: json['id'],
      title: json['title'],
      provider: json['provider'],
      description: json['description'] ?? '',
      imageUrl: json['image_url'],
      isActive: json['is_active'] ?? true,
    );
  }
}

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => ServicesScreenState();
}

class ServicesScreenState extends State<ServicesScreen> {
  final _client = Supabase.instance.client;
  List<ServiceModel> _services = [];
  bool _isLoading = true;
  RealtimeChannel? _subscription;
  double _bcvRate = 36.25; // 🚀 Tasa por defecto
  bool _showParkingPayment = false;
  bool _showCinesPayment = false;    
  bool _showRecargasPayment = false; 
  String? _paymentUrl;

  /// Indica si hay un pago activo (WebView abierta). Usado por MainLayout
  /// para evitar que el timeout de inactividad expulse al usuario.
  bool get isPaymentActive => _paymentUrl != null;

  void resetState() {
    if (mounted) {
      setState(() {
        _showParkingPayment = false;
        _showCinesPayment = false;
        _showRecargasPayment = false;
        _paymentUrl = null;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchBcvRate(); // 🚀 Cargamos la tasa al abrir la pantalla
    _fetchServices();
    _setupRealtime();
  }

  @override
  void dispose() {
    if (_subscription != null) _client.removeChannel(_subscription!);
    super.dispose();
  }

  // 🚀 NUEVO: Obtener tasa oficial del BCV
  Future<void> _fetchBcvRate() async {
    final rate = await CurrencyService().getBcvRate();
    if (mounted) {
      setState(() {
        _bcvRate = rate;
      });
    }
  }

  void _setupRealtime() {
    _subscription = _client
        .channel('public:services')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'services',
          callback: (payload) {
            if (mounted) _fetchServices();
          },
        )
        .subscribe();
  }

  Future<void> _fetchServices() async {
    try {
      final data = await _client
          .from('services')
          .select('*')
          .eq('is_active', true) // Solo muestra los activos
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _services = (data as List)
              .map((s) => ServiceModel.fromJson(s))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 🚀 MODAL PREPARADO PARA EL PATRÓN MODULAR DE PAGOS FUTURO
  void _showServiceModal(ServiceModel service) {
    // 🚀 Registramos que alguien se interesó en este servicio
    AnalyticsService().logEvent(
      eventType: 'view_modal',
      module: 'service',
      itemName: service.title,
      itemId: service.id,
    );

    final TextEditingController contractController = TextEditingController();
    bool isProcessing = false;

    showDialog(
      context: context,
      barrierDismissible: false, // Evita cerrar tocando afuera mientras procesa
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
                    color: const Color(0xFFFF007A).withOpacity(0.5),
                    width: 2,
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  // Logo
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.network(
                        service.imageUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.image_not_supported,
                          color: Colors.black26,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    service.provider.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFFFF007A),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    service.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    service.description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                  ),

                  const SizedBox(height: 30),

                  // Input para Identificador del cliente
                  TextField(
                    controller: contractController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Número de contrato / Teléfono',
                      hintStyle: const TextStyle(color: Colors.white30),
                      prefixIcon: const Icon(
                        Icons.badge_outlined,
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
                        borderSide: const BorderSide(color: Color(0xFFFF007A)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 25),

                  LayoutBuilder(
                    builder: (context, constraints) {
                      final submitButton = ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF007A),
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        onPressed: isProcessing
                            ? null
                            : () async {
                                if (contractController.text.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Ingresa el número de contrato',
                                      ),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                  return;
                                }

                                setModalState(() => isProcessing = true);

                                try {
                                  // 1. Simulamos una pequeña espera conectando al "Proveedor"
                                  await Future.delayed(
                                    const Duration(seconds: 2),
                                  );

                                  // 2. Simulamos una deuda a pagar fija para el MVP
                                  final double amountUsd = 15.00;

                                  // 3. Buscamos el ID real del Kiosco
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  final currentKioskId =
                                      prefs.getString('kiosk_id') ??
                                      'K2-NO-VINCULADO';

                                  // 🚀 4. REGISTRAMOS LA TRANSACCIÓN FINANCIERA EN SUPABASE
                                  await _client.from('transactions').insert({
                                    'transaction_type': 'service',
                                    'item_id': service.id,
                                    'item_name': 'Pago: ${service.title}',
                                    'amount_usd': amountUsd,
                                    'exchange_rate': _bcvRate,
                                    'amount_bs': (amountUsd * _bcvRate),
                                    'payment_method': 'simulated',
                                    'status': 'completed',
                                    'user_email':
                                        'contrato_${contractController.text}@terminal.com',
                                    'kiosk_id': currentKioskId,
                                  });

                                  if (mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(
                                      context,
                                    ).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '✅ Pago de \$${amountUsd.toStringAsFixed(2)} procesado con éxito',
                                        ),
                                        backgroundColor: Colors.green,
                                        duration: const Duration(seconds: 4),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (!mounted) return;
                                  setModalState(() => isProcessing = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Error procesando pago: $e',
                                      ),
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
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'CONSULTAR Y PAGAR',
                                style: TextStyle(
                                  color: Colors.white,
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

  void _showComingSoonModal() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppColors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: AppColors.primary.withOpacity(0.5),
                width: 2,
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
              const Icon(
                Icons.hourglass_empty_rounded,
                color: AppColors.primary,
                size: 60,
              ),
              const SizedBox(height: 20),
              const Text(
                'PRÓXIMAMENTE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Estamos trabajando para habilitar este servicio muy pronto.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondaryMuted,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'ENTENDIDO',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCinesCard(ServiceModel srv) {
    return GestureDetector(
      onTap: _showComingSoonModal,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          gradient: const LinearGradient(
            colors: [Color(0xFFFF007A), Color(0xFFFF5E00)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.chipBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.theaters, color: AppColors.textPrimary, size: 24),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'CINES UNIDOS',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Compra de Entradas y Combos',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.chipBackground,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chevron_right, color: AppColors.textPrimary, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '¿A qué hora es la función? Compra aquí tus boletos en segundos',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.chipBackground,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.subtleBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.touch_app, color: AppColors.textPrimary, size: 14),
                  SizedBox(width: 6),
                  Text(
                    'TOCA PARA ACCEDER',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstacionamientoCard(ServiceModel srv) {
    return GestureDetector(
      onTap: () => setState(() => _showParkingPayment = true),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.secondary.withOpacity(0.5), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: AppColors.secondary.withOpacity(0.1),
              blurRadius: 15,
              spreadRadius: -5,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.chipBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.directions_car, color: AppColors.secondary, size: 24),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'ESTACIONAMIENTO',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Pago de Ticket de Parking',
                        style: TextStyle(
                          color: AppColors.textSecondaryMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.chipBackground,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chevron_right, color: AppColors.textSecondaryMuted, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Ingresa tu placa y calcula tu tarifa al instante',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.chipBackground,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.secondary.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.touch_app, color: AppColors.secondary, size: 14),
                  SizedBox(width: 6),
                  Text(
                    'TOCA PARA ACCEDER',
                    style: TextStyle(
                      color: AppColors.secondary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecargasCard(ServiceModel srv) {
    return GestureDetector(
      onTap: _showComingSoonModal,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary.withOpacity(0.5), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.1),
              blurRadius: 15,
              spreadRadius: -5,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.chipBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.flash_on, color: AppColors.warning, size: 24),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'RECARGAS Y SERVICIOS',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'CORPOELEC - CANTV - Hidrocapital - Recargas',
                        style: TextStyle(
                          color: AppColors.textSecondaryMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.chipBackground,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chevron_right, color: AppColors.textSecondaryMuted, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Paga tus servicios y realiza recargas telefónicas aquí mismo',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.chipBackground,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.touch_app, color: AppColors.primary, size: 14),
                  SizedBox(width: 6),
                  Text(
                    'TOCA PARA ACCEDER',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomPaymentSection() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.chipBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.secondary.withOpacity(0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.contactless, color: AppColors.secondary, size: 22),
                SizedBox(height: 2),
                Text('NFC', style: TextStyle(color: AppColors.secondary, fontSize: 9, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.chipBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.qr_code_scanner, color: AppColors.primary, size: 22),
                SizedBox(height: 2),
                Text('QR', style: TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Pague aquí con QR o NFC',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Acerque su dispositivo o escanee el código QR en la ranura de pago para finalizar su transacción de forma rápida y segura',
                  style: TextStyle(
                    color: AppColors.textSecondaryMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

@override
  Widget build(BuildContext context) {
    final cinesService = _services.firstWhere(
      (s) => s.title.toLowerCase().contains('cine') || s.provider.toLowerCase().contains('cine'),
      orElse: () => ServiceModel(id: 'cine', title: 'Cines Unidos', provider: 'Cines Unidos', description: 'Compra de Entradas y Combos', imageUrl: '', isActive: true),
    );
    final estService = _services.firstWhere(
      (s) => s.title.toLowerCase().contains('estacionamiento') || s.provider.toLowerCase().contains('estacionamiento'),
      orElse: () => ServiceModel(id: 'estacionamiento', title: 'Estacionamiento', provider: 'Parking', description: 'Pago de Ticket de Parking', imageUrl: '', isActive: true),
    );
    final recargasService = _services.firstWhere(
      (s) => s.title.toLowerCase().contains('recarga') || s.provider.toLowerCase().contains('recarga') || s.title.toLowerCase().contains('servicio'),
      orElse: () => ServiceModel(id: 'recargas', title: 'Recargas y Servicios', provider: 'Servicios', description: 'CORPOELEC - CANTV - Hidrocapital - Recargas', imageUrl: '', isActive: true),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: ScreenAdBanners(
        showTop: false,
        showBottom: false,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 0.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 15),
                // FIX: Added the spread operator `...[` and closed it with `],`
                if (!_showParkingPayment && !_showCinesPayment && !_showRecargasPayment) ...[
                  const Text(
                    '¿En qué te podemos ayudar?',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Selecciona un módulo para comenzar',
                    style: TextStyle(
                      color: AppColors.textSecondaryMuted,
                      fontSize: 14,
                    ),
                  ),
                ], 
                const SizedBox(height: 15),
                Expanded(
                  child: Stack(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: _showParkingPayment
                            ? ParkingPaymentScreen(
                                embedInLayout: true,
                                onBack: () => setState(() {
                                  _showParkingPayment = false;
                                  _paymentUrl = null;
                                }),
                                onOpenPaymentUrl: (url) => setState(() {
                                  _paymentUrl = url;
                                }),
                                onPaymentConfirmed: () {
                                  // El webhook confirmó el pago via Realtime.
                                  // Cerramos la WebView automáticamente.
                                  if (mounted) {
                                    setState(() => _paymentUrl = null);
                                  }
                                },
                              )
                            : ListView(
                                key: const ValueKey('services-list'),
                                physics: const BouncingScrollPhysics(),
                                children: [
                                  _buildCinesCard(cinesService),
                                  const SizedBox(height: 10),
                                  _buildEstacionamientoCard(estService),
                                  const SizedBox(height: 10),
                                  _buildRecargasCard(recargasService),
                                  const SizedBox(height: 15),
                                  // _buildBottomPaymentSection(),
                                  // const SizedBox(height: 15),
                                ],
                              ),
                      ),
                      if (_paymentUrl != null)
                        _PaymentWebViewOverlay(
                          url: _paymentUrl!,
                          onClose: () => setState(() => _paymentUrl = null),
                        ),
                    ],
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
class _PaymentWebViewOverlay extends StatelessWidget {
  const _PaymentWebViewOverlay({
    required this.url,
    required this.onClose,
  });

  final String url;
  final VoidCallback onClose;

  bool get _supportsPaymentWebView {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return true;
      case TargetPlatform.linux:
      case TargetPlatform.windows:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    InAppWebViewController? controller;
    final uri = Uri.tryParse(url);
    return Positioned.fill(
      child: Container(
        color: theme.scaffoldBackgroundColor,
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Pago en linea',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                  child: _supportsPaymentWebView
                      ? InAppWebView(
                          initialUrlRequest: URLRequest(url: WebUri(url)),
                          initialSettings: InAppWebViewSettings(
                            javaScriptEnabled: true,
                            cacheEnabled: true,
                            mediaPlaybackRequiresUserGesture: false,
                            domStorageEnabled: true,
                            supportMultipleWindows: true,
                            javaScriptCanOpenWindowsAutomatically: true,
                            useShouldOverrideUrlLoading: true,
                            thirdPartyCookiesEnabled: true,
                            sharedCookiesEnabled: true,
                          ),
                          onWebViewCreated: (created) => controller = created,
                          shouldOverrideUrlLoading:
                              (controller, navigationAction) async {
                            final uri = navigationAction.request.url;
                            if (uri == null) {
                              return NavigationActionPolicy.ALLOW;
                            }
                            // Some gateways open a new window/tab; keep navigation in-app.
                            if (navigationAction.isForMainFrame != true) {
                              await controller.loadUrl(
                                urlRequest: URLRequest(url: uri),
                              );
                              return NavigationActionPolicy.CANCEL;
                            }
                            return NavigationActionPolicy.ALLOW;
                          },
                          onCreateWindow:
                              (controller, createWindowRequest) async {
                            final uri = createWindowRequest.request.url;
                            if (uri != null) {
                              await controller.loadUrl(
                                urlRequest: URLRequest(url: uri),
                              );
                            }
                            return true;
                          },
                          onLoadError: (controller, url, code, message) {
                            debugPrint(
                              '[PaymentWebView] load error code=$code message=$message url=$url',
                            );
                          },
                          onLoadHttpError:
                              (controller, url, statusCode, description) {
                            debugPrint(
                              '[PaymentWebView] http error status=$statusCode url=$url desc=$description',
                            );
                          },
                        )
                      : _PaymentWebViewFallback(
                          url: url,
                          uri: uri,
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentWebViewFallback extends StatelessWidget {
  const _PaymentWebViewFallback({
    required this.url,
    required this.uri,
  });

  final String url;
  final Uri? uri;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      color: theme.colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.open_in_browser,
                    size: 42,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Este dispositivo no soporta WebView para pagos.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Abre el enlace en tu navegador para completar el pago.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: uri == null
                          ? null
                          : () async {
                              final ok = await launchUrl(
                                uri!,
                                mode: LaunchMode.externalApplication,
                              );
                              if (!ok && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('No se pudo abrir el navegador.'),
                                  ),
                                );
                              }
                            },
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Abrir en navegador'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: url));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('Enlace copiado al portapapeles.'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copiar enlace'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
