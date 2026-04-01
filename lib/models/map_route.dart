class MapRoutePoint {
  final double x;
  final double y;

  MapRoutePoint({required this.x, required this.y});

  factory MapRoutePoint.fromJson(Map<String, dynamic> json) {
    return MapRoutePoint(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
    );
  }
}

class MapRoute {
  final String id;
  final String name;
  final String color;
  final List<MapRoutePoint> points;
  final int floorLevel;
  final String? originType;
  final String? originId;
  final String? destType;
  final String? destId;

  MapRoute({
    required this.id,
    required this.name,
    required this.color,
    required this.points,
    required this.floorLevel,
    this.originType,
    this.originId,
    this.destType,
    this.destId,
  });

  factory MapRoute.fromJson(Map<String, dynamic> json) {
    List<MapRoutePoint> pts = [];
    if (json['points'] != null) {
      final rawPoints = json['points'];
      if (rawPoints is List) {
        pts = rawPoints
            .map((p) => MapRoutePoint.fromJson(Map<String, dynamic>.from(p)))
            .toList();
      }
    }

    return MapRoute(
      id: json['id'] as String,
      name: json['name'] ?? '',
      color: json['color'] ?? '#22d3ee',
      points: pts,
      floorLevel: json['floor_level'] as int,
      originType: json['origin_type'] as String?,
      originId: json['origin_id'] as String?,
      destType: json['dest_type'] as String?,
      destId: json['dest_id'] as String?,
    );
  }
}
