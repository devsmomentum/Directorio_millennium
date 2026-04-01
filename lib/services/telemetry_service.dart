import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TelemetryService {
  static final TelemetryService _instance = TelemetryService._internal();
  factory TelemetryService() => _instance;
  TelemetryService._internal();

  final _supabase = Supabase.instance.client;
  Timer? _pingTimer;

  void start() {
    _pingTimer?.cancel();
    // Enviar latido inmediatamente y luego cada 1 minuto
    _sendPing();
    _pingTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _sendPing();
    });
  }

  Future<void> _sendPing() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentKioskId = prefs.getString('kiosk_id');

      if (currentKioskId == null)
        return; // Si no está vinculado, no envía latido

      await _supabase
          .from('kiosks')
          .update({
            'status': 'online',
            'last_ping': DateTime.now().toIso8601String(),
          })
          .eq('id', currentKioskId);

      print('💚 Ping de telemetría enviado (Kiosco $currentKioskId)');
    } catch (e) {
      print('❌ Error en telemetría: $e');
    }
  }

  void stop() {
    _pingTimer?.cancel();
  }
}
