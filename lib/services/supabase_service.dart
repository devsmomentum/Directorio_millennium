import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/map_node.dart';
import '../models/map_edge.dart';
import '../models/map_route.dart';
import '../models/map_polygon.dart';
import '../models/store.dart';

class SupabaseService {
  final _supabase = Supabase.instance.client;

  // PostgREST aplica por defecto un tope de 1000 filas por .select(). Para
  // tablas de grafo (nodes/edges) esto rompe la navegación silenciosamente:
  // si faltan nodos, sus aristas se descartan como huérfanas y el pathfinder
  // no puede conectar origen y destino. Subimos el tope explícitamente.
  static const int _graphFetchLimit = 10000;

  Future<List<Store>> getStores() async {
    final response = await _supabase
        .from('stores')
        .select()
        .limit(_graphFetchLimit);
    return response.map((json) => Store.fromJson(json)).toList();
  }

  Future<List<MapNode>> getMapNodes() async {
    final response = await _supabase
        .from('map_nodes')
        .select()
        .limit(_graphFetchLimit);
    final nodes = response.map((json) => MapNode.fromJson(json)).toList();
    debugPrint('[SupabaseService] map_nodes cargados: ${nodes.length}');
    return nodes;
  }

  Future<List<MapEdge>> getMapEdges() async {
    final response = await _supabase
        .from('map_edges')
        .select()
        .limit(_graphFetchLimit);
    final edges = response.map((json) => MapEdge.fromJson(json)).toList();
    debugPrint('[SupabaseService] map_edges cargados: ${edges.length}');
    return edges;
  }

  Future<List<MapRoute>> getMapRoutes() async {
    final response = await _supabase
        .from('map_routes')
        .select()
        .limit(_graphFetchLimit);
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
    final response = await _supabase
        .from('map_polygons')
        .select()
        .limit(_graphFetchLimit);
    return response.map((json) => MapPolygon.fromJson(json)).toList();
  }
}
