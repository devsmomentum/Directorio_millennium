import '../models/map_node.dart';
import '../models/map_edge.dart';

class Pathfinder {
  final List<MapNode> nodes;
  final List<MapEdge> edges;

  Pathfinder({required this.nodes, required this.edges});

  List<MapNode> findShortestPath(String startId, String targetId) {
    Map<String, double> distances = {};
    Map<String, String?> previousNodes = {};
    List<String> unvisited = [];

    for (var node in nodes) {
      distances[node.id] = double.infinity;
      previousNodes[node.id] = null;
      unvisited.add(node.id);
    }
    distances[startId] = 0.0;

    while (unvisited.isNotEmpty) {
      unvisited.sort((a, b) => distances[a]!.compareTo(distances[b]!));
      String currentNodeId = unvisited.first;

      if (distances[currentNodeId] == double.infinity) break;
      if (currentNodeId == targetId) break;

      unvisited.remove(currentNodeId);

      var connectedEdges = edges.where(
        (e) => e.nodeAId == currentNodeId || e.nodeBId == currentNodeId,
      );

      for (var edge in connectedEdges) {
        String neighborId = edge.nodeAId == currentNodeId
            ? edge.nodeBId
            : edge.nodeAId;
        if (!unvisited.contains(neighborId)) continue;

        double newDistance = distances[currentNodeId]! + edge.distanceWeight;
        if (newDistance < distances[neighborId]!) {
          distances[neighborId] = newDistance;
          previousNodes[neighborId] = currentNodeId;
        }
      }
    }

    List<MapNode> path = [];
    String? currentId = targetId;

    if (previousNodes[targetId] == null && startId != targetId) return [];

    while (currentId != null) {
      path.insert(0, nodes.firstWhere((n) => n.id == currentId));
      currentId = previousNodes[currentId];
    }

    return path;
  }
}
