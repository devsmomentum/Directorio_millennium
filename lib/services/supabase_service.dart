import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/map_node.dart';
import '../models/map_edge.dart';
import '../models/map_route.dart';
import '../models/map_polygon.dart';
import '../models/store.dart';

class SupabaseService {
  final _supabase = Supabase.instance.client;

  Future<List<Store>> getStores() async {
    final response = await _supabase.from('stores').select();
    return response.map((json) => Store.fromJson(json)).toList();
  }

  Future<List<MapNode>> getMapNodes() async {
    final response = await _supabase.from('map_nodes').select();
    return response.map((json) => MapNode.fromJson(json)).toList();
  }

  Future<List<MapEdge>> getMapEdges() async {
    final response = await _supabase.from('map_edges').select();
    return response.map((json) => MapEdge.fromJson(json)).toList();
  }

  Future<List<MapRoute>> getMapRoutes() async {
    final response = await _supabase.from('map_routes').select();
    return response.map((json) => MapRoute.fromJson(json)).toList();
  }

  Future<List<Map<String, dynamic>>> getKiosks() async {
    final response = await _supabase.from('kiosks').select();
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>?> getKioskById(String kioskId) async {
    final response = await _supabase
        .from('kiosks')
        .select()
        .eq('id', kioskId)
        .maybeSingle();
    return response;
  }

  Future<List<MapPolygon>> getMapPolygons() async {
    final response = await _supabase.from('map_polygons').select();
    return response.map((json) => MapPolygon.fromJson(json)).toList();
  }
}
