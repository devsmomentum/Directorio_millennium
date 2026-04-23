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
import '../widgets/screen_ad_banners.dart';
import '../widgets/map_view_web.dart';
import '../theme/app_theme.dart';

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
  int? _kioskFloorLevel;
  List<MapRoute> _allRoutes = [];
  List<MapPolygon> _allPolygons = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    _setupRealtime();
    _categoryScrollController.addListener(_updateCategoryScrollState);
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _searchController.dispose();
    _categoryScrollController.dispose();
    super.dispose();
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
      final polygons = await _supabaseService.getMapPolygons();

      final prefs = await SharedPreferences.getInstance();
      final kioskId = prefs.getString('kiosk_id');

      int? kioskFloor;
      if (kioskId != null) {
        final kioskData = await _supabaseService.getKioskById(kioskId);
        if (kioskData != null && kioskData['node_id'] != null) {
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
        final description = store.description?.toLowerCase() ?? ''; 

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

  int _getStoreFloorNum(Store store) {
    return _floorNameToNum[store.floorLevel] ?? 1;
  }

  void _onStoreTapped(Store store) {
    AnalyticsService().logEvent(
      eventType: 'click',
      module: 'directory',
      itemName: store.name,
      itemId: store.id,
    );
    // TODO: Actualizar Columna B con la ubicación de esta tienda
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

            // Zona secreta: long-press esquina superior derecha
            Positioned(
              top: 0,
              right: 0,
              child: _KioskLongPressZone(
                onKioskSelected: () {
                  _loadData(isSilent: true);
                },
              ),
            ),
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
                  // ValueKey fuerza reconstrucción al cambiar de piso
                  key: ValueKey(_selectedFloor),
                  modelUrl: modelUrl,
                  onMapLoaded: () {
                    debugPrint('[MapScreen] Mapa del piso $_selectedFloor cargado');
                  },
                  onError: () {
                    debugPrint('[MapScreen] Error cargando mapa de $_selectedFloor');
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
    final floors = ['C4', 'C3', 'C2', 'C1', 'RG'];
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

    _progressTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (mounted) {
        setState(() {
          _progress = (_progress + 0.01).clamp(0.0, 1.0);
        });
      }
    });

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
                const Icon(
                  Icons.tv_rounded,
                  color: Color(0xFFFF007A),
                  size: 28,
                ),
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
              style: TextStyle(
                color: Colors.white54,
                fontSize: 14,
                height: 1.4,
              ),
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
                  onTap: () => setState(() => _selectedKioskId = kiosk['id']),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFFF007A).withAlpha(38)
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
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withAlpha(51),
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
                onPressed: _isLoading || _selectedKioskId == null
                    ? null
                    : _selectKiosk,
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