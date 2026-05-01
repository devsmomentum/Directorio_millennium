import 'package:flutter/foundation.dart';

import '../models/map_edge.dart';
import '../models/map_node.dart';
import '../models/store.dart';
import '../utils/node_world_mapping.dart';
import '../utils/pathfinder.dart';

/// Tramo de ruta dentro de un único piso. La ruta cross-floor es una secuencia
/// de estos: el último nodo de un segmento es el EXIT del conector y el primer
/// nodo del siguiente segmento es el ENTRY en el piso destino.
class FloorSegment {
  final String floorLevel;
  final List<MapNode> nodes;
  final List<Map<String, dynamic>> waypoints;

  const FloorSegment({
    required this.floorLevel,
    required this.nodes,
    required this.waypoints,
  });

  bool get isEmpty => nodes.isEmpty;
}

/// Resultado de un cálculo de ruta para el avatar.
///
/// Compatibilidad: `path` y `waypoints` reflejan el primer segmento (el que se
/// anima en el piso visible al inicio), igual que la versión previa que
/// truncaba al primer cruce. La novedad está en `segments`, que conserva la
/// ruta completa para que el orquestador pueda reproducirla piso por piso.
class AvatarRoute {
  final List<MapNode> path;
  final List<Map<String, dynamic>> waypoints;
  final bool crossesFloors;
  final List<FloorSegment> segments;
  final String? errorMessage;

  const AvatarRoute({
    required this.path,
    required this.waypoints,
    required this.crossesFloors,
    this.segments = const [],
    this.errorMessage,
  });

  bool get isEmpty => path.isEmpty;
  bool get isNotEmpty => path.isNotEmpty;

  static const AvatarRoute empty = AvatarRoute(
    path: [],
    waypoints: [],
    crossesFloors: false,
  );

  factory AvatarRoute.error(String message) {
    return AvatarRoute(
      path: const [],
      waypoints: const [],
      crossesFloors: false,
      errorMessage: message,
    );
  }
}

/// Combina el grafo (`map_nodes` + `map_edges`) con la información del kiosko y
/// la tienda objetivo para producir la ruta 3D del avatar.
///
/// Uso típico:
/// ```dart
/// final service = AvatarNavigationService(
///   nodes: nodes,
///   edges: edges,
///   mapping: NodeWorldMapping.identity,
/// );
/// final route = service.routeFromKioskToStore(
///   kioskNodeId: kiosk['node_id'],
///   store: store,
///   currentFloorLevel: 1,
/// );
/// ```
class AvatarNavigationService {
  final List<MapNode> nodes;
  final List<MapEdge> edges;
  final NodeWorldMapping mapping;
  final Pathfinder _pathfinder;

  AvatarNavigationService({
    required this.nodes,
    required this.edges,
    this.mapping = NodeWorldMapping.identity,
  }) : _pathfinder = Pathfinder(nodes: nodes, edges: edges) {
    // Diagnóstico temporal: confirma que el grafo no esté vacío al construirse.
    debugPrint(
      '[AvatarNav] Grafo inicializado → '
      'nodos=${nodes.length} aristas=${edges.length} '
      '(adyacencias indexadas=${_pathfinder.adjacencyCount})',
    );
    if (nodes.isEmpty || edges.isEmpty) {
      debugPrint(
        '[AvatarNav] ⚠ Grafo vacío o incompleto. '
        'Revisa SupabaseService.getMapNodes / getMapEdges.',
      );
    }
  }

  /// Expuesto para que el caller pueda validar readiness antes de navegar.
  bool get isReady => nodes.isNotEmpty && edges.isNotEmpty;
  int get nodeCount => nodes.length;
  int get edgeCount => edges.length;

