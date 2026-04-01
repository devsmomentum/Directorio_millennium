import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../services/supabase_service.dart';
import '../services/analytics_service.dart';
import '../models/store.dart';
import '../models/map_route.dart';
import '../models/map_polygon.dart';
import '../widgets/route_points_painter.dart';
import '../widgets/polygon_painter.dart';

// ============================================================================
// Constantes de pisos
// ============================================================================
const Map<String, int> _floorNameToNum = {
  'C4': 5,
  'C3': 4,
  'C2': 3,
  'C1': 2,
  'RG': 1,
};
const Map<int, String> _floorNumToName = {
  5: 'C4',
  4: 'C3',
  3: 'C2',
  2: 'C1',
  1: 'RG',
};

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final TextEditingController _searchController = TextEditingController();

  List<Store> _allStores = [];
  List<Store> _filteredStores = [];
  String _selectedCategory = 'Todas';
  bool _isLoading = true;

  RealtimeChannel? _realtimeChannel;

  List<Map<String, dynamic>> _categories = [
    {'name': 'Todas', 'icon': Icons.grid_view_rounded},
  ];

  // Datos del kiosco actual
  String? _currentKioskId;
  int? _kioskFloorLevel; // Piso numérico del kiosco
  List<MapRoute> _allRoutes = [];
  List<MapPolygon> _allPolygons = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    _setupRealtime();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _searchController.dispose();
    super.dispose();
  }

  void _setupRealtime() {
    final client = Supabase.instance.client;
    client.removeChannel(client.channel('public-kiosk-updates'));

    _realtimeChannel = client.channel('public-kiosk-updates')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'stores',
        callback: (payload) {
          _loadData(isSilent: true);
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'categories',
        callback: (payload) {
          _loadData(isSilent: true);
        },
      )
      ..subscribe();
  }

  Future<void> _loadData({bool isSilent = false}) async {
    try {
      final client = Supabase.instance.client;
      final box = Hive.box('kiosk_cache');

      if (!isSilent && mounted) {
        setState(() => _isLoading = true);
      }

      final catsResponse =
          await client.from('categories').select().order('name');
      final stores = await _supabaseService.getStores();

      await box.put('cached_categories', catsResponse);
      final storesJson = stores.map((s) => s.toJson()).toList();
      await box.put('cached_stores', storesJson);

      // Cargar rutas, nodos, polígonos y datos del kiosco
      final routes = await _supabaseService.getMapRoutes();
      final nodes = await _supabaseService.getMapNodes();
      final polygons = await _supabaseService.getMapPolygons();

      final prefs = await SharedPreferences.getInstance();
      final kioskId = prefs.getString('kiosk_id');

      int? kioskFloor;
      if (kioskId != null) {
        final kioskData = await _supabaseService.getKioskById(kioskId);
        if (kioskData != null && kioskData['node_id'] != null) {
          // Buscar el nodo del kiosco para saber su piso
          final kioskNodeId = kioskData['node_id'] as String;
          try {
            final kioskNode = nodes.firstWhere((n) => n.id == kioskNodeId);
            kioskFloor = kioskNode.floorLevel;
          } catch (_) {}
        }
      }

      if (mounted) {
        setState(() {
          _allRoutes = routes;
          _allPolygons = polygons;
          _currentKioskId = kioskId;
          _kioskFloorLevel = kioskFloor;
        });
      }

      _updateUIWithData(catsResponse, stores);
    } catch (e) {
      debugPrint('Error de red: $e');
      await _loadFromCache();
    }
  }

  Future<void> _loadFromCache() async {
    try {
      final box = Hive.box('kiosk_cache');
      final catsData = box.get('cached_categories');
      final storesData = box.get('cached_stores');

      if (catsData != null && storesData != null) {
        final catsResponse = List<dynamic>.from(catsData);
        final storesJson = List<dynamic>.from(storesData);
        final stores = storesJson
            .map((s) => Store.fromJson(Map<String, dynamic>.from(s)))
            .toList();
        _updateUIWithData(catsResponse, stores);
      } else {
        throw Exception("No hay cache disponible.");
      }
    } catch (e) {
      debugPrint('Fallo total sin cache: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateUIWithData(List<dynamic> catsResponse, List<Store> stores) {
    List<Map<String, dynamic>> loadedCategories = [
      {'name': 'Todas', 'icon': Icons.grid_view_rounded},
    ];

    for (var cat in catsResponse) {
      loadedCategories.add({
        'name': cat['name'],
        'icon': _getIconData(cat['icon'] as String?),
      });
    }

    if (mounted) {
      setState(() {
        _categories = loadedCategories;
        _allStores = stores;
        _filterStores();
        _isLoading = false;
      });
    }
  }

  IconData _getIconData(String? iconName) {
    final normalized = iconName?.trim().toLowerCase() ?? '';
    switch (normalized) {
      case 'comida':
      case 'feria':
      case 'restaurante':
      case 'fastfood':
        return Icons.fastfood_rounded;
      case 'cafe':
      case 'postres':
      case 'cafeteria':
      case 'local_cafe':
        return Icons.local_cafe_rounded;
      case 'heladeria':
      case 'helados':
        return Icons.icecream_rounded;
      case 'ropa':
      case 'moda':
      case 'boutique':
      case 'checkroom':
        return Icons.checkroom_rounded;
      case 'zapatos':
      case 'calzado':
      case 'zapateria':
        return Icons.roller_skating_rounded;
      case 'tecnologia':
      case 'electronica':
      case 'celulares':
      case 'devices':
        return Icons.devices_rounded;
      case 'videojuegos':
      case 'juegos':
      case 'sports_esports':
        return Icons.sports_esports_rounded;
      case 'belleza':
      case 'maquillaje':
      case 'spa':
      case 'peluqueria':
        return Icons.spa_rounded;
      case 'salud':
      case 'farmacia':
      case 'clinica':
      case 'local_hospital':
        return Icons.local_hospital_rounded;
      case 'optica':
      case 'lentes':
        return Icons.remove_red_eye_rounded;
      case 'cine':
      case 'peliculas':
      case 'movie':
        return Icons.movie_rounded;
      case 'ninos':
      case 'jugueteria':
      case 'infantil':
      case 'child_friendly':
        return Icons.child_friendly_rounded;
      case 'mascotas':
      case 'veterinaria':
      case 'pets':
        return Icons.pets_rounded;
      case 'compras':
      case 'shopping':
      case 'shopping_bag':
      case 'tienda':
        return Icons.shopping_bag_rounded;
      case 'supermercado':
      case 'bodegon':
      case 'market':
        return Icons.shopping_cart_rounded;
      case 'banco':
      case 'cajero':
      case 'finanzas':
        return Icons.account_balance_rounded;
      case 'servicios':
      case 'reparacion':
      case 'home_repair_service':
        return Icons.home_repair_service_rounded;
      case 'deportes':
      case 'gimnasio':
      case 'fitness_center':
        return Icons.fitness_center_rounded;
      case 'joyeria':
      case 'relojes':
        return Icons.watch_rounded;
      case 'hogar':
      case 'muebles':
        return Icons.chair_rounded;
      case 'musica':
      case 'instrumentos':
        return Icons.music_note_rounded;
      default:
        return Icons.storefront_rounded;
    }
  }

  void _filterStores() {
    String query = _searchController.text.toLowerCase();
    setState(() {
      _filteredStores = _allStores.where((store) {
        final matchesQuery = store.name.toLowerCase().contains(query);
        final matchesCategory = _selectedCategory == 'Todas' ||
            store.category
                .toLowerCase()
                .contains(_selectedCategory.toLowerCase());
        return matchesQuery && matchesCategory;
      }).toList();
    });
  }

  /// Busca la primera ruta asociada a la tienda (como destino o como origen).
  MapRoute? _findFirstRouteForStore(Store store) {
    // Primero buscar rutas donde la tienda es destino y el kiosco actual es origen
    if (_currentKioskId != null) {
      for (final route in _allRoutes) {
        if (route.destType == 'store' &&
            route.destId == store.id &&
            route.originType == 'kiosk' &&
            route.originId == _currentKioskId) {
          return route;
        }
      }
    }

    // Luego buscar cualquier ruta donde la tienda es destino
    for (final route in _allRoutes) {
      if (route.destType == 'store' && route.destId == store.id) {
        return route;
      }
    }

    // Buscar rutas donde la tienda es origen
    for (final route in _allRoutes) {
      if (route.originType == 'store' && route.originId == store.id) {
        return route;
      }
    }

    return null;
  }

  /// Busca el polígono asociado a la tienda en el mapa.
  MapPolygon? _findPolygonForStore(Store store) {
    for (final polygon in _allPolygons) {
      if (polygon.storeId == store.id) {
        return polygon;
      }
    }
    return null;
  }

  /// Determina el piso numérico de una tienda.
  int _getStoreFloorNum(Store store) {
    return _floorNameToNum[store.floorLevel] ?? 1;
  }

  void _showStoreDetail(Store store) {
    AnalyticsService().logEvent(
      eventType: 'click',
      module: 'directory',
      itemName: store.name,
      itemId: store.id,
    );

    final storeFloor = _getStoreFloorNum(store);
    final isSameFloor =
        _kioskFloorLevel != null && storeFloor == _kioskFloorLevel;
    final route = _findFirstRouteForStore(store);
    final polygon = _findPolygonForStore(store);
    final hasRoute = route != null;
    final hasPolygon = polygon != null;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.7,
          constraints: const BoxConstraints(maxWidth: 600),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(30)),
                child: Image.network(
                  store.logoUrl,
                  height: 250,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 250,
                    color: Colors.white10,
                    child: const Icon(Icons.store,
                        size: 80, color: Colors.white24),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(30.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.name.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${store.category} • PISO ${store.floorLevel} • LOCAL ${store.localNumber}',
                      style: const TextStyle(
                        color: Color(0xFFFF007A),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Indicador de piso diferente (cuando no hay ruta directa)
                    if (!hasRoute && !isSameFloor && _kioskFloorLevel != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFC107).withAlpha(38),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                              color: const Color(0xFFFFC107).withAlpha(128),
                              width: 1.5),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.stairs_rounded,
                                color: Color(0xFFFFC107), size: 32),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'ESTA TIENDA ESTA EN OTRO PISO',
                                    style: TextStyle(
                                      color: Color(0xFFFFC107),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Te encuentras en el piso ${_floorNumToName[_kioskFloorLevel] ?? '?'}. '
                                    'Dirigete al piso ${store.floorLevel} para encontrar esta tienda.',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Texto descriptivo según el caso
                    if (hasRoute)
                      const Text(
                        "Toca el boton para ver la ruta en el mapa desde tu ubicacion actual.",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          height: 1.5,
                        ),
                      )
                    else if (hasPolygon)
                      Text(
                        !isSameFloor
                            ? "Esta tienda esta marcada en el mapa del piso ${store.floorLevel}. Puedes ver su ubicacion exacta."
                            : "No hay una ruta trazada, pero puedes ver su ubicacion en el mapa.",
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          height: 1.5,
                        ),
                      )
                    else
                      const Text(
                        "Esta tienda aun no tiene una ruta ni ubicacion asignada en el mapa.",
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),

                    const SizedBox(height: 40),
                    Row(
                      children: [
                        // CASO 1: Hay ruta → mostrar mapa con ruta animada
                        if (hasRoute)
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF007A),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 20),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                              onPressed: () {
                                Navigator.pop(context);
                                _showAnimatedMap(store, route);
                              },
                              child: const Text(
                                'VER RUTA EN EL MAPA',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),

                        // CASO 2: No hay ruta pero sí polígono → mostrar mapa con polígono
                        if (!hasRoute && hasPolygon)
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: !isSameFloor
                                    ? const Color(0xFFFFC107)
                                    : const Color(0xFFFF007A),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 20),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                              onPressed: () {
                                Navigator.pop(context);
                                _showStoreLocationMap(store, polygon);
                              },
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    !isSameFloor
                                        ? Icons.map_rounded
                                        : Icons.location_on,
                                    color: !isSameFloor
                                        ? Colors.black87
                                        : Colors.white,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    !isSameFloor
                                        ? 'VER EN MAPA PISO ${store.floorLevel}'
                                        : 'VER EN EL MAPA',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: !isSameFloor
                                          ? Colors.black87
                                          : Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // CASO 3: No hay ruta ni polígono, y está en otro piso
                        if (!hasRoute && !hasPolygon && !isSameFloor && _kioskFloorLevel != null)
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFC107).withAlpha(51),
                                borderRadius: BorderRadius.circular(15),
                                border:
                                    Border.all(color: const Color(0xFFFFC107)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.elevator_rounded,
                                      color: Color(0xFFFFC107), size: 24),
                                  const SizedBox(width: 8),
                                  Text(
                                    'PISO ${store.floorLevel}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFFFC107),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        const SizedBox(width: 15),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            'CERRAR',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAnimatedMap(Store targetStore, MapRoute route) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AnimatedMapModal(
        targetStore: targetStore,
        route: route,
      ),
    );
  }

  void _showStoreLocationMap(Store targetStore, MapPolygon polygon) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _StoreLocationMapModal(
        targetStore: targetStore,
        polygon: polygon,
        kioskFloorLevel: _kioskFloorLevel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                height: 140,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFFF007A), Color(0xFFFF5900)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(
                  child: Text(
                    'MILLENNIUM MALL - DIRECTORIO DIGITAL',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(30, 30, 30, 10),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => _filterStores(),
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                  decoration: InputDecoration(
                    hintText: 'Busca tu tienda favorita...',
                    hintStyle: const TextStyle(color: Colors.white30),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Color(0xFFFF007A),
                      size: 30,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF1A1A1A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 25),
                  ),
                ),
              ),
              SizedBox(
                height: 120,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    bool isSelected = _selectedCategory == cat['name'];
                    return GestureDetector(
                      onTap: () {
                        AnalyticsService().logEvent(
                          eventType: 'filter',
                          module: 'directory',
                          itemName: 'Categoria: ${cat['name']}',
                        );
                        setState(() => _selectedCategory = cat['name']);
                        _filterStores();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 140,
                        margin: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFFF007A)
                              : const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              cat['icon'],
                              color:
                                  isSelected ? Colors.white : Colors.white54,
                              size: 30,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              cat['name'],
                              style: TextStyle(
                                color:
                                    isSelected ? Colors.white : Colors.white54,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: Color(0xFFFF007A)),
                      )
                    : _filteredStores.isEmpty
                        ? const Center(
                            child: Text(
                              'No se encontraron tiendas',
                              style: TextStyle(color: Colors.white54),
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(30),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 25,
                              mainAxisSpacing: 25,
                              childAspectRatio: 0.85,
                            ),
                            itemCount: _filteredStores.length,
                            itemBuilder: (context, index) {
                              return GestureDetector(
                                onTap: () =>
                                    _showStoreDetail(_filteredStores[index]),
                                child:
                                    _buildStoreCard(_filteredStores[index]),
                              );
                            },
                          ),
              ),
            ],
          ),

          // ================================================================
          // ZONA SECRETA: Long-press 5 segundos en esquina superior derecha
          // para seleccionar kiosco
          // ================================================================
          Positioned(
            top: 0,
            right: 0,
            child: _KioskLongPressZone(
              onKioskSelected: () {
                // Recargar datos con el nuevo kiosco
                _loadData(isSilent: true);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreCard(Store store) {
    final storeFloor = _getStoreFloorNum(store);
    final isSameFloor =
        _kioskFloorLevel != null && storeFloor == _kioskFloorLevel;
    final hasRoute = _findFirstRouteForStore(store) != null;
    final hasPolygon = _findPolygonForStore(store) != null;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(25),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                color: Colors.black26,
                child: Image.network(
                  store.logoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.store, size: 50, color: Colors.white24),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(15.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      store.name.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'PISO ${store.floorLevel} • LOCAL ${store.localNumber}',
                            style: const TextStyle(
                              color: Color(0xFFFF007A),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        // Badge: otro piso sin ruta
                        if (_kioskFloorLevel != null && !isSameFloor && !hasRoute)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFC107).withAlpha(51),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.stairs_rounded,
                                    color: Color(0xFFFFC107), size: 12),
                                const SizedBox(width: 2),
                                Text(
                                  store.floorLevel,
                                  style: const TextStyle(
                                    color: Color(0xFFFFC107),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // Icono: tiene ruta
                        if (hasRoute)
                          const Icon(Icons.route_rounded,
                              color: Color(0xFFFF007A), size: 16),
                        // Icono: tiene polígono pero no ruta
                        if (!hasRoute && hasPolygon)
                          const Icon(Icons.map_rounded,
                              color: Colors.white38, size: 16),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ZONA INVISIBLE para long-press de 5 segundos (selector de kiosco)
// ============================================================================
class _KioskLongPressZone extends StatefulWidget {
  final VoidCallback onKioskSelected;
  const _KioskLongPressZone({required this.onKioskSelected});

  @override
  State<_KioskLongPressZone> createState() => _KioskLongPressZoneState();
}

class _KioskLongPressZoneState extends State<_KioskLongPressZone> {
  Timer? _longPressTimer;
  bool _isPressed = false;
  double _progress = 0.0;
  Timer? _progressTimer;

  void _startLongPress() {
    setState(() {
      _isPressed = true;
      _progress = 0.0;
    });

    // Actualizar progreso visual cada 50ms
    _progressTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (mounted) {
        setState(() {
          _progress = (_progress + 0.01).clamp(0.0, 1.0);
        });
      }
    });

    // Disparar a los 5 segundos
    _longPressTimer = Timer(const Duration(seconds: 5), () {
      _cancelTimers();
      if (mounted) {
        setState(() {
          _isPressed = false;
          _progress = 0.0;
        });
        _showKioskSelectorModal();
      }
    });
  }

  void _cancelLongPress() {
    _cancelTimers();
    if (mounted) {
      setState(() {
        _isPressed = false;
        _progress = 0.0;
      });
    }
  }

  void _cancelTimers() {
    _longPressTimer?.cancel();
    _progressTimer?.cancel();
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }

  void _showKioskSelectorModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _KioskSelectorModal(
        onSelected: () {
          widget.onKioskSelected();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => _startLongPress(),
      onLongPressEnd: (_) => _cancelLongPress(),
      onLongPressCancel: () => _cancelLongPress(),
      child: Container(
        width: 80,
        height: 80,
        color: Colors.transparent,
        child: _isPressed
            ? Center(
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    value: _progress,
                    strokeWidth: 3,
                    color: Colors.white24,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

// ============================================================================
// MODAL para seleccionar cual kiosco es este dispositivo
// ============================================================================
class _KioskSelectorModal extends StatefulWidget {
  final VoidCallback onSelected;
  const _KioskSelectorModal({required this.onSelected});

  @override
  State<_KioskSelectorModal> createState() => _KioskSelectorModalState();
}

class _KioskSelectorModalState extends State<_KioskSelectorModal> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _kiosks = [];
  String? _selectedKioskId;
  String? _currentKioskId;

  @override
  void initState() {
    super.initState();
    _loadKiosks();
  }

  Future<void> _loadKiosks() async {
    try {
      final client = Supabase.instance.client;
      final prefs = await SharedPreferences.getInstance();
      _currentKioskId = prefs.getString('kiosk_id');

      // Traer TODOS los kioscos (no solo los libres)
      final response = await client.from('kiosks').select();

      if (mounted) {
        setState(() {
          _kiosks = List<Map<String, dynamic>>.from(response);
          _selectedKioskId = _currentKioskId;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando kioscos: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectKiosk() async {
    if (_selectedKioskId == null) return;
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('kiosk_id', _selectedKioskId!);

      if (mounted) {
        Navigator.pop(context);
        widget.onSelected();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kiosco actualizado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error seleccionando kiosco: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tv_rounded, color: Color(0xFFFF007A), size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'SELECCIONAR KIOSCO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Selecciona a cual kiosco corresponde este dispositivo para determinar las rutas y el piso actual.',
              style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 24),

            if (_isLoading)
              const SizedBox(
                height: 100,
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF007A)),
                ),
              )
            else if (_kiosks.isEmpty)
              const Text(
                'No hay kioscos registrados en el sistema.',
                style: TextStyle(color: Colors.redAccent),
              )
            else
              ...(_kiosks.map((kiosk) {
                final isSelected = _selectedKioskId == kiosk['id'];
                final isCurrent = _currentKioskId == kiosk['id'];
                return GestureDetector(
                  onTap: () =>
                      setState(() => _selectedKioskId = kiosk['id']),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFFF007A).withOpacity(0.15)
                          : const Color(0xFF111111),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFFF007A)
                            : Colors.white10,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: isSelected
                              ? const Color(0xFFFF007A)
                              : Colors.white30,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                kiosk['name'] ?? 'Sin nombre',
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              if (kiosk['location'] != null)
                                Text(
                                  kiosk['location'],
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 13,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (isCurrent)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'ACTUAL',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }).toList()),

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF007A),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                onPressed:
                    _isLoading || _selectedKioskId == null ? null : _selectKiosk,
                child: const Text(
                  'CONFIRMAR KIOSCO',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// WIDGET DEL MAPA ANIMADO CON RUTA PRE-DIBUJADA DEL ADMIN
// ============================================================================
class _AnimatedMapModal extends StatefulWidget {
  final Store targetStore;
  final MapRoute route;
  const _AnimatedMapModal({
    Key? key,
    required this.targetStore,
    required this.route,
  }) : super(key: key);

  @override
  State<_AnimatedMapModal> createState() => _AnimatedMapModalState();
}

class _AnimatedMapModalState extends State<_AnimatedMapModal>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late TransformationController _transformationController;
  late AnimationController _cameraAnimationController;
  Size _currentViewSize = Size.zero;
  bool _isInitialCameraSet = false;
  String? _floorImageUrl;
  bool _isLoadingImage = true;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _transformationController = TransformationController();
    _cameraAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _loadFloorImage();
  }

  Future<void> _loadFloorImage() async {
    try {
      final client = Supabase.instance.client;
      final floorLabel =
          _floorNumToName[widget.route.floorLevel]?.toLowerCase() ?? 'rg';
      final url = client.storage
          .from('mapas')
          .getPublicUrl('plano_$floorLabel.png');
      setState(() {
        _floorImageUrl = url;
        _isLoadingImage = false;
      });
    } catch (e) {
      debugPrint('Error cargando imagen del piso: $e');
      setState(() => _isLoadingImage = false);
    }
  }

  void _animateCameraToFocusRoute() {
    final points = widget.route.points;
    if (points.isEmpty || _currentViewSize == Size.zero) return;

    double minX = points.first.x;
    double maxX = points.first.x;
    double minY = points.first.y;
    double maxY = points.first.y;

    for (var pt in points) {
      if (pt.x < minX) minX = pt.x;
      if (pt.x > maxX) maxX = pt.x;
      if (pt.y < minY) minY = pt.y;
      if (pt.y > maxY) maxY = pt.y;
    }

    double routeCenterX = (minX + maxX) / 2.0;
    double routeCenterY = (minY + maxY) / 2.0;
    double routeWidth = maxX - minX;
    double routeHeight = maxY - minY;

    double paddingFactor = 1.5;
    double viewWidth = _currentViewSize.width;
    double viewHeight = _currentViewSize.height;

    double scaleX = viewWidth / (routeWidth * paddingFactor);
    double scaleY = viewHeight / (routeHeight * paddingFactor);
    double targetScale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.8, 5.0);

    double targetDx = (viewWidth / 2.0) - (routeCenterX * targetScale);
    double targetDy = (viewHeight / 2.0) - (routeCenterY * targetScale);

    final targetMatrix = Matrix4.identity()
      ..translate(targetDx, targetDy)
      ..scale(targetScale);

    final Matrix4Tween matrixTween = Matrix4Tween(
      begin: _transformationController.value,
      end: targetMatrix,
    );

    _cameraAnimationController.addListener(() {
      _transformationController.value =
          matrixTween.evaluate(_cameraAnimationController);
    });

    _cameraAnimationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _animationController.forward();
      }
    });

    _cameraAnimationController.forward(from: 0.0);
  }

  void _setInitialMacroFit(BoxConstraints constraints) {
    if (_isInitialCameraSet) return;

    double mapOriginalSize = 2000.0;
    double viewWidth = constraints.maxWidth;
    double viewHeight = constraints.maxHeight;

    double scaleFit =
        (viewWidth / mapOriginalSize < viewHeight / mapOriginalSize)
            ? viewWidth / mapOriginalSize
            : viewHeight / mapOriginalSize;

    double dx = (viewWidth - (mapOriginalSize * scaleFit)) / 2.0;
    double dy = (viewHeight - (mapOriginalSize * scaleFit)) / 2.0;

    _transformationController.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scaleFit);

    _isInitialCameraSet = true;
  }

  Color _parseRouteColor(String hexColor) {
    try {
      final hex = hexColor.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.pinkAccent;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _transformationController.dispose();
    _cameraAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routeColor = _parseRouteColor(widget.route.color);
    final points = widget.route.points;

    return Dialog(
      backgroundColor: const Color(0xFF111111),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        height: MediaQuery.of(context).size.height * 0.85,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(30)),
        child: Column(
          children: [
            // Header
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
              color: const Color(0xFF1A1A1A),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "RUTA: ${widget.route.name}",
                          style: const TextStyle(
                            color: Color(0xFFFF007A),
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          "Hacia: ${widget.targetStore.name}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'PISO ${_floorNumToName[widget.route.floorLevel] ?? '?'} • LOCAL ${widget.targetStore.localNumber}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Mapa
            Expanded(
              child: _isLoadingImage
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFFFF007A)),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        _currentViewSize =
                            Size(constraints.maxWidth, constraints.maxHeight);

                        if (!_isInitialCameraSet) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _setInitialMacroFit(constraints);
                            // Iniciar animación de cámara después del macro fit
                            Future.delayed(
                                const Duration(milliseconds: 300), () {
                              if (mounted) _animateCameraToFocusRoute();
                            });
                          });
                        }

                        return InteractiveViewer(
                          transformationController: _transformationController,
                          maxScale: 5.0,
                          minScale: 0.1,
                          constrained: false,
                          boundaryMargin: const EdgeInsets.all(100),
                          child: SizedBox(
                            width: 2000,
                            height: 2000,
                            child: Stack(
                              children: [
                                // Imagen del plano
                                if (_floorImageUrl != null)
                                  Image.network(
                                    _floorImageUrl!,
                                    width: 2000,
                                    height: 2000,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 2000,
                                      height: 2000,
                                      color: const Color(0xFF111111),
                                      child: const Center(
                                        child: Text(
                                          'No se pudo cargar el plano',
                                          style: TextStyle(
                                              color: Colors.white24),
                                        ),
                                      ),
                                    ),
                                  ),

                                // Ruta animada
                                AnimatedBuilder(
                                  animation: _animationController,
                                  builder: (context, child) {
                                    return CustomPaint(
                                      size: const Size(2000, 2000),
                                      painter: RoutePointsPainter(
                                        points: points,
                                        animationValue:
                                            _animationController.value,
                                        routeColor: routeColor,
                                      ),
                                    );
                                  },
                                ),

                                // Marcador de destino (tienda)
                                if (points.isNotEmpty)
                                  Positioned(
                                    left: points.last.x - 25,
                                    top: points.last.y - 50,
                                    child: const Icon(
                                      Icons.location_on,
                                      color: Colors.pinkAccent,
                                      size: 50,
                                    ),
                                  ),

                                // Marcador de origen (kiosco / tu ubicación)
                                if (points.isNotEmpty)
                                  Positioned(
                                    left: points.first.x - 20,
                                    top: points.first.y - 20,
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: Colors.blueAccent,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white, width: 3),
                                      ),
                                      child: const Icon(
                                        Icons.accessibility_new,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// MODAL: MUESTRA PLANO CON POLIGONO RESALTADO (sin ruta)
// ============================================================================
class _StoreLocationMapModal extends StatefulWidget {
  final Store targetStore;
  final MapPolygon polygon;
  final int? kioskFloorLevel;

  const _StoreLocationMapModal({
    Key? key,
    required this.targetStore,
    required this.polygon,
    this.kioskFloorLevel,
  }) : super(key: key);

  @override
  State<_StoreLocationMapModal> createState() => _StoreLocationMapModalState();
}

class _StoreLocationMapModalState extends State<_StoreLocationMapModal>
    with SingleTickerProviderStateMixin {
  late TransformationController _transformationController;
  late AnimationController _pulseController;
  String? _floorImageUrl;
  bool _isLoadingImage = true;
  bool _isInitialCameraSet = false;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _loadFloorImage();
  }

  Future<void> _loadFloorImage() async {
    try {
      final client = Supabase.instance.client;
      final floorLabel =
          _floorNumToName[widget.polygon.floorLevel]?.toLowerCase() ?? 'rg';
      final url =
          client.storage.from('mapas').getPublicUrl('plano_$floorLabel.png');
      setState(() {
        _floorImageUrl = url;
        _isLoadingImage = false;
      });
    } catch (e) {
      debugPrint('Error cargando imagen del piso: $e');
      setState(() => _isLoadingImage = false);
    }
  }

  Color _parseColor(String hexColor) {
    try {
      final hex = hexColor.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.pinkAccent;
    }
  }

  void _focusOnPolygon(BoxConstraints constraints) {
    if (_isInitialCameraSet) return;
    final points = widget.polygon.points;
    if (points.length < 3) return;

    double minX = points.first.x;
    double maxX = points.first.x;
    double minY = points.first.y;
    double maxY = points.first.y;

    for (var pt in points) {
      if (pt.x < minX) minX = pt.x;
      if (pt.x > maxX) maxX = pt.x;
      if (pt.y < minY) minY = pt.y;
      if (pt.y > maxY) maxY = pt.y;
    }

    double centerX = (minX + maxX) / 2.0;
    double centerY = (minY + maxY) / 2.0;
    double polyWidth = maxX - minX;
    double polyHeight = maxY - minY;

    double paddingFactor = 2.0;
    double viewWidth = constraints.maxWidth;
    double viewHeight = constraints.maxHeight;

    double scaleX = viewWidth / (polyWidth * paddingFactor);
    double scaleY = viewHeight / (polyHeight * paddingFactor);
    double targetScale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.5, 4.0);

    double dx = (viewWidth / 2.0) - (centerX * targetScale);
    double dy = (viewHeight / 2.0) - (centerY * targetScale);

    _transformationController.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(targetScale);

    _isInitialCameraSet = true;
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final polyColor = _parseColor(widget.polygon.color);
    final isSameFloor = widget.kioskFloorLevel != null &&
        widget.polygon.floorLevel == widget.kioskFloorLevel;
    final floorName = _floorNumToName[widget.polygon.floorLevel] ?? '?';

    return Dialog(
      backgroundColor: const Color(0xFF111111),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        height: MediaQuery.of(context).size.height * 0.85,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(30)),
        child: Column(
          children: [
            // Header
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
              color: const Color(0xFF1A1A1A),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              "UBICACION EN PISO $floorName",
                              style: TextStyle(
                                color:
                                    isSameFloor ? const Color(0xFFFF007A) : const Color(0xFFFFC107),
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                                fontSize: 12,
                              ),
                            ),
                            if (!isSameFloor) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFC107).withAlpha(38),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'OTRO PISO',
                                  style: TextStyle(
                                    color: Color(0xFFFFC107),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          widget.targetStore.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'LOCAL ${widget.targetStore.localNumber} • ${widget.targetStore.category}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Mapa con polígono
            Expanded(
              child: _isLoadingImage
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFFFF007A)),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        if (!_isInitialCameraSet) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _focusOnPolygon(constraints);
                          });
                        }

                        return InteractiveViewer(
                          transformationController: _transformationController,
                          maxScale: 5.0,
                          minScale: 0.1,
                          constrained: false,
                          boundaryMargin: const EdgeInsets.all(100),
                          child: SizedBox(
                            width: 2000,
                            height: 2000,
                            child: Stack(
                              children: [
                                // Plano del piso
                                if (_floorImageUrl != null)
                                  Image.network(
                                    _floorImageUrl!,
                                    width: 2000,
                                    height: 2000,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 2000,
                                      height: 2000,
                                      color: const Color(0xFF111111),
                                      child: const Center(
                                        child: Text(
                                          'No se pudo cargar el plano',
                                          style:
                                              TextStyle(color: Colors.white24),
                                        ),
                                      ),
                                    ),
                                  ),

                                // Polígono resaltado con pulso
                                AnimatedBuilder(
                                  animation: _pulseController,
                                  builder: (context, child) {
                                    return CustomPaint(
                                      size: const Size(2000, 2000),
                                      painter: PolygonHighlightPainter(
                                        polygon: widget.polygon,
                                        fillColor: polyColor,
                                        borderColor: polyColor,
                                        pulseValue: _pulseController.value,
                                      ),
                                    );
                                  },
                                ),

                                // Label de la tienda en el centro del polígono
                                if (widget.polygon.points.length >= 3)
                                  Positioned(
                                    left: _polygonCenterX(widget.polygon) - 60,
                                    top: _polygonCenterY(widget.polygon) - 20,
                                    child: Container(
                                      width: 120,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.black87,
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        border: Border.all(
                                            color: polyColor, width: 1.5),
                                      ),
                                      child: Text(
                                        widget.targetStore.name.toUpperCase(),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  double _polygonCenterX(MapPolygon polygon) {
    double sum = 0;
    for (var pt in polygon.points) {
      sum += pt.x;
    }
    return sum / polygon.points.length;
  }

  double _polygonCenterY(MapPolygon polygon) {
    double sum = 0;
    for (var pt in polygon.points) {
      sum += pt.y;
    }
    return sum / polygon.points.length;
  }
}
