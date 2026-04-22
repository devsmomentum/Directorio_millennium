import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';

class CurrencyService {
  // Patrón Singleton para usar la misma instancia en toda la app
  static final CurrencyService _instance = CurrencyService._internal();
  factory CurrencyService() => _instance;
  CurrencyService._internal();

  Future<double> getBcvRate() async {
    final box = Hive.box('kiosk_cache');

    try {
      // Intentamos obtener la tasa en vivo
      final response = await http
          .get(
            Uri.parse(
              'https://pydolarvenezuela-api.vercel.app/api/v1/dollar/page?page=bcv',
            ),
          )
          .timeout(
            const Duration(seconds: 10),
          ); // Timeout para no dejar la app colgada

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final double rate = data['monitors']['usd']['price'].toDouble();

        // 🚀 GUARDADO SEGURO: Actualizamos la caché con la tasa de hoy
        await box.put('cached_bcv_rate', rate);
        debugPrint('✅ Tasa BCV actualizada desde API: $rate');

        return rate;
      } else {
        throw Exception('Error HTTP: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('⚠️ Error al consultar BCV: $e');

      // 🚀 FALLBACK INTELIGENTE: Si no hay internet, usamos la última tasa real conocida
      final cachedRate = box.get('cached_bcv_rate');
      if (cachedRate != null) {
        debugPrint('🔄 Usando tasa BCV desde la caché de Hive: $cachedRate');
        return cachedRate as double;
      }

      // Solo en el caso extremo de ser el primer encendido histórico del kiosco sin internet
      debugPrint(
        '❌ Sin internet y sin caché previa. Retornando tasa de emergencia.',
      );
      return 36.25;
    }
  }
}
