import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AnalyticsService {
  final _supabase = Supabase.instance.client;

  // 🚀 Método genérico para registrar cualquier interacción en el Kiosco
  Future<void> logEvent({
    required String eventType,
    required String module,
    required String itemName,
    String? itemId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentKioskId = prefs.getString('kiosk_id') ?? 'K2-NO-VINCULADO';

      // 1. Construimos el paquete de datos dinámicamente
      final Map<String, dynamic> insertData = {
        'kiosk_id': currentKioskId,
        'event_type': eventType,
        'module': module,
        'item_name': itemName,
        // 🚀 Envolvemos event_data en un JSON seguro para evitar crasheos de JSONB
        'event_data': {'store_name': itemName},
      };

      // 2. Solo enviamos el ID si existe (enviar "null" a veces crashea Supabase)
      if (itemId != null && itemId.isNotEmpty) {
        insertData['item_id'] = itemId;
      }

      // 3. Disparamos a la base de datos
      await _supabase.from('analytics_events').insert({
        'kiosk_id': currentKioskId,
        'event_type': eventType,
        'module': module,
        'item_name': itemName,
        'event_data': {'name': itemName}, // 🚀 Se envía como objeto para JSONB
      });

      print('✅ ÉXITO: Analítica guardada -> [$module] $itemName');
    } catch (e) {
      // 🚀 AHORA SÍ VEREMOS EL ERROR EXACTO SI SUPABASE LO RECHAZA
      print('❌ ERROR FATAL GUARDANDO ANALÍTICA: $e');
    }
  }
}
