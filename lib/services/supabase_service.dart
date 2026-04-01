import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/map_node.dart';
import '../models/map_edge.dart';
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
}
