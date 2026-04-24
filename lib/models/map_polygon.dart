class PolygonPoint {
  final double x;
  final double y;

  PolygonPoint({required this.x, required this.y});

  factory PolygonPoint.fromJson(Map<String, dynamic> json) {
    return PolygonPoint(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
    );
  }
}

class MapPolygon {
  final String id;
  final String name;
  final String color;
  final List<PolygonPoint> points;
  final String floorLevel;
  final String? storeId;

  MapPolygon({
    required this.id,
    required this.name,
    required this.color,
    required this.points,
    required this.floorLevel,
    this.storeId,
  });

  factory MapPolygon.fromJson(Map<String, dynamic> json) {
    List<PolygonPoint> pts = [];
    if (json['points'] != null) {
      final rawPoints = json['points'];
      if (rawPoints is List) {
        pts = rawPoints
            .map((p) => PolygonPoint.fromJson(Map<String, dynamic>.from(p)))
            .toList();
      }
    }

    return MapPolygon(
      id: json['id'] as String,
      name: json['name'] ?? '',
      color: json['color'] ?? '#4466ff',
      points: pts,
      floorLevel: json['floor_level'].toString(),
      storeId: json['store_id'] as String?,
    );
  }
}
