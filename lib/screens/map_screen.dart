import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
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
import '../features/map/controllers/character_animator_controller.dart';
import '../features/map/controllers/path_renderer_controller.dart';
import '../features/map/services/store_selection_service.dart';
import '../features/map/state/map_state_manager.dart';

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
  State<MapScreen> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {
  // Pisos disponibles (orden = índice del IndexedStack)
  static const List<String> _kAllFloors = ['RG', 'PL', 'C1', 'C2', 'C3', 'C4'];

  // Una key por piso para preservar el estado del WebView entre rebuilds
  late final Map<String, GlobalKey<MapViewWebState>> _floorKeys;

  // Pisos que ya tienen su MapViewWeb instanciado en el árbol (lazy)
  final Set<String> _activatedFloors = {};

  // Cola de precarga de mapas (background)
  final List<String> _preloadQueue = [];
  bool _preloadRunning = false;
  bool _preloadStarted = false;

  // Pisos cuyo onMapLoaded ya disparó (calibración aplicada)
  final Set<String> _loadedFloors = {};

  final SupabaseService _supabaseService = SupabaseService();
  final TextEditingController _searchController = TextEditingController();
  
  // Controladores para las flechas dinámicas de categorías
  final ScrollController _categoryScrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = true;

  // NUEVO ESTADO DE UI
  bool _isSearchVisible = false;

  // Cuando resetToKioskView se llama antes de que _loadData entregue el piso
  // del kiosco, guardamos la intención para ejecutarla cuando llegue el dato.
  bool _pendingKioskFloorSwitch = false;

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

  // Flag para evitar loop en Flutter Web
  bool _routeDispatched = false;

  late final StoreSelectionService _selectionService;
  late final PathRendererController _pathRenderer;
  late final CharacterAnimatorController _characterAnimator;
  late final MapStateManager _stateManager;

  // Calibración del modelo por piso
  Map<String, Map<String, double>> _floorCalibrations = {};

  bool _pendingCenterOnKioskFloor = false;

  @override
  void initState() {
    super.initState();
    _floorKeys = {for (final f in _kAllFloors) f: GlobalKey<MapViewWebState>()};
    _activatedFloors.add(_selectedFloor);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startBackgroundMapPreload(priorityFloor: _selectedFloor);
    });

    _selectionService = StoreSelectionService();
    _pathRenderer = PathRendererController();
    _characterAnimator = CharacterAnimatorController();
    _stateManager = MapStateManager(
      selectionService: _selectionService,
      pathRenderer: _pathRenderer,
      characterAnimator: _characterAnimator,
      routeDispatcher: _dispatchRouteForStore,
      routeStopper: _stopRouteOnAllFloors,
    );

    _loadData();
    _setupRealtime();
    _categoryScrollController.addListener(_updateCategoryScrollState);
    KioskBus.selectionTick.addListener(_onKioskChanged);
  }

  @override
  void dispose() {
    KioskBus.selectionTick.removeListener(_onKioskChanged);
    _realtimeChannel?.unsubscribe();
    _searchController.dispose();
    _categoryScrollController.dispose();
    _stateManager.onViewChanged();
    _stateManager.dispose();
    _selectionService.dispose();
    super.dispose();
  }

  void closeSearch() {
    if (!_isSearchVisible || !mounted) return;
    setState(() {
      _isSearchVisible = false;
      _searchController.clear();
      _selectedCategory = 'Todas';
      _filterStores();
    });
  }

  Future<void> resetToKioskView() async {
    if (!mounted) return;
    final kioskFloor = _normalizeFloorCode(_kioskFloorLevel);
    final targetFloor = kioskFloor.isNotEmpty ? kioskFloor : _selectedFloor;

    if (mounted) {
      setState(() {
        _isSearchVisible = false;
        _searchController.clear();
        _selectedCategory = 'Todas';
        _selectedStoreForRoute = null;
        _routeDispatched = false;
        _pendingCenterOnKioskFloor = true;
        if (kioskFloor.isEmpty) {
          // Piso del kiosco aún no disponible (carrera con _loadData).
          // Cuando llegue el dato, _prioritizeKioskFloorPreload lo aplica.
          _pendingKioskFloorSwitch = true;
        } else if (targetFloor != _selectedFloor) {
          _selectedFloor = targetFloor;
          _activatedFloors.add(targetFloor);
        }
      });
      _filterStores();
      // Si el piso objetivo ya estaba activo y falló (error congelado),
      // didUpdateWidget no se dispara → forzamos el retry manualmente.
      _floorKeys[targetFloor]?.currentState?.retryLoad();
    }

    _stateManager.onViewChanged();
    await _stopRouteOnAllFloors();
    await _floorKeys[targetFloor]?.currentState?.centerTopView();
  }

  void _onKioskChanged() {
    debugPrint('[MapScreen] KioskBus → recargando datos por cambio de kiosco');
    _selectedStoreForRoute = null;
    _stateManager.onViewChanged();
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

      final catsResponse = await client.from('categories').select().order('name');
      final stores = await _supabaseService.getStores();

      await box.put('cached_categories', catsResponse);
      final storesJson = stores.map((s) => s.toJson()).toList();
      await box.put('cached_stores', storesJson);

      final routes = await _supabaseService.getMapRoutes();
      final nodes = await _supabaseService.getMapNodes();
      final edges = await _supabaseService.getMapEdges();
      final polygons = await _supabaseService.getMapPolygons();

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
        debugPrint('[MapScreen] map_calibration no disponible: $e');
      }

      final prefs = await SharedPreferences.getInstance();
      final kioskId = prefs.getString('kiosk_id');

      String? kioskFloor;
      String? kioskNodeId;
      if (kioskId == null) {
        debugPrint('[MapScreen] ⚠ No hay kiosk_id en SharedPreferences.');
      } else {
        final kioskData = await _supabaseService.getKioskById(kioskId);
        if (kioskData == null) {
          debugPrint('[MapScreen] ⚠ Kiosco "$kioskId" no existe en Supabase.');
        } else if (kioskData['node_id'] == null || (kioskData['node_id'] as String).isEmpty) {
          debugPrint('[MapScreen] ⚠ El kiosco "$kioskId" existe pero tiene node_id NULL.');
        } else {
          kioskNodeId = kioskData['node_id'] as String;
          final nodeMatch = nodes.where((n) => n.id == kioskNodeId).toList();
          if (nodeMatch.isEmpty) {
            debugPrint('[MapScreen] ⚠ node_id "$kioskNodeId" del kiosco no está en map_nodes.');
          } else {
            kioskFloor = nodeMatch.first.floorLevel;
          }
        }
      }

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

      _prioritizeKioskFloorPreload();

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
        final stores = storesJson.map((s) => Store.fromJson(Map<String, dynamic>.from(s))).toList();
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

  String _normalizeFloorCode(String? floor) {
    final raw = floor?.trim().toUpperCase() ?? '';
    if (!_kAllFloors.contains(raw)) return '';
    return raw;
  }

  void _enqueueFloorPreload(String floor, {bool front = false}) {
    final code = _normalizeFloorCode(floor);
    if (code.isEmpty) return;
    if (_activatedFloors.contains(code)) return;
    if (_preloadQueue.contains(code)) {
      if (front) {
        _preloadQueue.remove(code);
        _preloadQueue.insert(0, code);
      }
      return;
    }
    if (front) {
      _preloadQueue.insert(0, code);
    } else {
      _preloadQueue.add(code);
    }
  }

  Future<void> _drainPreloadQueue() async {
    if (_preloadRunning) return;
    _preloadRunning = true;
    while (mounted && _preloadQueue.isNotEmpty) {
      final floor = _preloadQueue.removeAt(0);
      if (!_activatedFloors.contains(floor)) {
        setState(() {
          _activatedFloors.add(floor);
        });
        await Future.delayed(const Duration(milliseconds: 120));
      }
    }
    _preloadRunning = false;
  }

  void _startBackgroundMapPreload({String? priorityFloor}) {
    if (_preloadStarted) return;
    _preloadStarted = true;
    if (priorityFloor != null && priorityFloor.isNotEmpty) {
      _enqueueFloorPreload(priorityFloor, front: true);
    }
    for (final floor in _kAllFloors) {
      _enqueueFloorPreload(floor);
    }
    _drainPreloadQueue();
  }

  void _prioritizeKioskFloorPreload() {
    final kioskFloor = _normalizeFloorCode(_kioskFloorLevel);
    if (kioskFloor.isEmpty) return;

    // Si resetToKioskView se llamó antes de que llegara el piso del kiosco,
    // ahora que lo sabemos: cambiamos el piso visible.
    if (_pendingKioskFloorSwitch && mounted && kioskFloor != _selectedFloor) {
      _pendingKioskFloorSwitch = false;
      setState(() {
        _selectedFloor = kioskFloor;
        _activatedFloors.add(kioskFloor);
        _pendingCenterOnKioskFloor = true;
      });
      // Dar un frame para que el widget esté en el árbol antes de retryLoad.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _floorKeys[kioskFloor]?.currentState?.retryLoad();
      });
    } else {
      _pendingKioskFloorSwitch = false;
    }

    if (!_preloadStarted) {
      _startBackgroundMapPreload(priorityFloor: kioskFloor);
      return;
    }
    _enqueueFloorPreload(kioskFloor, front: true);
    _drainPreloadQueue();
  }

  IconData _getIconData(String? iconName) {
    final normalized = iconName?.trim().toLowerCase() ?? '';
    switch (normalized) {
      case 'comida': case 'feria': case 'restaurante': case 'fastfood': return Icons.fastfood_rounded;
      case 'cafe': case 'postres': case 'cafeteria': case 'local_cafe': return Icons.local_cafe_rounded;
      case 'heladeria': case 'helados': return Icons.icecream_rounded;
      case 'ropa': case 'moda': case 'boutique': case 'checkroom': return Icons.checkroom_rounded;
      case 'zapatos': case 'calzado': case 'zapateria': return Icons.roller_skating_rounded;
      case 'tecnologia': case 'electronica': case 'celulares': case 'devices': return Icons.devices_rounded;
      case 'videojuegos': case 'juegos': case 'sports_esports': return Icons.sports_esports_rounded;
      case 'belleza': case 'maquillaje': case 'spa': case 'peluqueria': return Icons.spa_rounded;
      case 'salud': case 'farmacia': case 'clinica': case 'local_hospital': return Icons.local_hospital_rounded;
      case 'optica': case 'lentes': return Icons.remove_red_eye_rounded;
      case 'cine': case 'peliculas': case 'movie': return Icons.movie_rounded;
      case 'ninos': case 'jugueteria': case 'infantil': case 'child_friendly': return Icons.child_friendly_rounded;
      case 'mascotas': case 'veterinaria': case 'pets': return Icons.pets_rounded;
      case 'compras': case 'shopping': case 'shopping_bag': case 'tienda': return Icons.shopping_bag_rounded;
      case 'supermercado': case 'bodegon': case 'market': return Icons.shopping_cart_rounded;
      case 'banco': case 'cajero': case 'finanzas': return Icons.account_balance_rounded;
      case 'servicios': case 'reparacion': case 'home_repair_service': return Icons.home_repair_service_rounded;
      case 'deportes': case 'gimnasio': case 'fitness_center': return Icons.fitness_center_rounded;
      case 'joyeria': case 'relojes': return Icons.watch_rounded;
      case 'hogar': case 'muebles': return Icons.chair_rounded;
      case 'musica': case 'instrumentos': return Icons.music_note_rounded;
      default: return Icons.storefront_rounded;
    }
  }

  int _getPlanPriority(String? plan) {
    if (plan == null) return 4;
    switch (plan.toUpperCase()) {
      case 'DIAMANTE': return 1;
      case 'ORO': return 2;
      case 'IA_PERFORMANCE': return 3;
      default: return 4;
    }
  }

  void _filterStores() {
    String query = _searchController.text.toLowerCase().trim();
    
    setState(() {
      _filteredStores = _allStores.where((store) {
        final name = store.name.toLowerCase();
        final category = store.category.toLowerCase();
        final description = store.description?.toLowerCase() ?? ''; 

        final matchesQuery = query.isEmpty || name.contains(query) || category.contains(query) || description.contains(query);
        final matchesCategory = _selectedCategory == 'Todas' || category.contains(_selectedCategory.toLowerCase());

        return matchesQuery && matchesCategory;
      }).toList();

      _filteredStores.sort((a, b) {
        int priorityA = _getPlanPriority(a.planType);
        int priorityB = _getPlanPriority(b.planType);

        if (priorityA != priorityB) {
          return priorityA.compareTo(priorityB);
        }
        return a.name.compareTo(b.name);
      });
    });
  }

  MapRoute? _findFirstRouteForStore(Store store) {
    if (_currentKioskId != null) {
      for (final route in _allRoutes) {
        if (route.destType == 'store' && route.destId == store.id && route.originType == 'kiosk' && route.originId == _currentKioskId) {
          return route;
        }
      }
    }
    for (final route in _allRoutes) {
      if (route.destType == 'store' && route.destId == store.id) return route;
    }
    for (final route in _allRoutes) {
      if (route.originType == 'store' && route.originId == store.id) return route;
    }
    return null;
  }

  MapPolygon? _findPolygonForStore(Store store) {
    for (final polygon in _allPolygons) {
      if (polygon.storeId == store.id) return polygon;
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
    _selectionService.select(store);
  }

  Future<void> _stopRouteOnAllFloors() async {
    for (final floor in _activatedFloors) {
      final mapView = _floorKeys[floor]?.currentState;
      if (mapView == null) continue;
      try {
        await mapView.stopAvatarRoute();
      } catch (e) {
        debugPrint('[MapScreen] stopAvatarRoute($floor) falló: $e');
      }
    }
    _routeDispatched = false;
  }

  Future<bool> _dispatchRouteForStore(Store store) async {
    final targetFloorName = store.floorLevel;

    setState(() {
      _selectedStoreForRoute = store;
      _routeDispatched = false; 
    });

    if (targetFloorName != null && targetFloorName != _selectedFloor) {
      setState(() {
        _selectedFloor = targetFloorName;
        _activatedFloors.add(targetFloorName);
      });
      if (_loadedFloors.contains(targetFloorName)) {
        return _runAvatarRouteTo(store);
      }
      return true;
    }

    return _runAvatarRouteTo(store);
  }

  Future<bool> _runAvatarRouteTo(Store store) async {
    final nav = _navService;
    if (nav == null || !nav.isReady) {
      debugPrint('[MapScreen] Servicio de navegación no listo aún.');
      return false;
    }
    if (_currentKioskNodeId == null || _currentKioskNodeId!.isEmpty) {
      debugPrint('[MapScreen] No se puede navegar: kiosk_id sin node_id asignado.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El kiosco actual no tiene un nodo de mapa asignado.'),
            backgroundColor: AppColors.error,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return false;
    }

    final currentFloorNum = _selectedFloor;
    final route = nav.routeFromKioskToStore(
      kioskNodeId: _currentKioskNodeId,
      store: store,
      currentFloorLevel: currentFloorNum,
    );

    if (route.isEmpty || route.waypoints.isEmpty) {
      debugPrint('[MapScreen] Sin ruta disponible: ${route.errorMessage ?? "desconocido"}');
      if (mounted && route.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(route.errorMessage!),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      _placeAvatarAtKiosk();
      return false;
    }

    final mapView = _floorKeys[_selectedFloor]?.currentState;
    _routeDispatched = true;
    await mapView?.startAvatarRoute(route.waypoints);
    return true;
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
    _floorKeys[_selectedFloor]?.currentState?.setAvatarAtWorld(world.x, world.y, world.z);
  }

  void _onFloorMapLoaded(String floor) {
    debugPrint('[MapScreen] Mapa del piso $floor cargado');
    _loadedFloors.add(floor);

    final calib = _floorCalibrations[floor];
    if (calib != null) {
      _floorKeys[floor]?.currentState?.setMapCalibration(
        scale: calib['scale']!,
        ox: calib['ox']!,
        oy: calib['oy']!,
        oz: calib['oz']!,
        rotY: calib['rotY']!,
      );
    }

    if (floor != _selectedFloor) return;

    if (_pendingCenterOnKioskFloor) {
      _pendingCenterOnKioskFloor = false;
      _floorKeys[floor]?.currentState?.centerTopView();
    }

    if (_selectedStoreForRoute != null && !_routeDispatched) {
      _runAvatarRouteTo(_selectedStoreForRoute!);
    }
  }

  // ============================================================================
  // BUILD PRINCIPAL 
  // ============================================================================
@override
  Widget build(BuildContext context) {
    debugPrint('[MapScreen][BUILD] _isSearchVisible=$_isSearchVisible _isLoading=$_isLoading allStores=${_allStores.length} filtered=${_filteredStores.length}');
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ScreenAdBanners(
        showTop: false,
        showBottom: false,
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: AppColors.background,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  // 1. Mapa 3D ocupa todo el espacio
                  Positioned.fill(child: _build3DMapArea()),

                  // 2. Overlay transparente: cierra la búsqueda al tocar fuera del panel.
                  //    Solo aparece cuando _isSearchVisible es true.
                  if (_isSearchVisible)
                    Positioned.fill(
                      child: PointerInterceptor(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: closeSearch,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),

                  // 3. Overlay: lupa + buscador + categorías + logos — sobre el mapa.
                  // • PointerInterceptor: en Flutter Web coloca un div HTML encima del
                  //   iframe para capturar clics antes de que el browser los entregue al iframe.
                  // • Listener(opaque): en Android reclama el hit-test antes de que
                  //   AndroidViewSurface (InAppWebView) lo intercepte.
                  // Sus hijos (GestureDetector, TextField, etc.) reciben eventos normalmente.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: PointerInterceptor(
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildPremiumLogosAndSearchRow(),
                            _buildSearchPanel(),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 4. Selector de pisos flotante
                  Positioned(
                    right: 8,
                    bottom: 16,
                    width: 32,
                    child: PointerInterceptor(
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        child: _buildFloorSelector(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchPanel() {
    debugPrint('[MapScreen][PANEL] rebuild — visible=$_isSearchVisible');
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: _isSearchVisible ? _buildSearchPanelContent() : const SizedBox.shrink(),
    );
  }

  Widget _buildSearchPanelContent() {
    debugPrint('[MapScreen][PANEL] MOSTRANDO contenido — filteredStores=${_filteredStores.length}');
    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Categorías
          _buildCategoryRow(),
          const SizedBox(height: 4),
          // Logos de TODAS las tiendas (incluye premium) ordenadas por plan
          _buildAllStoresLogosRow(),
        ],
      ),
    );
  }
  
  Widget _buildFallbackLogo(String storeName) {
    // Tomamos hasta las primeras 2 letras del nombre
    String initials = storeName.trim().isNotEmpty
        ? storeName.trim().substring(0, storeName.trim().length > 1 ? 2 : 1).toUpperCase()
        : '??';

    return Container(
      color: AppColors.surfaceLight, // Fondo sutil
      alignment: Alignment.center,
      child: Text(
        initials,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w900,
          fontSize: 16,
        ),
      ),
    );
  }

  // ============================================================================
  // WIDGETS AUXILIARES
  // ============================================================================
Widget _buildPremiumLogosAndSearchRow() {
    final premiumStores = _allStores.where((store) {
      return store.planType != null && store.planType!.trim().isNotEmpty;
    }).toList()
      ..sort((a, b) => _getPlanPriority(a.planType).compareTo(_getPlanPriority(b.planType)));

    debugPrint('[MapScreen][TOPBAR] rebuild — visible=$_isSearchVisible premium=${premiumStores.length}');

    return Container(
      height: 65,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final next = !_isSearchVisible;
              debugPrint('[MapScreen][LUPA] TAP recibido — cambiando a visible=$next');
              setState(() {
                _isSearchVisible = next;
                if (!next) {
                  _searchController.clear();
                  _selectedCategory = 'Todas';
                  _filterStores();
                }
              });
              debugPrint('[MapScreen][LUPA] setState hecho — _isSearchVisible=$_isSearchVisible');
            },
            child: Container(
              width: 44,
              height: 44,
              margin: const EdgeInsets.only(left: 4, right: 8),
              decoration: BoxDecoration(
                // Sin boxShadow: evita conflicto de compositing con InAppWebView
                color: _isSearchVisible ? AppColors.secondary : Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _isSearchVisible ? Icons.close_rounded : Icons.search_rounded,
                color: _isSearchVisible ? Colors.white : AppColors.primary,
                size: 22,
              ),
            ),
          ),
          // Cuando la búsqueda está abierta: barra de texto.
          // Cuando está cerrada: logos de tiendas con plan.
          Expanded(
              child: _isSearchVisible
              ? Container(
                  // La caja contenedora aporta la misma sombra sutil que las categorías
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            onChanged: (_) => _filterStores(),
            style: TextStyle(
              color: Colors.grey.shade800, // Un gris oscuro es más suave a la vista que negro puro
              fontSize: 14,
              fontWeight: FontWeight.w500, // SemiBold ligero para mejor legibilidad
            ),
            decoration: InputDecoration(
              hintText: 'Busca tienda, categoría...',
              hintStyle: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 14,
              ),
              prefixIcon: Icon(
                Icons.search_rounded, // search_rounded se ve más moderno
                color: AppColors.primary.withOpacity(0.8), // Primario ligeramente suavizado
                size: 20,
              ),
              filled: true,
              fillColor: Colors.white, // Resalta limpiamente sobre el fondo general
              
              // Borde cuando NO está seleccionado (estático)
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.grey.shade200,
                  width: 1.2,
                ),
              ),
              
              // Borde cuando el usuario hace tap y está escribiendo (activo)
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppColors.primary.withOpacity(0.5), // Tinte primario elegante
                  width: 1.2,
                ),
              ),
              
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              isDense: true, // Mantiene el TextField compacto para que no altere tu layout
            ),
          ),
        )
      : (premiumStores.isEmpty || _isLoading
          ? const SizedBox.shrink()
          : ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: premiumStores.length,
              itemBuilder: (context, index) => _buildStoreLogo(premiumStores[index]),
            )),
          ),
        ],
      ),
    );
  }

  Widget _buildAllStoresLogosRow() {
    if (_filteredStores.isEmpty || _isLoading) return const SizedBox.shrink();

    // Mismo alto y padding vertical que la fila de logos premium del top bar
    return SizedBox(
      height: 65,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: _filteredStores.length,
        itemBuilder: (context, index) => _buildStoreLogo(_filteredStores[index]),
      ),
    );
  }

  Widget _buildStoreLogo(Store store) {
    Color borderColor = Colors.white10;
    if (store.planType?.toUpperCase() == 'DIAMANTE') {
      borderColor = AppColors.primary.withAlpha(150);
    } else if (store.planType?.toUpperCase() == 'ORO') {
      borderColor = Colors.amber.withAlpha(150);
    }

    return GestureDetector(
      onTap: () => _onStoreTapped(store),
      child: Container(
        width: 48,
        height: 48,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 2),
          boxShadow: [
            BoxShadow(
              color: borderColor.withOpacity(0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: store.logoUrl.trim().isNotEmpty &&
                  store.logoUrl.startsWith('http') &&
                  !store.logoUrl.contains('dummyimage.com')
              ? Image.network(
                  store.logoUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => _buildFallbackLogo(store.name),
                )
              : _buildFallbackLogo(store.name),
        ),
      ),
    );
  }
  
Widget _buildCategoryRow() {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _canScrollLeft ? 1.0 : 0.0,
            child: GestureDetector(
              onTap: _canScrollLeft
                  ? () {
                      _categoryScrollController.animateTo(
                        _categoryScrollController.offset - 250,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    }
                  : null,
              child: Container(
                color: Colors.transparent,
                padding: const EdgeInsets.only(left: 16, right: 8),
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  // Un gris un poco más definido para que no se pierda en el blanco
                  color: Colors.grey.shade500, 
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
                    curve: Curves.easeOut, // Transición más fluida
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), // Ajuste vertical sutil para la sombra
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      // Fondo: Translúcido si está seleccionado, blanco puro si no
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      // Borde: Usa el color primario si está seleccionado, gris muy suave si no
                      border: Border.all(
                        color: isSelected 
                            ? AppColors.primary.withOpacity(0.5) 
                            : Colors.grey.shade200,
                        width: 1.2,
                      ),
                      // Sombra: Muy sutil para despegar el botón del fondo blanco
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          cat['icon'] as IconData,
                          color: isSelected 
                              ? AppColors.primary 
                              : Colors.grey.shade600,
                          size: 16, // Ligeramente más pequeño para verse más refinado
                        ),
                        const SizedBox(width: 8),
                        Text(
                          cat['name'] as String,
                          style: TextStyle(
                            color: isSelected 
                                ? AppColors.primary 
                                : Colors.grey.shade700,
                            // w600 (SemiBold) es más elegante que 'bold' puro
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            fontSize: 13,
                            letterSpacing: 0.2, // El espaciado de letras da un toque premium
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
              onTap: _canScrollRight
                  ? () {
                      _categoryScrollController.animateTo(
                        _categoryScrollController.offset + 250,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    }
                  : null,
              child: Container(
                color: Colors.transparent,
                padding: const EdgeInsets.only(left: 8, right: 16),
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 18,
                  color: Colors.grey.shade500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

Widget _build3DMapArea() {
    // Retornamos directamente el IndexedStack, sin Textos ni contenedores decorativos
    return IndexedStack(
      index: _kAllFloors.indexOf(_selectedFloor),
      children: _kAllFloors.map((floor) {
        if (!_activatedFloors.contains(floor)) return const SizedBox.shrink();
        final modelUrl = 'https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/mapas/plano_${floor.toLowerCase()}.glb';
        return MapViewWeb(
          key: _floorKeys[floor],
          modelUrl: modelUrl,
          avatarUrl: _kAvatarModelUrl,
          isActive: floor == _selectedFloor,
          onMapLoaded: () => _onFloorMapLoaded(floor),
          onError: () {
            debugPrint('[MapScreen] Error cargando mapa de $floor — reintentando en 4 s');
            Future.delayed(const Duration(seconds: 4), () {
              if (!mounted || _loadedFloors.contains(floor)) return;
              _floorKeys[floor]?.currentState?.retryLoad();
            });
          },
          onPathRendered: (steps) {
            if (floor != _selectedFloor) return;
            _stateManager.notifyPathRendered(stepCount: steps);
          },
          onAvatarArrived: () {
            if (floor != _selectedFloor) return;
            _stateManager.notifyCharacterArrived();
          },
        );
      }).toList(),
    );
  }

Widget _buildFloorSelector() {
    final floors = ['RG','PL','C1','C2', 'C3', 'C4'];
    return Column(
      mainAxisAlignment: MainAxisAlignment.end, // Alinear hacia abajo
      mainAxisSize: MainAxisSize.min, // Ocupar solo el espacio necesario
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 2),
          child: Container(
            width: 32, // Mismo ancho que los botones
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight.withAlpha(150), // Fondo semi-transparente
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text(
                'PISO',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 7, // Ligeramente más pequeño para el contenedor
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
        Flexible(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true, // La lista se encoge a su contenido
            physics: const NeverScrollableScrollPhysics(), // Desactivar scroll si no hace falta
            itemCount: floors.length,
            itemBuilder: (context, index) {
              final floor = floors[index];
              final isSelected = _selectedFloor == floor;
              return GestureDetector(
                onTap: () {
                  if (_selectedFloor == floor) return;
                  setState(() {
                    _selectedFloor = floor;
                    _activatedFloors.add(floor);
                  });
                  if (_loadedFloors.contains(floor)) {
                    final active = _selectedStoreForRoute;
                    if (active != null) {
                      _selectionService.select(active);
                    } else {
                      _stateManager.onViewChanged();
                      _floorKeys[_selectedFloor]?.currentState?.hideAvatar();
                    }
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 32, // Botones compactos
                  height: 32,
                  margin: const EdgeInsets.only(bottom: 6), // Margen solo abajo
                  decoration: BoxDecoration(
                    // Color semi-transparente SIEMPRE
                    color: isSelected 
                        ? AppColors.primary.withAlpha(200) 
                        : AppColors.surfaceLight.withAlpha(150),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      floor,
                      style: TextStyle(
                        color: isSelected ? Colors.white : AppColors.textPrimary,
                        fontSize: 10,
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

Widget _buildStoreCard(Store store) {
    Color borderColor = Colors.white10;
    if (store.planType?.toUpperCase() == 'DIAMANTE') {
      borderColor = AppColors.primary.withAlpha(150);
    } else if (store.planType?.toUpperCase() == 'ORO') {
      borderColor = Colors.amber.withAlpha(150);
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
              // NUEVA VALIDACIÓN: Aplicada también a las tarjetas
              child: store.logoUrl.trim().isNotEmpty && 
                     store.logoUrl.startsWith('http') &&
                     !store.logoUrl.contains('dummyimage.com')
                  ? Image.network(
                      store.logoUrl,
                      fit: BoxFit.contain, 
                      errorBuilder: (_, __, ___) => _buildFallbackLogo(store.name),
                    )
                  : _buildFallbackLogo(store.name),
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
                    if (store.planType?.toUpperCase() == 'DIAMANTE')
                      const Icon(Icons.diamond, color: AppColors.primary, size: 10),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Nivel ${store.floorLevel}',
                  style: const TextStyle(color: AppColors.textSecondaryMuted, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}