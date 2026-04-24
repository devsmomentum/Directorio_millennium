import 'package:flutter/foundation.dart';

import '../models/map_edge.dart';
import '../models/map_node.dart';
import '../models/store.dart';
import '../utils/node_world_mapping.dart';
import '../utils/pathfinder.dart';

/// Resultado de un cálculo de ruta para el avatar.
class AvatarRoute {
  final List<MapNode> path;
  final List<Map<String, dynamic>> waypoints;
  final bool crossesFloors;
  final String? errorMessage;

  const AvatarRoute({
    required this.path,
    required this.waypoints,
    required this.crossesFloors,
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
    int? currentFloorLevel,
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
    int? currentFloorLevel,
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

    // Si estamos en un piso concreto, solo animamos los waypoints de ese piso.
    // Estrategia: recorrer desde el inicio, tomar nodos mientras floorLevel
    // coincida; al primer cambio cortamos. De ese modo el avatar termina en la
    // escalera/elevador de salida del piso actual.
    List<MapNode> floorSegment;
    if (currentFloorLevel != null && crossesFloors) {
      floorSegment = <MapNode>[];
      for (final node in path) {
        if (node.floorLevel == currentFloorLevel) {
          floorSegment.add(node);
        } else if (floorSegment.isNotEmpty) {
          break; // cortamos en el primer nodo del siguiente piso
        }
      }
      if (floorSegment.length < 2) {
        // La ruta sale del piso inmediatamente → mostramos solo el kiosko.
        floorSegment = path.take(1).toList();
      }
    } else {
      floorSegment = path;
    }

    final waypoints = floorSegment.map(mapping.toWaypoint).toList(growable: false);

    return AvatarRoute(
      path: floorSegment,
      waypoints: waypoints,
      crossesFloors: crossesFloors,
    );
  }
}
