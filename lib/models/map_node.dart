class MapNode {
  final String id;
  final String floorLevel;
  final double x;
  final double y;
  final double zHeight;
  final bool is3d;
  final String nodeType;
  /// Rol del nodo cuando es conector (escalera / ascensor):
  /// 'exit'  → el avatar camina HASTA aquí para salir del piso.
  /// 'entry' → el avatar APARECE aquí al llegar de otro piso.
  /// 'both'  → bidireccional (escalera fija, ascensor).
  /// null    → no es conector.
  final String? connectorRole;
  /// UUID del nodo par en el piso destino (exit ↔ entry).
  final String? pairedNodeId;

  MapNode({
    required this.id,
    required this.floorLevel,
    required this.x,
    required this.y,
    required this.nodeType,
    this.zHeight = 0.0,
    this.is3d = false,
    this.connectorRole,
    this.pairedNodeId,
  });

  bool get isConnector =>
      nodeType == 'stairs' || nodeType == 'elevator';

  bool get isExit => connectorRole == 'exit' || connectorRole == 'both';
  bool get isEntry => connectorRole == 'entry' || connectorRole == 'both';

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
      connectorRole: json['connector_role'] as String?,
      pairedNodeId: json['paired_node_id'] as String?,
    );
  }
}
