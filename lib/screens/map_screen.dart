import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../services/supabase_service.dart';
import '../services/analytics_service.dart';
import '../services/avatar_navigation_service.dart';
import '../services/kiosk_bus.dart';
import '../models/store.dart';
import '../models/map_node.dart';
import '../models/map_route.dart';
import '../models/map_polygon.dart';
import '../utils/node_world_mapping.dart';
import '../widgets/screen_ad_banners.dart';
import '../widgets/map_view_web.dart';
import '../theme/app_theme.dart';

// URL del avatar 3D (Supabase Storage).
const String _kAvatarModelUrl =
    'https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/mapas/Persona_caminar.glb';

/// Parámetros que convierten coordenadas del grafo al mundo three.js. Si los
/// .glb del mapa no comparten escala 1:1 con los nodos, ajustar aquí.
const NodeWorldMapping _kNodeWorldMapping = NodeWorldMapping.identity;

// ============================================================================
// Constantes de pisos
// ============================================================================

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Key global para acceder al estado de MapViewWeb (comunicación Flutter→Web)
  final GlobalKey<MapViewWebState> _mapViewKey = GlobalKey<MapViewWebState>();
  final SupabaseService _supabaseService = SupabaseService();
  final TextEditingController _searchController = TextEditingController();
  
  // Controladores para las flechas dinámicas de categorías
  final ScrollController _categoryScrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = true;

  List<Store> _allStores = [];
  List<Store> _filteredStores = [];
  String _selectedCategory = 'Todas';
  String _selectedFloor = 'RG';
  bool _isLoading = true;

  RealtimeChannel? _realtimeChannel;

  List<Map<String, dynamic>> _categories = [
    {'name': 'Todas', 'icon': Icons.grid_view_rounded},
  ];

  // Datos del kiosco actual
  String? _currentKioskId;
  String? _currentKioskNodeId;
  String? _kioskFloorLevel;
  List<MapRoute> _allRoutes = [];
  List<MapPolygon> _allPolygons = [];
  List<MapNode> _allNodes = const [];
  AvatarNavigationService? _navService;

  // Tienda seleccionada → para feedback UI de ruta activa
  Store? _selectedStoreForRoute;

  // Flag para evitar loop en Flutter Web: `startAvatarRoute` recarga el HTML
  // y `onMapLoaded` vuelve a dispararse; sin este flag, llamaría de nuevo a
  // `_runAvatarRouteTo` → otra recarga → loop infinito. Se marca true cuando
  // la ruta ya fue enviada al WebView, y se resetea en cada nueva selección.
  bool _routeDispatched = false;

  // Calibración del modelo por piso (cargada desde map_calibration en Supabase)
  Map<String, Map<String, double>> _floorCalibrations = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    _setupRealtime();
    _categoryScrollController.addListener(_updateCategoryScrollState);
    // Recarga cuando el técnico cambia el kiosco desde el header.
    KioskBus.selectionTick.addListener(_onKioskChanged);
  }

  @override
  void dispose() {
    KioskBus.selectionTick.removeListener(_onKioskChanged);
    _realtimeChannel?.unsubscribe();
    _searchController.dispose();
    _categoryScrollController.dispose();
    super.dispose();
  }

  void _onKioskChanged() {
    debugPrint('[MapScreen] KioskBus → recargando datos por cambio de kiosco');
    _selectedStoreForRoute = null;
    _routeDispatched = false;
    _mapViewKey.currentState?.stopAvatarRoute();
    _loadData(isSilent: true);
  }

  void _updateCategoryScrollState() {
    if (!_categoryScrollController.hasClients) return;
    
    final canLeft = _categoryScrollController.position.pixels > 0;
    final canRight = _categoryScrollController.position.pixels < _categoryScrollController.position.maxScrollExtent;
    
    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      if (mounted) {
        setState(() {
          _canScrollLeft = canLeft;
          _canScrollRight = canRight;
        });
      }
    }
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

      final catsResponse = await client
          .from('categories')
          .select()
          .order('name');
      final stores = await _supabaseService.getStores();

      await box.put('cached_categories', catsResponse);
      final storesJson = stores.map((s) => s.toJson()).toList();
      await box.put('cached_stores', storesJson);

      final routes = await _supabaseService.getMapRoutes();
      final nodes = await _supabaseService.getMapNodes();
      final edges = await _supabaseService.getMapEdges();
      final polygons = await _supabaseService.getMapPolygons();

      // Cargar calibraciones de todos los pisos desde Supabase.
      // Requiere la tabla map_calibration (ver SQL exportado por el editor).
      try {
        final calibRows = await Supabase.instance.client
            .from('map_calibration')
            .select('floor_code, scale, ox, oy, oz, rot_y');
        final calibMap = <String, Map<String, double>>{};
        for (final row in calibRows as List<dynamic>) {
          final code = (row['floor_code'] as String).toUpperCase();
          calibMap[code] = {
            'scale': (row['scale'] as num?)?.toDouble() ?? 1.0,
            'ox': (row['ox'] as num?)?.toDouble() ?? 0.0,
            'oy': (row['oy'] as num?)?.toDouble() ?? 0.0,
            'oz': (row['oz'] as num?)?.toDouble() ?? 0.0,
            'rotY': (row['rot_y'] as num?)?.toDouble() ?? 0.0,
          };
        }
        _floorCalibrations = calibMap;
        debugPrint('[MapScreen] Calibraciones cargadas: ${calibMap.keys.join(', ')}');
      } catch (e) {
        // La tabla puede no existir aún; continuar con calibración por defecto.
        debugPrint('[MapScreen] map_calibration no disponible: $e');
      }

      final prefs = await SharedPreferences.getInstance();
      final kioskId = prefs.getString('kiosk_id');

      String? kioskFloor;
      String? kioskNodeId;
      if (kioskId == null) {
        debugPrint(
          '[MapScreen] ⚠ No hay kiosk_id en SharedPreferences — '
          'el técnico debe seleccionar un kiosco desde el header.',
        );
      } else {
        final kioskData = await _supabaseService.getKioskById(kioskId);
        if (kioskData == null) {
          debugPrint(
            '[MapScreen] ⚠ Kiosco "$kioskId" no existe en Supabase.',
          );
        } else if (kioskData['node_id'] == null ||
            (kioskData['node_id'] as String).isEmpty) {
          debugPrint(
            '[MapScreen] ⚠ El kiosco "$kioskId" existe pero tiene node_id NULL '
            'en la base de datos. Asígnale un nodo del grafo.',
          );
        } else {
          kioskNodeId = kioskData['node_id'] as String;
          final nodeMatch = nodes.where((n) => n.id == kioskNodeId).toList();
          if (nodeMatch.isEmpty) {
            debugPrint(
              '[MapScreen] ⚠ node_id "$kioskNodeId" del kiosco no está en '
              'map_nodes. ¿Límite de filas en la consulta?',
            );
          } else {
            kioskFloor = nodeMatch.first.floorLevel;
          }
        }
      }

      // Construimos el servicio ANTES del setState para que, aunque el
      // callback onMapLoaded del WebView se dispare en el mismo frame, ya
      // encuentre el grafo listo.
      final navService = AvatarNavigationService(
        nodes: nodes,
        edges: edges,
        mapping: _kNodeWorldMapping,
      );

      if (mounted) {
        setState(() {
          _allRoutes = routes;
          _allPolygons = polygons;
          _allNodes = nodes;
          _currentKioskId = kioskId;
          _currentKioskNodeId = kioskNodeId;
          _kioskFloorLevel = kioskFloor;
          _navService = navService;
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateCategoryScrollState());
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

  // ══════════════════════════════════════════════════════════════════════════
  // LÓGICA DE ORDENAMIENTO Y BÚSQUEDA AVANZADA (NUEVO)
  // ══════════════════════════════════════════════════════════════════════════

  /// Define el nivel de prioridad de cada plan. Número menor = mayor prioridad.
  int _getPlanPriority(String? plan) {
    if (plan == null) return 4;
    switch (plan.toUpperCase()) {
      case 'DIAMANTE':
        return 1;
      case 'ORO':
        return 2;
      case 'IA_PERFORMANCE':
        return 3;
      default:
        return 4; // Otros casos o nulos
    }
  }

  void _filterStores() {
    String query = _searchController.text.toLowerCase().trim();
    
    setState(() {
      // 1. Filtrado de datos (Por Nombre, Categoría o Descripción/Nicho)
      _filteredStores = _allStores.where((store) {
        // Obtenemos los campos de forma segura
        final name = store.name.toLowerCase();
        final category = store.category.toLowerCase();
        // Asume que tienes `description` en tu modelo Store. Si no, quita esta línea.
        final description = store.description.toLowerCase() ?? ''; 

        final matchesQuery = query.isEmpty ||
            name.contains(query) ||
            category.contains(query) ||
            description.contains(query);

        final matchesCategory = _selectedCategory == 'Todas' ||
            category.contains(_selectedCategory.toLowerCase());

        return matchesQuery && matchesCategory;
      }).toList();

      // 2. Ordenamiento por Prioridad de Plan
      _filteredStores.sort((a, b) {
        // Asume que tu modelo Store tiene el campo planType o plan_type
        int priorityA = _getPlanPriority(a.planType);
        int priorityB = _getPlanPriority(b.planType);

        if (priorityA != priorityB) {
          // Si tienen distinto plan, prioriza el de menor número (1 Diamante > 4 Null)
          return priorityA.compareTo(priorityB);
        }
        
        // Si tienen el mismo plan, ordenamos alfabéticamente por el nombre
        return a.name.compareTo(b.name);
      });
    });
  }

  // ══════════════════════════════════════════════════════════════════════════

  MapRoute? _findFirstRouteForStore(Store store) {
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
    for (final route in _allRoutes) {
      if (route.destType == 'store' && route.destId == store.id) {
        return route;
      }
    }
    for (final route in _allRoutes) {
      if (route.originType == 'store' && route.originId == store.id) {
        return route;
      }
    }
    return null;
  }

  MapPolygon? _findPolygonForStore(Store store) {
    for (final polygon in _allPolygons) {
      if (polygon.storeId == store.id) {
        return polygon;
      }
    }
    return null;
  }



  void _onStoreTapped(Store store) {
    AnalyticsService().logEvent(
      eventType: 'click',
      module: 'directory',
      itemName: store.name,
      itemId: store.id,
    );

    // Si la tienda está en otro piso, cambiamos la vista primero; la ruta se
    // dispara cuando el nuevo mapa esté cargado (ver `onMapLoaded`).
    final targetFloorName = store.floorLevel;

    setState(() {
      _selectedStoreForRoute = store;
      _routeDispatched = false; // nueva selección → permitir dispatch
    });

    if (targetFloorName != null && targetFloorName != _selectedFloor) {
      setState(() => _selectedFloor = targetFloorName);
      // Al cambiar de piso el MapViewWeb se reconstruye (ValueKey), por lo que
      // `onMapLoaded` disparará `_runAvatarRouteTo` para la tienda en el nuevo
      // piso. Nada más que hacer aquí.
      return;
    }

    _runAvatarRouteTo(store);
  }

  /// Calcula y lanza la animación del avatar hacia la tienda.
  void _runAvatarRouteTo(Store store) {
    final nav = _navService;
    if (nav == null || !nav.isReady) {
      debugPrint(
        '[MapScreen] Servicio de navegación no listo aún '
        '(nav=${nav != null}, ready=${nav?.isReady ?? false}). '
        'Reintentaré cuando termine de cargar.',
      );
      return;
    }
    if (_currentKioskNodeId == null || _currentKioskNodeId!.isEmpty) {
      debugPrint(
        '[MapScreen] No se puede navegar: kiosk_id=$_currentKioskId '
        'sin node_id asignado en la tabla kiosks.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'El kiosco actual no tiene un nodo de mapa asignado. '
              'Configúralo en Supabase.',
            ),
            backgroundColor: AppColors.error,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    final currentFloorNum = _selectedFloor;
    debugPrint(
      '[MapScreen] Calculando ruta: kiosko=$_currentKioskNodeId → '
      'tienda="${store.name}" (node=${store.nodeId}) '
      'piso=$currentFloorNum',
    );
    final route = nav.routeFromKioskToStore(
      kioskNodeId: _currentKioskNodeId,
      store: store,
      currentFloorLevel: currentFloorNum,
    );

    if (route.isEmpty || route.waypoints.isEmpty) {
      debugPrint(
        '[MapScreen] Sin ruta disponible: ${route.errorMessage ?? "desconocido"}',
      );
      if (mounted && route.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(route.errorMessage!),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      // Al menos posicionamos el avatar en el kiosko si tenemos su nodo.
      _placeAvatarAtKiosk();
      return;
    }

    // La cámara la posiciona el JS (fitCameraToRoute) para encuadrar el
    // recorrido completo desde el kiosco hasta la tienda.
    final mapView = _mapViewKey.currentState;
    // Marcar ANTES del envío: en web la recarga de HTML puede disparar
    // onMapLoaded muy rápido y llegar antes de que esta línea se ejecute.
    _routeDispatched = true;
    mapView?.startAvatarRoute(route.waypoints);
  }

  void _placeAvatarAtKiosk() {
    final kioskNodeId = _currentKioskNodeId;
    if (kioskNodeId == null) return;
    MapNode? kioskNode;
    for (final n in _allNodes) {
      if (n.id == kioskNodeId) {
        kioskNode = n;
        break;
      }
    }
    if (kioskNode == null) return;
    final world = _kNodeWorldMapping.toWorld(kioskNode);
    _mapViewKey.currentState?.setAvatarAtWorld(world.x, world.y, world.z);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ScreenAdBanners(
        showTop: false,
        showBottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                // ── Fila 1: Barra de búsqueda ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: SizedBox(
                    height: 48,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => _filterStores(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Busca tienda, categoría, nicho...', // Texto más intuitivo
                        hintStyle: const TextStyle(color: AppColors.textHint),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: AppColors.primary,
                          size: 24,
                        ),
                        filled: true,
                        fillColor: AppColors.surfaceLight,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),
                  ),
                ),

                // ── Fila 2: Categorías con Flechas Dinámicas estilo iOS ──
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _canScrollLeft ? 1.0 : 0.0,
                        child: GestureDetector(
                          onTap: _canScrollLeft ? () {
                            _categoryScrollController.animateTo(
                              _categoryScrollController.offset - 250,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          } : null,
                          child: Container(
                            color: Colors.transparent,
                            padding: const EdgeInsets.only(left: 16, right: 8),
                            child: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 18,
                              color: AppColors.textSecondaryMuted,
                            ),
                          ),
                        ),
                      ),

                      Expanded(
                        child: ListView.builder(
                          controller: _categoryScrollController,
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.only(
                            left: _canScrollLeft ? 0 : 12,
                            right: _canScrollRight ? 0 : 12,
                          ),
                          itemCount: _categories.length,
                          itemBuilder: (context, index) {
                            final cat = _categories[index];
                            final isSelected = _selectedCategory == cat['name'];
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
                                duration: const Duration(milliseconds: 250),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 4,
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.surfaceLight,
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      cat['icon'] as IconData,
                                      color: isSelected
                                          ? AppColors.textPrimary
                                          : AppColors.textSecondaryMuted,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      cat['name'] as String,
                                      style: TextStyle(
                                        color: isSelected
                                            ? AppColors.textPrimary
                                            : AppColors.textSecondaryMuted,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _canScrollRight ? 1.0 : 0.0,
                        child: GestureDetector(
                          onTap: _canScrollRight ? () {
                            _categoryScrollController.animateTo(
                              _categoryScrollController.offset + 250,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          } : null,
                          child: Container(
                            color: Colors.transparent,
                            padding: const EdgeInsets.only(left: 8, right: 16),
                            child: const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 18,
                              color: AppColors.textSecondaryMuted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Fila 3: Tres columnas principales ──
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ═══ COLUMNA A: Lista de tiendas ═══
                        Expanded(
                          flex: 2,
                          child: _isLoading
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: AppColors.primary,
                                  ),
                                )
                              : _filteredStores.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'No se encontraron resultados',
                                        style: TextStyle(
                                          color: AppColors.textSecondaryMuted,
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      padding: const EdgeInsets.only(right: 8, top: 4),
                                      itemCount: _filteredStores.length,
                                      itemBuilder: (context, index) {
                                        return GestureDetector(
                                          onTap: () => _onStoreTapped(
                                            _filteredStores[index],
                                          ),
                                          child: _buildStoreCard(
                                            _filteredStores[index],
                                          ),
                                        );
                                      },
                                    ),
                        ),

                        // ═══ COLUMNA B: Mapa placeholder ═══
                        Expanded(
                          flex: 5,
                          child: _build3DMapArea(),
                        ),

                        // ═══ COLUMNA C: Selector de pisos ═══
                        SizedBox(
                          width: 60,
                          child: _buildFloorSelector(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Nota: el selector de kiosco vive ahora en AppHeader
            // (long-press sobre el logo). La suscripción a KioskBus en
            // _onKioskChanged dispara la recarga automática.
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Tarjeta de tienda — Diseño horizontal compacto
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildStoreCard(Store store) {
    // Definimos un pequeño indicador visual dependiendo de si es Diamante u Oro (Opcional)
    Color borderColor = Colors.white10;
    if (store.planType?.toUpperCase() == 'DIAMANTE') {
      borderColor = AppColors.primary.withAlpha(150); // Borde brillante para Diamante
    } else if (store.planType?.toUpperCase() == 'ORO') {
      borderColor = Colors.amber.withAlpha(150); // Borde dorado para Oro
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight, 
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor), 
      ),
      child: Row(
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                store.logoUrl,
                fit: BoxFit.contain, 
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.store,
                  size: 24,
                  color: AppColors.textHint,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        store.name.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Opcional: Pequeño ícono si es diamante
                    if (store.planType?.toUpperCase() == 'DIAMANTE')
                      const Icon(Icons.diamond, color: AppColors.primary, size: 10),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Nivel ${store.floorLevel}',
                  style: const TextStyle(
                    color: AppColors.textSecondaryMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Columna B — Visor 3D del mapa (InAppWebView + model-viewer)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _build3DMapArea() {
    // URL dinámica apuntando al bucket de Supabase según el piso seleccionado
    final modelUrl =
        'https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/mapas/plano_${_selectedFloor.toLowerCase()}.glb';

    const floorLabels = {
      'RG': '🗺 PLANTA BAJA',
      'PL': '🗺 NIVEL PL',
      'C1': '🗺 NIVEL C1',
      'C2': '🗺 NIVEL C2',
      'C3': '🗺 NIVEL C3',
      'C4': '🗺 NIVEL C4',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          // Etiqueta del piso actual
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              floorLabels[_selectedFloor] ?? '🗺 MAPA',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),

          // Visor 3D con MapViewWeb (recarga al cambiar de piso)
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(20),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: MapViewWeb(
                  // GlobalKey<MapViewWebState> para exponer la API imperativa.
                  // El cambio de piso se maneja vía didUpdateWidget (recarga el
                  // HTML inline con la nueva URL del .glb).
                  key: _mapViewKey,
                  modelUrl: modelUrl,
                  avatarUrl: _kAvatarModelUrl,
                  onMapLoaded: () {
                    debugPrint('[MapScreen] Mapa del piso $_selectedFloor cargado');
                    // Sincronizar calibración antes de lanzar la ruta.
                    // Esto garantiza que el modelo GLB esté en la misma posición
                    // y escala que cuando se capturaron los nodos en el editor.
                    final calib = _floorCalibrations[_selectedFloor];
                    if (calib != null) {
                      _mapViewKey.currentState?.setMapCalibration(
                        scale: calib['scale']!,
                        ox: calib['ox']!,
                        oy: calib['oy']!,
                        oz: calib['oz']!,
                        rotY: calib['rotY']!,
                      );
                    }
                    // En Flutter Web, startAvatarRoute recarga el HTML y
                    // onMapLoaded vuelve a dispararse. Sin este check,
                    // llamaríamos _runAvatarRouteTo otra vez → loop infinito.
                    // El bootstrap embebido ya ejecuta la ruta; no hacer nada
                    // más si ya fue despachada.
                    if (_selectedStoreForRoute != null && !_routeDispatched) {
                      _runAvatarRouteTo(_selectedStoreForRoute!);
                    } else if (_selectedStoreForRoute == null) {
                      _placeAvatarAtKiosk();
                    }
                  },
                  onError: () {
                    debugPrint('[MapScreen] Error cargando mapa de $_selectedFloor');
                  },
                  onAvatarArrived: () {
                    debugPrint('[MapScreen] Avatar llegó a destino');
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Columna C — Selector de pisos
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildFloorSelector() {
    final floors = ['RG','PL','C1','C2', 'C3', 'C4'];
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8, top: 0),
          child: Text(
            'PISO',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: floors.length,
            itemBuilder: (context, index) {
              final floor = floors[index];
              final isSelected = _selectedFloor == floor;
              return GestureDetector(
                onTap: () => setState(() => _selectedFloor = floor),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 46,
                  height: 46,
                  margin: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withAlpha(38)
                        : AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      floor,
                      style: TextStyle(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textSecondaryMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
