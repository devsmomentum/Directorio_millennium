import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/map_edge.dart';
import '../models/map_node.dart';
import 'node_world_mapping.dart';

/// Grafo de navegación sobre los nodos del centro comercial. Expone dos
/// algoritmos: Dijkstra (ruta garantizada óptima) y A* (óptima si la
/// heurística no sobreestima — aquí usamos distancia euclídea que cumple esa
/// condición para pesos en la misma unidad). El resultado siempre es una
/// `List<MapNode>` del origen al destino; si no hay ruta devuelve `[]`.
class Pathfinder {
  final List<MapNode> nodes;
  final List<MapEdge> edges;

  final Map<String, MapNode> _nodeIndex;
  final Map<String, List<_Adjacency>> _adjacency;

  Pathfinder({required this.nodes, required this.edges})
      : _nodeIndex = {for (final n in nodes) _normalizeId(n.id): n},
        _adjacency = _buildAdjacency(nodes, edges);

  /// Los IDs vienen de Supabase como UUIDs en minúsculas, pero normalizamos
  /// (trim + lowercase) para evitar que un espacio accidental o una diferencia
  /// de casing en alguna arista produzca aristas "huérfanas" fantasmas.
  static String _normalizeId(String id) => id.trim().toLowerCase();

  static Map<String, List<_Adjacency>> _buildAdjacency(
    List<MapNode> nodes,
    List<MapEdge> edges,
  ) {
    final adj = <String, List<_Adjacency>>{
      for (final n in nodes) _normalizeId(n.id): <_Adjacency>[],
    };
    int orphanCount = 0;
    for (final e in edges) {
      final aId = _normalizeId(e.nodeAId);
      final bId = _normalizeId(e.nodeBId);
      final a = adj[aId];
      final b = adj[bId];
      if (a == null || b == null) {
        orphanCount++;
        continue; // arista referencia a nodo ausente
      }
      a.add(_Adjacency(bId, e.distanceWeight));
      // Aristas direccionales (escaleras mecánicas, rampas one-way) sólo
      // se transitan a→b. Las bidireccionales también agregan b→a.
      if (!e.directional) {
        b.add(_Adjacency(aId, e.distanceWeight));
      }
    }
    debugPrint(
      '[Pathfinder] Grafo construido: nodos=${nodes.length} '
      'aristas=${edges.length} (huérfanas descartadas=$orphanCount)',
    );
    if (orphanCount > 0) {
      debugPrint(
        '[Pathfinder] ⚠ Hay $orphanCount aristas huérfanas. '
        'Verifica que map_nodes y map_edges estén cargados completos '
        '(¿límite de 1000 filas de PostgREST?).',
      );
    }
    return adj;
  }

  int get nodeCount => _nodeIndex.length;
  int get adjacencyCount => _adjacency.length;

  bool hasNode(String id) => _nodeIndex.containsKey(_normalizeId(id));

  /// Devuelve la cantidad de vecinos directos de un nodo. Útil para diagnosticar
  /// por qué un nodo no tiene ruta (si el grado es 0, nunca puede conectarse).
  int neighborCount(String id) =>
      _adjacency[_normalizeId(id)]?.length ?? 0;

  /// IDs de los vecinos directos de un nodo. Solo para logging diagnóstico.
  List<String> neighborsOf(String id) {
    final list = _adjacency[_normalizeId(id)];
    if (list == null) return const [];
    return list.map((e) => e.nodeId).toList(growable: false);
  }

