class Store {
  final String id;
  final String name;
  final String category;
  final String description;
  final String logoUrl;
  final String floorLevel;
  final String localNumber;
  final String? nodeId;
  final String? planType;

  Store({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.logoUrl,
    required this.floorLevel,
    required this.localNumber,
    this.nodeId,
    this.planType,
  });

  factory Store.fromJson(Map<String, dynamic> json) {
    return Store(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] ?? 'General',
      description: json['description'] ?? '',
      logoUrl: json['logo_url'] ?? '',
      floorLevel: json['floor_level'] ?? '',
      localNumber: json['local_number'] ?? '',
      nodeId: json['node_id'] as String?,
      planType: json['plan_type'] as String?,
    );
  }

  // 🚀 NUEVO: Necesario para guardar en caché
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'description': description,
      'logo_url': logoUrl,
      'floor_level': floorLevel,
      'local_number': localNumber,
      'node_id': nodeId,
      'plan_type': planType,
    };
  }
}
