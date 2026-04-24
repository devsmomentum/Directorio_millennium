import '../models/map_node.dart';

/// Convierte coordenadas del grafo (`map_nodes.x / y / z_height`) al sistema de
/// referencia 3D de three.js (Y-up). El plano lógico del centro comercial usa
/// X/Y como coordenadas en el suelo y `z_height` como altura; three.js espera
/// X/Z como plano de suelo y Y como altura, por lo que se mapea:
///
///   world.x = node.x * scale + offset.x
///   world.y = node.z_height * scale + offset.y
///   world.z = node.y * scale + offset.z
///
/// Los factores viven en un único lugar para poder ajustarlos sin tocar la
/// capa de navegación ni el código inyectado en JavaScript.
class NodeWorldMapping {
  final double scale;
  final double offsetX;
  final double offsetY;
  final double offsetZ;

  const NodeWorldMapping({
    this.scale = 1.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.offsetZ = 0.0,
  });

  /// Mapeo por defecto: identidad. Úsalo si los .glb del mapa ya comparten el
  /// mismo sistema de ejes que los nodos almacenados en Supabase.
  static const NodeWorldMapping identity = NodeWorldMapping();

  /// Coordenadas 3D del nodo en el espacio de three.js.
  ({double x, double y, double z}) toWorld(MapNode node) {
    return (
      x: node.x * scale + offsetX,
      y: node.zHeight * scale + offsetY,
      z: node.y * scale + offsetZ,
    );
  }

  /// Versión serializable para JS: `{x, y, z, nodeId}`.
  Map<String, dynamic> toWaypoint(MapNode node) {
    final w = toWorld(node);
    return {
      'x': w.x,
      'y': w.y,
      'z': w.z,
      'nodeId': node.id,
      'floorLevel': node.floorLevel,
      'nodeType': node.nodeType,
    };
  }
}