  /// Tamaño del componente conexo al que pertenece `id`. Si `id` y el destino
  /// están en componentes distintos, no puede existir ruta.
  Set<String> connectedComponent(String id) {
    final start = _normalizeId(id);
    if (!_adjacency.containsKey(start)) return const {};
    final visited = <String>{start};
    final stack = <String>[start];
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      for (final edge in _adjacency[current] ?? const <_Adjacency>[]) {
        if (visited.add(edge.nodeId)) {
          stack.add(edge.nodeId);
        }
      }
    }
    return visited;
  }

  /// Emite logs detallados explicando por qué no hay ruta entre dos nodos:
  /// grado de cada nodo, tamaño del componente conexo de cada uno, y si están
  /// o no en el mismo componente.
  void _logWhyNoRoute(String startId, String targetId) {
    final start = _normalizeId(startId);
    final target = _normalizeId(targetId);
    final startDeg = _adjacency[start]?.length ?? 0;
    final targetDeg = _adjacency[target]?.length ?? 0;
    debugPrint(
      '[Pathfinder][diag] Grado de nodos: '
      'start=$start deg=$startDeg | target=$target deg=$targetDeg',
    );
    if (startDeg == 0) {
      debugPrint(
        '[Pathfinder][diag] ⚠ El nodo de ORIGEN ($start) no tiene aristas. '
        'Revisa map_edges: no hay ninguna fila con node_a_id o node_b_id = $start.',
      );
    } else {
      debugPrint(
        '[Pathfinder][diag] Vecinos de ORIGEN ($start): '
        '${_adjacency[start]!.take(8).map((a) => a.nodeId).join(", ")}'
        '${startDeg > 8 ? " …" : ""}',
      );
    }
    if (targetDeg == 0) {
      debugPrint(
        '[Pathfinder][diag] ⚠ El nodo DESTINO ($target) no tiene aristas. '
        'Revisa map_edges: no hay ninguna fila con node_a_id o node_b_id = $target.',
      );
    } else {
      debugPrint(
        '[Pathfinder][diag] Vecinos de DESTINO ($target): '
        '${_adjacency[target]!.take(8).map((a) => a.nodeId).join(", ")}'
        '${targetDeg > 8 ? " …" : ""}',
      );
    }
    if (startDeg == 0 || targetDeg == 0) return;

    final startComp = connectedComponent(start);
    final inSameComp = startComp.contains(target);
    debugPrint(
      '[Pathfinder][diag] Componente conexo de ORIGEN: '
      '${startComp.length}/${_nodeIndex.length} nodos alcanzables.',
    );
    if (inSameComp) {
      debugPrint(
        '[Pathfinder][diag] ⚠ Origen y destino están en el MISMO componente '
        'pero el algoritmo no reconstruyó la ruta. Posible bug en _reconstructPath '
        'o pesos negativos/NaN en aristas.',
      );
    } else {
      final targetComp = connectedComponent(target);
      debugPrint(
        '[Pathfinder][diag] Componente conexo de DESTINO: '
        '${targetComp.length}/${_nodeIndex.length} nodos alcanzables.',
      );
      debugPrint(
        '[Pathfinder][diag] ⚠ Origen y destino están en componentes DISTINTOS. '
        'Faltan aristas que unan ambas islas del grafo. '
        'Muestra del componente de ORIGEN (hasta 5): '
        '${startComp.take(5).join(", ")}. '
        'Muestra del componente de DESTINO (hasta 5): '
        '${targetComp.take(5).join(", ")}.',
      );
    }
  }

  /// Dijkstra clásico. Mantenido por compatibilidad con `lib/screens/res.dart`.
  /// Devuelve `[]` si no hay ruta.
  List<MapNode> findShortestPath(String startId, String targetId) {
    final start = _normalizeId(startId);
    final target = _normalizeId(targetId);
    if (start == target) {
      final node = _nodeIndex[start];
      return node == null ? const [] : [node];
    }
    if (!_nodeIndex.containsKey(start) ||
        !_nodeIndex.containsKey(target)) {
      debugPrint(
        '[Pathfinder] IDs no presentes en el grafo: '
        'start=$start(${_nodeIndex.containsKey(start)}) '
        'target=$target(${_nodeIndex.containsKey(target)})',
      );
      return const [];
    }

    final distances = <String, double>{
      for (final id in _nodeIndex.keys) id: double.infinity,
    };
    final previous = <String, String?>{
      for (final id in _nodeIndex.keys) id: null,
    };
    distances[start] = 0.0;

    final queue = HeapPriorityQueue<_Visit>(
      (a, b) => a.distance.compareTo(b.distance),
    )..add(_Visit(start, 0.0));

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (current.distance > (distances[current.nodeId] ?? double.infinity)) {
        continue; // entrada obsoleta
      }
      if (current.nodeId == target) break;

      for (final edge in _adjacency[current.nodeId] ?? const <_Adjacency>[]) {
        final newDist = current.distance + edge.weight;
        if (newDist < (distances[edge.nodeId] ?? double.infinity)) {
          distances[edge.nodeId] = newDist;
          previous[edge.nodeId] = current.nodeId;
          queue.add(_Visit(edge.nodeId, newDist));
        }
      }
    }

    final path = _reconstructPath(previous, start, target);
    if (path.isEmpty) _logWhyNoRoute(start, target);
    return path;
  }

  /// A* con heurística euclídea sobre (x, y, z_height). Útil cuando el grafo
  /// crece: explora menos nodos que Dijkstra conservando optimalidad.
  List<MapNode> findShortestPathAStar(String startId, String targetId) {
    final startN = _normalizeId(startId);
    final targetN = _normalizeId(targetId);
    if (startN == targetN) {
      final node = _nodeIndex[startN];
      return node == null ? const [] : [node];
    }
    final start = _nodeIndex[startN];
    final goal = _nodeIndex[targetN];
    if (start == null || goal == null) {
      debugPrint(
        '[Pathfinder] A*: IDs no presentes en el grafo. '
        'start=$startN(${start != null}) target=$targetN(${goal != null}). '
        'Total nodos en índice: ${_nodeIndex.length}.',
      );
      return const [];
    }

    final gScore = <String, double>{
      for (final id in _nodeIndex.keys) id: double.infinity,
    };
    final previous = <String, String?>{
      for (final id in _nodeIndex.keys) id: null,
    };
    gScore[startN] = 0.0;

    final open = HeapPriorityQueue<_Visit>(
      (a, b) => a.distance.compareTo(b.distance),
    )..add(_Visit(startN, _heuristic(start, goal)));

    while (open.isNotEmpty) {
      final current = open.removeFirst();
      if (current.nodeId == targetN) break;

      final currentG = gScore[current.nodeId];
      if (currentG == null) continue;

      for (final edge in _adjacency[current.nodeId] ?? const <_Adjacency>[]) {
        final neighbor = _nodeIndex[edge.nodeId];
        if (neighbor == null) continue;
        final tentativeG = currentG + edge.weight;
        final prevG = gScore[edge.nodeId] ?? double.infinity;
        if (tentativeG < prevG) {
          gScore[edge.nodeId] = tentativeG;
          previous[edge.nodeId] = current.nodeId;
          final f = tentativeG + _heuristic(neighbor, goal);
          open.add(_Visit(edge.nodeId, f));
        }
      }
    }

    final path = _reconstructPath(previous, startN, targetN);
    if (path.isEmpty) _logWhyNoRoute(startN, targetN);
    return path;
  }

  /// Atajo: encuentra la ruta con A* y la devuelve como lista de waypoints
  /// listos para serializar a JSON (ver `NodeWorldMapping.toWaypoint`).
  List<Map<String, dynamic>> findRouteAsWaypoints(
    String startId,
    String targetId, {
    NodeWorldMapping mapping = NodeWorldMapping.identity,
  }) {
    final path = findShortestPathAStar(startId, targetId);
    return path.map(mapping.toWaypoint).toList(growable: false);
  }

  List<MapNode> _reconstructPath(
    Map<String, String?> previous,
    String startId,
    String targetId,
  ) {
    if (previous[targetId] == null && startId != targetId) return const [];

    final path = <MapNode>[];
    String? cursor = targetId;
    while (cursor != null) {
      final node = _nodeIndex[cursor];
      if (node == null) return const [];
      path.insert(0, node);
      cursor = previous[cursor];
    }
    return path;
  }

  static double _heuristic(MapNode a, MapNode b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    final dz = a.zHeight - b.zHeight;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }
}

