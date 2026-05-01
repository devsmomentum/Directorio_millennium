class MapEdge {
  final String id;
  final String nodeAId;
  final String nodeBId;
  final double distanceWeight;
  final bool directional;

  MapEdge({
    required this.id,
    required this.nodeAId,
    required this.nodeBId,
    required this.distanceWeight,
    this.directional = false,
  });

  factory MapEdge.fromJson(Map<String, dynamic> json) {
    return MapEdge(
      id: json['id'] as String,
      nodeAId: json['node_a_id'] as String,
      nodeBId: json['node_b_id'] as String,
      distanceWeight: (json['distance_weight'] as num).toDouble(),
      directional: (json['directional'] as bool?) ?? false,
    );
  }
}
