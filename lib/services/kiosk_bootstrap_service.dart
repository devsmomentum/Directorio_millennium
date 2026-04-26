import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Garantiza que la app tenga un `kiosk_id` válido en SharedPreferences
/// antes de levantar la UI principal. La estrategia es:
///   1. Si ya hay `kiosk_id` guardado → respetar.
///   2. Buscar kiosco por `hardware_id` físico (sólo Android tiene uno real).
///   3. Fallback: kiosco de la planta baja (`floor_level = 'RG'`) — útil
///      cuando se está debuggeando en laptop/desktop, donde no hay hardware
///      Sunmi y nunca habrá match real.
class KioskBootstrapService {
  KioskBootstrapService._();

  static const String _kPrefKioskId = 'kiosk_id';
  static const String _kPrefHardwareId = 'hardware_id';
  static const String _kFallbackFloor = 'RG';

  /// Llamar una sola vez al arranque de la app (después de Supabase.initialize).
  static Future<void> ensureKioskBound() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_kPrefKioskId);
    if (existing != null && existing.isNotEmpty) {
      debugPrint('[KioskBootstrap] kiosk_id ya estaba: $existing');
      return;
    }

    final client = Supabase.instance.client;

    // 1. Intento por hardware físico (Sunmi/Android).
    final hardwareId = await _readHardwareId();
    if (hardwareId != null && hardwareId.isNotEmpty) {
      try {
        final byHw = await client
            .from('kiosks')
            .select('id, name')
            .eq('hardware_id', hardwareId)
            .maybeSingle();
        if (byHw != null) {
          await prefs.setString(_kPrefKioskId, byHw['id'] as String);
          await prefs.setString(_kPrefHardwareId, hardwareId);
          debugPrint(
            '[KioskBootstrap] match por hardware: ${byHw['name']} (${byHw['id']})',
          );
          return;
        }
      } catch (e) {
        debugPrint('[KioskBootstrap] error consultando por hardware: $e');
      }
    }

    // 2. Fallback: cualquier kiosco en planta baja (RG).
    final fallback = await _findKioskOnFloor(client, _kFallbackFloor);
    if (fallback != null) {
      await prefs.setString(_kPrefKioskId, fallback['id'] as String);
      debugPrint(
        '[KioskBootstrap] usando kiosco RG por defecto (debug/laptop): '
        '${fallback['name']} (${fallback['id']})',
      );
      return;
    }

    debugPrint(
      '[KioskBootstrap] ⚠ no se encontró kiosco RG; la app correrá sin kiosk_id',
    );
  }

  static Future<String?> _readHardwareId() async {
    if (kIsWeb) return null;
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        return info.id;
      }
    } catch (e) {
      debugPrint('[KioskBootstrap] error leyendo hardware id: $e');
    }
    return null;
  }

  /// Busca un kiosco asociado a la planta dada. Intenta por la columna
  /// `floor_level` directa de `kiosks`; si no existe en ese registro,
  /// cae a buscar por `node_id` → `map_nodes.floor_level`.
  static Future<Map<String, dynamic>?> _findKioskOnFloor(
    SupabaseClient client,
    String floor,
  ) async {
    // a) Match directo en `kiosks.floor_level`.
    try {
      final direct = await client
          .from('kiosks')
          .select('id, name, floor_level, node_id')
          .eq('floor_level', floor)
          .order('name')
          .limit(1)
          .maybeSingle();
      if (direct != null) return direct;
    } catch (e) {
      debugPrint('[KioskBootstrap] floor_level directo falló: $e');
    }

    // b) Vía nodos del mapa: trae todos los nodos del piso y busca un
    //    kiosco cuyo node_id esté en ese conjunto.
    try {
      final nodes = await client
          .from('map_nodes')
          .select('id')
          .eq('floor_level', floor);
      final nodeIds = (nodes as List)
          .map((n) => (n as Map)['id'] as String)
          .toList();
      if (nodeIds.isEmpty) return null;

      final byNode = await client
          .from('kiosks')
          .select('id, name, node_id')
          .inFilter('node_id', nodeIds)
          .order('name')
          .limit(1)
          .maybeSingle();
      return byNode;
    } catch (e) {
      debugPrint('[KioskBootstrap] búsqueda por nodos falló: $e');
      return null;
    }
  }
}
