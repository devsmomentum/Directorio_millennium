import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart'; // 🚀 ESTA ES LA LÍNEA QUE FALTA

import '../services/supabase_service.dart';
import '../models/store.dart';
import '../models/map_node.dart';
import '../models/map_edge.dart';
import '../services/analytics_service.dart';
import '../utils/pathfinder.dart';
import '../widgets/route_painter.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _StoreDirectoryScreenState extends State<MapScreen> {
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

  @override
  void initState() {
    super.initState();
    _loadData(); // Llama a la nueva función híbrida (Internet -> Caché)
    _setupRealtime(); // Iniciamos la escucha al abrir la pantalla
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _searchController.dispose();
    super.dispose();
  }

  void _setupRealtime() {
    final client = Supabase.instance.client;

    // 🚀 BLINDAJE ANTI-ZOMBIES: Destruimos el canal viejo si existe antes de crear uno nuevo
    client.removeChannel(client.channel('public-kiosk-updates'));

    _realtimeChannel = client.channel('public-kiosk-updates')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'stores',
        callback: (payload) {
          debugPrint(
            '🔄 Cambio detectado en TIENDAS. Actualizando directorio en segundo plano...',
          );
          _loadData(isSilent: true);
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'categories',
        callback: (payload) {
          debugPrint(
            '🔄 Cambio detectado en CATEGORÍAS. Actualizando directorio en segundo plano...',
          );
          _loadData(isSilent: true);
        },
      )
      ..subscribe();
  }

  Future<void> _loadData({bool isSilent = false}) async {
    try {
      final client = Supabase.instance.client;
      // 🚀 CACHÉ EN RAM: Abrimos la caja ultrarrápida de Hive
      final box = Hive.box('kiosk_cache');

      if (!isSilent && mounted) {
        setState(() => _isLoading = true);
      }

      final catsResponse = await client
          .from('categories')
          .select()
          .order('name');
      final stores = await _supabaseService.getStores();

      // 🚀 GUARDADO NATIVO: Sin jsonEncode, no bloquea el hilo principal (0 tirones)
      await box.put('cached_categories', catsResponse);
      final storesJson = stores.map((s) => s.toJson()).toList();
      await box.put('cached_stores', storesJson);

      _updateUIWithData(catsResponse, stores);
    } catch (e) {
      debugPrint('⚠️ Error de red detectado: $e');
      debugPrint('🔄 Intentando cargar desde la caché local de Hive...');
      await _loadFromCache();
    }
  }

  Future<void> _loadFromCache() async {
    try {
      // 🚀 LECTURA EN MILISEGUNDOS: Sacamos los datos de Hive
      final box = Hive.box('kiosk_cache');
      final catsData = box.get('cached_categories');
      final storesData = box.get('cached_stores');

      if (catsData != null && storesData != null) {
        // Casteamos directamente de vuelta a listas sin usar jsonDecode
        final catsResponse = List<dynamic>.from(catsData);
        final storesJson = List<dynamic>.from(storesData);

        final stores = storesJson
            .map((s) => Store.fromJson(Map<String, dynamic>.from(s)))
            .toList();

        debugPrint(
          '✅ Directorio cargado exitosamente desde modo Offline (Hive).',
        );
        _updateUIWithData(catsResponse, stores);
      } else {
        throw Exception("No hay caché disponible en Hive.");
      }
    } catch (e) {
      debugPrint('❌ Fallo total: Sin internet y sin caché. Error: $e');
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

  // 🚀 NUEVO: DICCIONARIO INTELIGENTE DE ÍCONOS
  IconData _getIconData(String? iconName) {
    // 1. Normalizamos el texto: quitamos espacios y lo pasamos a minúsculas
    // Así, si el admin escribe "  Comida " o "COMIDA", Flutter lo leerá igual.
    final normalized = iconName?.trim().toLowerCase() ?? '';

    switch (normalized) {
      // 🍔 COMIDA Y BEBIDA
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

      // 👕 MODA Y ROPA
      case 'ropa':
      case 'moda':
      case 'boutique':
      case 'checkroom':
        return Icons.checkroom_rounded;
      case 'zapatos':
      case 'calzado':
      case 'zapateria':
        return Icons
            .roller_skating_rounded; // Ícono más representativo para calzado

      // 📱 TECNOLOGÍA Y ELECTRÓNICA
      case 'tecnologia':
      case 'electronica':
      case 'celulares':
      case 'devices':
        return Icons.devices_rounded;
      case 'videojuegos':
      case 'juegos':
      case 'sports_esports':
        return Icons.sports_esports_rounded;

      // 💄 BELLEZA Y SALUD
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

      // 🎈 ENTRETENIMIENTO Y NIÑOS
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

      // 🛍️ COMPRAS GENERALES Y SERVICIOS
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

      // 🏠 POR DEFECTO (Si el admin escribe algo que no está en la lista)
      default:
        return Icons
            .storefront_rounded; // Una tiendita se ve mucho mejor que un ícono de error
    }
  }

  void _filterStores() {
    String query = _searchController.text.toLowerCase();
    setState(() {
      _filteredStores = _allStores.where((store) {
        final matchesQuery = store.name.toLowerCase().contains(query);
        final matchesCategory =
            _selectedCategory == 'Todas' ||
            store.category.toLowerCase().contains(
              _selectedCategory.toLowerCase(),
            );
        return matchesQuery && matchesCategory;
      }).toList();
    });
  }

  void _showStoreDetail(Store store) {
    // 🚀 NUEVO: ANALÍTICA PARA CLIC EN TIENDA
    AnalyticsService().logEvent(
      eventType: 'click',
      module: 'directory',
      itemName: store.name,
      itemId: store.id,
    );

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
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
                child: Image.network(
                  store.logoUrl,
                  height: 250,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 250,
                    color: Colors.white10,
                    child: const Icon(
                      Icons.store,
                      size: 80,
                      color: Colors.white24,
                    ),
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
                    const Text(
                      "Dirígete al mapa interactivo para obtener la ruta más rápida hacia esta tienda desde tu ubicación actual.",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 40),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF007A),
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            onPressed: () {
                              Navigator.pop(context); // Cierra el detalle
                              // 🚀 ABRE EL MAPA ANIMADO
                              _showAnimatedMap(store);
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

  void _showAnimatedMap(Store targetStore) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AnimatedMapModal(targetStore: targetStore),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Column(
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
                hintStyle: TextStyle(color: Colors.white30),
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
                    // 🚀 NUEVO: ANALÍTICA PARA CLIC EN CATEGORÍA
                    AnalyticsService().logEvent(
                      eventType: 'filter',
                      module: 'directory',
                      itemName: 'Categoría: ${cat['name']}',
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
                          color: isSelected ? Colors.white : Colors.white54,
                          size: 30,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          cat['name'],
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white54,
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
                    child: CircularProgressIndicator(color: Color(0xFFFF007A)),
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
                        onTap: () => _showStoreDetail(_filteredStores[index]),
                        child: _buildStoreCard(_filteredStores[index]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreCard(Store store) {
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
                    Text(
                      'PISO ${store.floorLevel} • LOCAL ${store.localNumber}',
                      style: const TextStyle(
                        color: Color(0xFFFF007A),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
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

class _MapScreenState extends _StoreDirectoryScreenState {}

// ============================================================================
// 🚀 WIDGET DEL MAPA ANIMADO HÍBRIDO (MACRO ➡️ MICRO)
// ============================================================================
class _AnimatedMapModal extends StatefulWidget {
  final Store targetStore;
  const _AnimatedMapModal({Key? key, required this.targetStore})
    : super(key: key);

  @override
  State<_AnimatedMapModal> createState() => _AnimatedMapModalState();
}

// 🚀 Usamos TickerProviderStateMixin (Arreglado el nombre para Multi-Animation)
class _AnimatedMapModalState extends State<_AnimatedMapModal>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  String _errorMessage = '';

  List<MapNode> _nodes = [];
  List<MapEdge> _edges = [];
  List<MapNode> _calculatedRoute = [];

  late AnimationController _animationController;

  late TransformationController _transformationController;
  late AnimationController _cameraAnimationController;
  Size _currentViewSize = Size.zero;
  bool _isInitialCameraSet = false; // Flag para forzar Macro al inicio

  final Map<String, String> _floorImages = {
    'C4': 'https://dummyimage.com/2000x2000/1A1A1A/FF007A&text=Plano+Nivel+C4',
    'C3': 'https://dummyimage.com/2000x2000/1A1A1A/FF007A&text=Plano+Nivel+C3',
    'C2': 'https://dummyimage.com/2000x2000/1A1A1A/FF007A&text=Plano+Nivel+C2',
    'C1': 'https://dummyimage.com/2000x2000/1A1A1A/FF007A&text=Plano+Nivel+C1',
    'RG':
        'https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/mapas/plano_rg.png',
  };

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

    _calculateRoute();
  }

  Future<void> _calculateRoute() async {
    try {
      final client = Supabase.instance.client;
      final prefs = await SharedPreferences.getInstance();
      final currentKioskId = prefs.getString('kiosk_id');

      if (currentKioskId == null) {
        throw Exception(
          "Este equipo no ha sido vinculado a un Kiosco físico (Modo MDM).",
        );
      }

      final kioskData = await client
          .from('kiosks')
          .select('node_id')
          .eq('id', currentKioskId)
          .maybeSingle();
      if (kioskData == null || kioskData['node_id'] == null) {
        throw Exception(
          "El kiosco actual no tiene un punto asignado en el mapa.",
        );
      }
      final String startNodeId = kioskData['node_id'];

      final String? targetNodeId = widget.targetStore.nodeId;
      if (targetNodeId == null || targetNodeId.isEmpty) {
        throw Exception("Esta tienda aún no tiene ubicación mapeada.");
      }

      final floorMap = {'C4': 5, 'C3': 4, 'C2': 3, 'C1': 2, 'RG': 1};
      int floorNum = floorMap[widget.targetStore.floorLevel] ?? 1;

      final nodesData = await client
          .from('map_nodes')
          .select()
          .eq('floor_level', floorNum);
      final edgesData = await client.from('map_edges').select();

      _nodes = (nodesData as List).map((n) => MapNode.fromJson(n)).toList();
      _edges = (edgesData as List).map((e) => MapEdge.fromJson(e)).toList();

      final pathfinder = Pathfinder(nodes: _nodes, edges: _edges);
      _calculatedRoute = pathfinder.findShortestPath(startNodeId, targetNodeId);

      if (_calculatedRoute.isEmpty) {
        throw Exception(
          "No se encontró una ruta de pasillos hacia esta tienda.",
        );
      }

      setState(() => _isLoading = false);

      // 🚀 EJECUTAMOS EL ENCUDRE INTELIGENTE (Zoom In)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _animateCameraToFocusRoute();
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll("Exception: ", "");
        _isLoading = false;
      });
    }
  }

  // 🚀 ALGORITMO DE ENCUDRE INTELIGENTE (MACRO ➡️ MICRO)
  void _animateCameraToFocusRoute() {
    if (_calculatedRoute.isEmpty || _currentViewSize == Size.zero) return;

    // 1. Calcular Bounding Box
    double minX = _calculatedRoute.first.x;
    double maxX = _calculatedRoute.first.x;
    double minY = _calculatedRoute.first.y;
    double maxY = _calculatedRoute.first.y;

    for (var node in _calculatedRoute) {
      if (node.x < minX) minX = node.x;
      if (node.x > maxX) maxX = node.x;
      if (node.y < minY) minY = node.y;
      if (node.y > maxY) maxY = node.y;
    }

    // 2. Calcular centro y escala para Micro (Zoom In)
    double routeCenterX = (minX + maxX) / 2.0;
    double routeCenterY = (minY + maxY) / 2.0;
    double routeWidth = maxX - minX;
    double routeHeight = maxY - minY;

    double paddingFactor = 1.3;
    double viewWidth = _currentViewSize.width;
    double viewHeight = _currentViewSize.height;

    double scaleX = viewWidth / (routeWidth * paddingFactor);
    double scaleY = viewHeight / (routeHeight * paddingFactor);
    // Encuadre más cercano
    double targetScale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.8, 5.0);

    double targetDx = (viewWidth / 2.0) - (routeCenterX * targetScale);
    double targetDy = (viewHeight / 2.0) - (routeCenterY * targetScale);

    final targetMatrix = Matrix4.identity()
      ..translate(targetDx, targetDy)
      ..scale(targetScale);

    // 🚀 Comienza desde el Fit actual y hace Zoom In
    final Matrix4Tween matrixTween = Matrix4Tween(
      begin: _transformationController.value, // Comienza desde Macro
      end: targetMatrix, // Termina en Micro
    );

    _cameraAnimationController.addListener(() {
      _transformationController.value = matrixTween.evaluate(
        _cameraAnimationController,
      );
    });

    _cameraAnimationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _animationController.forward(); // Dibujar láser rosa al final
      }
    });

    _cameraAnimationController.forward(from: 0.0);
  }

  // 🚀 NUEVA FUNCIÓN: FUERZA EL PLANO COMPLETO (MACRO) AL INICIO
  void _setInitialMacroFit(BoxConstraints constraints) {
    if (_isLoading || _isInitialCameraSet) return;

    double mapOriginalSize = 2000.0;
    double viewWidth = constraints.maxWidth;
    double viewHeight = constraints.maxHeight;

    double scaleFit =
        (viewWidth / mapOriginalSize < viewHeight / mapOriginalSize)
        ? viewWidth / mapOriginalSize
        : viewHeight / mapOriginalSize;

    double dx = (viewWidth - (mapOriginalSize * scaleFit)) / 2.0;
    double dy = (viewHeight - (mapOriginalSize * scaleFit)) / 2.0;

    // Aplicamos INMEDIATAMENTE
    _transformationController.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scaleFit);

    _isInitialCameraSet = true; // Bloqueamos para que no se repita
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
              color: const Color(0xFF1A1A1A),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "RUTA ÓPTIMA",
                        style: TextStyle(
                          color: Color(0xFFFF007A),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
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
                    ],
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 30,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFFF007A),
                      ),
                    )
                  : _errorMessage.isNotEmpty
                  ? Center(
                      child: Text(
                        _errorMessage,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 18,
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        _currentViewSize = Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );

                        // 🚀 FORZAMOS EL MACRO AL INICIO DE FORMA SILENCIOSA
                        if (!_isInitialCameraSet) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _setInitialMacroFit(constraints);
                          });
                        }

                        return InteractiveViewer(
                          transformationController:
                              _transformationController, // CÁMARA CONTROLADA
                          maxScale: 5.0,
                          minScale: 0.1,
                          constrained: false,
                          boundaryMargin: const EdgeInsets.all(100),
                          child: SizedBox(
                            width: 2000,
                            height: 2000,
                            child: Stack(
                              children: [
                                Image.network(
                                  _floorImages[widget.targetStore.floorLevel] ??
                                      _floorImages['RG']!,
                                  width: 2000,
                                  height: 2000,
                                  fit: BoxFit.contain,
                                ),

                                AnimatedBuilder(
                                  animation: _animationController,
                                  builder: (context, child) {
                                    return CustomPaint(
                                      size: const Size(2000, 2000),
                                      painter: RoutePainter(
                                        route: _calculatedRoute,
                                        animationValue:
                                            _animationController.value,
                                      ),
                                    );
                                  },
                                ),

                                if (_calculatedRoute.isNotEmpty)
                                  Positioned(
                                    left: _calculatedRoute.last.x - 25,
                                    top: _calculatedRoute.last.y - 50,
                                    child: const Icon(
                                      Icons.location_on,
                                      color: Colors.pinkAccent,
                                      size: 50,
                                    ),
                                  ),

                                if (_calculatedRoute.isNotEmpty)
                                  Positioned(
                                    left: _calculatedRoute.first.x - 20,
                                    top: _calculatedRoute.first.y - 20,
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: Colors.blueAccent,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 3,
                                        ),
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