class _Adjacency {
  final String nodeId;
  final double weight;
  const _Adjacency(this.nodeId, this.weight);
}

class _Visit {
  final String nodeId;
  final double distance;
  const _Visit(this.nodeId, this.distance);
}

/// Heap binario mínimo implementado en Dart puro (evita dependencia a
/// `package:collection` solo por `HeapPriorityQueue`). Interfaz compatible
/// con el tipo homónimo de esa librería.
class HeapPriorityQueue<T> {
  final Comparator<T> _compare;
  final List<T> _heap = [];

  HeapPriorityQueue(this._compare);

  bool get isNotEmpty => _heap.isNotEmpty;
  int get length => _heap.length;

  void add(T value) {
    _heap.add(value);
    _siftUp(_heap.length - 1);
  }

  T removeFirst() {
    if (_heap.isEmpty) {
      throw StateError('HeapPriorityQueue vacía');
    }
    final top = _heap.first;
    final last = _heap.removeLast();
    if (_heap.isNotEmpty) {
      _heap[0] = last;
      _siftDown(0);
    }
    return top;
  }

  void _siftUp(int index) {
    while (index > 0) {
      final parent = (index - 1) >> 1;
      if (_compare(_heap[index], _heap[parent]) < 0) {
        final tmp = _heap[index];
        _heap[index] = _heap[parent];
        _heap[parent] = tmp;
        index = parent;
      } else {
        break;
      }
    }
  }

  void _siftDown(int index) {
    final n = _heap.length;
    while (true) {
      final left = index * 2 + 1;
      final right = left + 1;
      var smallest = index;
      if (left < n && _compare(_heap[left], _heap[smallest]) < 0) {
        smallest = left;
      }
      if (right < n && _compare(_heap[right], _heap[smallest]) < 0) {
        smallest = right;
      }
      if (smallest == index) break;
      final tmp = _heap[index];
      _heap[index] = _heap[smallest];
      _heap[smallest] = tmp;
      index = smallest;
    }
  }
}
