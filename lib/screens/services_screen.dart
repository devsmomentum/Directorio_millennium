// lib/screens/services_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/analytics_service.dart'; // 🚀 Importamos el rastreador
import '../services/currency_service.dart';

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
  const ServicesScreen({Key? key}) : super(key: key);

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  final _client = Supabase.instance.client;
  List<ServiceModel> _services = [];
  bool _isLoading = true;
  RealtimeChannel? _subscription;
  double _bcvRate = 36.25; // 🚀 Tasa por defecto

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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            child: Container(
              width: 450,
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: const Color(0xFFFF007A).withOpacity(0.5),
                  width: 2,
                ),
              ),
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
                      image: DecorationImage(
                        image: NetworkImage(service.imageUrl),
                        fit: BoxFit.contain,
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

                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
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
      appBar: AppBar(
        title: const Text(
          'PAGO DE SERVICIOS',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Text(
                'Tasa BCV: Bs. ${_bcvRate.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Color(0xFFFF007A),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 80,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFF007A), Color(0xFFFF5900)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Center(
              child: Text(
                'SELECCIONA EL SERVICIO A PAGAR',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF007A)),
                  )
                : _services.isEmpty
                ? const Center(
                    child: Text(
                      'No hay servicios disponibles por ahora.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(30),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 30,
                          mainAxisSpacing: 30,
                          childAspectRatio: 1.0,
                        ),
                    itemCount: _services.length,
                    itemBuilder: (context, index) {
                      final srv = _services[index];
                      return GestureDetector(
                        onTap: () => _showServiceModal(srv),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(25),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.05),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 70,
                                height: 70,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(15),
                                  image: DecorationImage(
                                    image: NetworkImage(srv.imageUrl),
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 15),
                              Text(
                                srv.provider,
                                style: const TextStyle(
                                  color: Color(0xFFFF007A),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                child: Text(
                                  srv.title,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