  /// Calcula la ruta desde el nodo del kiosko hasta el nodo asociado a la
  /// tienda. Si `currentFloorLevel` se proporciona, recorta la ruta al primer
  /// tramo contenido en ese piso (el avatar sólo camina dentro del piso
  /// visible; el cambio de piso lo manejan escaleras/elevadores en UI).
  AvatarRoute routeFromKioskToStore({
    required String? kioskNodeId,
    required Store store,
    String? currentFloorLevel,
  }) {
    if (kioskNodeId == null || kioskNodeId.isEmpty) {
      return AvatarRoute.error('El kiosko actual no tiene node_id asignado');
    }
    final storeNodeId = store.nodeId;
    if (storeNodeId == null || storeNodeId.isEmpty) {
      return AvatarRoute.error(
        'La tienda "${store.name}" no tiene nodo de mapa asociado',
      );
    }
    return routeBetweenNodes(
      startNodeId: kioskNodeId,
      targetNodeId: storeNodeId,
      currentFloorLevel: currentFloorLevel,
    );
  }

  /// Versión de bajo nivel: ruta entre dos nodos arbitrarios.
  AvatarRoute routeBetweenNodes({
    required String startNodeId,
    required String targetNodeId,
    String? currentFloorLevel,
  }) {
    if (!isReady) {
      debugPrint(
        '[AvatarNav] Grafo no listo (nodes=${nodes.length}, '
        'edges=${edges.length}) — no se puede calcular ruta.',
      );
      return AvatarRoute.error(
        'El mapa aún se está cargando, intenta de nuevo en un segundo',
      );
    }
    if (!_pathfinder.hasNode(startNodeId)) {
      debugPrint(
        '[AvatarNav] Nodo de origen "$startNodeId" no existe en el grafo.',
      );
      return AvatarRoute.error(
        'El nodo del kiosko no existe en el mapa cargado',
      );
    }
    if (!_pathfinder.hasNode(targetNodeId)) {
      debugPrint(
        '[AvatarNav] Nodo destino "$targetNodeId" no existe en el grafo.',
      );
      return AvatarRoute.error(
        'El nodo de la tienda no existe en el mapa cargado',
      );
    }

    final path = _pathfinder.findShortestPathAStar(startNodeId, targetNodeId);

    if (path.isEmpty) {
      debugPrint(
        '[AvatarNav] No se encontró ruta '
        '$startNodeId → $targetNodeId '
        '(nodos=${nodes.length}, aristas=${edges.length}). '
        'Probable causa: grafo desconectado o aristas faltantes.',
      );
      return AvatarRoute.error('No se encontró una ruta hasta la tienda');
    }

    final allFloors = path.map((n) => n.floorLevel).toSet();
    final crossesFloors = allFloors.length > 1;

    // Segmentar la ruta por piso. Cada cambio de floorLevel inicia un nuevo
    // FloorSegment; el último nodo del segmento previo (EXIT del conector) y
    // el primer nodo del siguiente (ENTRY en el piso destino) están unidos en
    // el grafo por una arista is_3d. El orquestador anima cada segmento por
    // separado y entre dos segmentos hace la transición visual de piso.
    final segments = _segmentByFloor(path);

    // Para mantener compatibilidad con los callers existentes, `path` y
    // `waypoints` siguen siendo el primer segmento jugable: el que coincide
    // con el piso visible (currentFloorLevel) si existe, o el inicial.
    FloorSegment first = segments.first;
    if (currentFloorLevel != null) {
      first = segments.firstWhere(
        (s) => s.floorLevel == currentFloorLevel,
        orElse: () => segments.first,
      );
    }

    return AvatarRoute(
      path: first.nodes,
      waypoints: first.waypoints,
      crossesFloors: crossesFloors,
      segments: segments,
    );
  }

  List<FloorSegment> _segmentByFloor(List<MapNode> path) {
    if (path.isEmpty) return const [];
    final out = <FloorSegment>[];
    var currentFloor = path.first.floorLevel;
    var bucket = <MapNode>[path.first];
    for (var i = 1; i < path.length; i++) {
      final node = path[i];
      if (node.floorLevel == currentFloor) {
        bucket.add(node);
      } else {
        out.add(_buildSegment(currentFloor, bucket));
        currentFloor = node.floorLevel;
        bucket = <MapNode>[node];
      }
    }
    out.add(_buildSegment(currentFloor, bucket));
    return out;
  }

  FloorSegment _buildSegment(String floor, List<MapNode> nodes) {
    return FloorSegment(
      floorLevel: floor,
      nodes: List<MapNode>.unmodifiable(nodes),
      waypoints: nodes.map(mapping.toWaypoint).toList(growable: false),
    );
  }
}
