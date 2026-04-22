import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as p;

class AdCacheManager {
  static final AdCacheManager _instance = AdCacheManager._internal();
  factory AdCacheManager() => _instance;
  AdCacheManager._internal();

  final _supabase = Supabase.instance.client;
  Timer? _syncTimer;

  // Lista de anuncios listos y descargados en el disco duro
  List<Map<String, dynamic>> _cachedAds = [];
  List<Map<String, dynamic>> get cachedAds => _cachedAds;

  // Avisador para la pantalla de inicio
  Function? onCacheUpdated;

  Future<void> init() async {
    await _loadLocalCache(); // Carga lo que ya está en el disco al arrancar
    _startBackgroundSync(); // Inicia la vigilancia
  }

  Future<void> _loadLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    final adsJson = prefs.getString('cached_ads');
    if (adsJson != null) {
      _cachedAds = List<Map<String, dynamic>>.from(json.decode(adsJson));
      print('📂 Caché local cargado: ${_cachedAds.length} anuncios listos.');
    }
  }

  void _startBackgroundSync() {
    _syncAds(); // Primera revisión al encender
    // Vigilar cada 10 minutos
    _syncTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      _syncAds();
    });
  }

  Future<void> _syncAds() async {
    try {
      print('🔄 Espía Underground: Buscando campañas nuevas...');
      final response = await _supabase
          .from('ad_campaigns')
          .select()
          .eq('is_active', true)
          .order('plan_type', ascending: true);

      final serverAds = List<Map<String, dynamic>>.from(response);
      final dir = await getApplicationDocumentsDirectory();
      List<Map<String, dynamic>> readyAds = [];

      // 1. Descargar lo nuevo sin interrumpir la UI
      for (var ad in serverAds) {
        final url = ad['media_url'] as String;
        // Creamos un nombre de archivo único basado en la URL
        final fileName = url.split('/').last.split('?').first;
        final localPath = p.join(dir.path, fileName);
        final file = File(localPath);

        // Si no existe, lo descargamos
        if (!await file.exists()) {
          print('⬇️ Descargando archivo pesado: $fileName');
          final request = await HttpClient().getUrl(Uri.parse(url));
          final response = await request.close();
          await response.pipe(file.openWrite());
          print('✅ Descarga completada: $fileName');
        }

        // Le inyectamos la ruta del disco duro a la data del anuncio
        ad['local_path'] = localPath;
        readyAds.add(ad);
      }

      // 2. Limpieza (Borrar del disco los que eliminaste en el panel Admin)
      for (var oldAd in _cachedAds) {
        final stillExists = readyAds.any((newAd) => newAd['id'] == oldAd['id']);
        if (!stillExists && oldAd['local_path'] != null) {
          final oldFile = File(oldAd['local_path']);
          if (await oldFile.exists()) {
            await oldFile.delete();
            print('🗑️ Basura eliminada del disco: ${oldAd['brand_name']}');
          }
        }
      }

      // 3. Guardar el nuevo estado y avisar a la pantalla
      _cachedAds = readyAds;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_ads', json.encode(_cachedAds));

      if (onCacheUpdated != null) {
        onCacheUpdated!(); // 🔔 Toca la campana para que la UI se actualice
      }
    } catch (e) {
      print('❌ Error en el espía underground: $e');
    }
  }
}
