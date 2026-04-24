class MapNode {
  final String id;
  final String floorLevel;
  final double x;
  final double y;
  final double zHeight;
  final bool is3d;
  final String nodeType;

  MapNode({
    required this.id,
    required this.floorLevel,
    required this.x,
    required this.y,
    required this.nodeType,
    this.zHeight = 0.0,
    this.is3d = false,
  });

  factory MapNode.fromJson(Map<String, dynamic> json) {
    return MapNode(
      id: json['id'] as String,
      floorLevel: json['floor_level'].toString(),
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      zHeight: json['z_height'] == null
          ? 0.0
          : (json['z_height'] as num).toDouble(),
      is3d: json['is_3d'] as bool? ?? false,
      nodeType: json['node_type'] as String,
    );
  }
}
