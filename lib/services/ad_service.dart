import 'package:supabase_flutter/supabase_flutter.dart';

class AdService {
  final _supabase = Supabase.instance.client;

  // Traer todas las campañas activas
  Future<List<Map<String, dynamic>>> getActiveAds() async {
    try {
      final response = await _supabase
          .from('ad_campaigns')
          .select()
          .eq('is_active', true)
          .order(
            'plan_type',
            ascending: true,
          ); // Esto pondrá Diamante primero por orden alfabético

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error cargando publicidad: $e');
      return [];
    }
  }
}
