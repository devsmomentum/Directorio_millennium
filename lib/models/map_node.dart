class MapNode {
  final String id;
  final int floorLevel;
  final double x;
  final double y;
  final String nodeType;

  MapNode({
    required this.id,
    required this.floorLevel,
    required this.x,
    required this.y,
    required this.nodeType,
  });

  factory MapNode.fromJson(Map<String, dynamic> json) {
    return MapNode(
      id: json['id'] as String,
      floorLevel: json['floor_level'] as int,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      nodeType: json['node_type'] as String,
    );
  }
}
