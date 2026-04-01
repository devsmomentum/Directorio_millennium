import 'package:flutter/material.dart';
import 'dart:ui'; // Para el efecto de desenfoque (Blur)
import '../widgets/route_painter.dart';
import '../models/map_node.dart';
import '../models/map_edge.dart';
import '../models/store.dart';
import '../services/supabase_service.dart';
import '../utils/pathfinder.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformationController =
      TransformationController();
  final SupabaseService _supabaseService = SupabaseService();

  bool _isLoading = true;
  List<MapNode> _nodes = [];
  List<MapEdge> _edges = [];
  List<Store> _stores = [];
  List<MapNode> _currentRoute = [];

  final TextEditingController _searchController = TextEditingController();
  List<Store> _searchResults = [];
  bool _isSearching =
      false; // 🆕 Controla si mostramos los resultados flotantes

  int _selectedFloor = 1;

  late AnimationController _routeAnimationController;

  final List<Map<String, dynamic>> _mallFloors = [
    {'level': 3, 'name': 'C2'},
    {'level': 2, 'name': 'C1'},
    {'level': 1, 'name': 'RG'},
  ];

  @override
  void initState() {
    super.initState();
    _routeAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _loadData();
  }

  @override
  void dispose() {
    _routeAnimationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        _supabaseService.getMapNodes(),
        _supabaseService.getMapEdges(),
        _supabaseService.getStores(),
      ]);

      setState(() {
        _nodes = results[0] as List<MapNode>;
        _edges = results[1] as List<MapEdge>;
        _stores = results[2] as List<Store>;
        _searchResults = _stores;
        _isLoading = false;
      });

      // 🆕 Ajustar el zoom inicial para que el mapa se vea completo al abrir
      // Retrasamos un poco para asegurarnos de que el widget ya se construyó
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _transformationController.value = Matrix4.identity()..scale(0.35);
      });
    } catch (e) {
      debugPrint('Error conectando a Supabase: $e');
      setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      setState(() {
        _searchResults = _stores;
        _isSearching = false;
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _searchResults = _stores
          .where(
            (store) => store.name.toLowerCase().contains(query.toLowerCase()),
          )
          .toList();
    });
  }

  void _closeSearch() {
    setState(() {
      _isSearching = false;
      _searchController.clear();
      FocusScope.of(context).unfocus();
    });
  }

  void _showStoreDialog(Store store) {
    _closeSearch(); // Cerramos el buscador al abrir el pop-up
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) {
        String floorName = "Nivel desconocido";
        try {
          if (store.nodeId != null && store.nodeId!.isNotEmpty) {
            final node = _nodes.firstWhere((n) => n.id == store.nodeId);
            final floor = _mallFloors.firstWhere(
              (f) => f['level'] == node.floorLevel,
            );
            floorName = 'Nivel ${floor['name']}';
          }
        } catch (e) {
          debugPrint('Error buscando datos del piso: $e');
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 20,
          ),
          child: Container(
            width: 500,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A).withOpacity(0.95),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.white10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(25),
                  ),
                  child: Image.network(
                    store.logoUrl.isNotEmpty
                        ? store.logoUrl
                        : 'https://dummyimage.com/600x300/333/fff&text=${Uri.encodeComponent(store.name)}',
                    height: 250,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 250,
                      color: Colors.grey[900],
                      child: const Icon(
                        Icons.broken_image,
                        color: Colors.white24,
                        size: 50,
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
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${store.category} • $floorName • Local ${store.localNumber}',
                        style: const TextStyle(
                          color: Colors.pinkAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        store.description,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 40),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                _calculateRouteTo(store);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.pinkAccent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 20,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                              child: const Text(
                                'CÓMO LLEGAR',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 15),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
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
        );
      },
    );
  }

  // 🆕 LÓGICA DE RUTAS CORREGIDA CON MANEJO DE ERRORES CLARO
  void _calculateRouteTo(Store destinationStore) {
    if (destinationStore.nodeId == null || destinationStore.nodeId!.isEmpty) {
      _showErrorSnackBar(
        'La tienda ${destinationStore.name} aún no tiene un punto asignado en el mapa.',
      );
      return;
    }

    try {
      // 1. Validar que exista un Kiosco mapeado
      final kioskNodes = _nodes.where((n) => n.nodeType == 'kiosk').toList();
      if (kioskNodes.isEmpty) {
        _showErrorSnackBar(
          'Falta ubicar el "Kiosco" en el panel de administrador para saber desde dónde calcular la ruta.',
        );
        return;
      }
      final kioskNode = kioskNodes.first;

      // 2. Calcular ruta
      final pathfinder = Pathfinder(nodes: _nodes, edges: _edges);
      final route = pathfinder.findShortestPath(
        kioskNode.id,
        destinationStore.nodeId!,
      );

      // 3. Validar que la ruta exista (que los puntos estén conectados por pasillos)
      if (route.isEmpty) {
        _showErrorSnackBar(
          'No hay una ruta conectada (pasillos) entre el Kiosco y esta tienda.',
        );
        return;
      }

      setState(() {
        _currentRoute = route;
        final storeNode = _nodes.firstWhere(
          (n) => n.id == destinationStore.nodeId,
        );
        _selectedFloor = storeNode.floorLevel; // Cambiar al piso de la tienda
      });

      _routeAnimationController.reset();
      _routeAnimationController.forward();
    } catch (e) {
      debugPrint('Error calculando ruta: $e');
      _showErrorSnackBar('Ocurrió un error inesperado al calcular la ruta.');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(20),
      ),
    );
  }

  String _getMapImageForCurrentFloor() {
    switch (_selectedFloor) {
      case 3:
        return 'https://dummyimage.com/2000x2000/1A1A1A/FF007A&text=Plano+Nivel+C2';
      case 2:
        return 'https://dummyimage.com/2000x2000/1A1A1A/FF007A&text=Plano+Nivel+C1';
      case 1:
      default:
        return 'https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/mapas/plano_rg.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0D0D),
        body: Center(
          child: CircularProgressIndicator(color: Colors.pinkAccent),
        ),
      );
    }

    final nodesOnCurrentFloor = _nodes
        .where((n) => n.floorLevel == _selectedFloor)
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Stack(
        children: [
          // ==========================================
          // 1. MAPA GIGANTE (CAPA INFERIOR)
          // ==========================================
          Positioned.fill(
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale:
                  0.1, // 🆕 Permite alejar mucho más para ver el plano completo
              maxScale: 4.0,
              constrained: false,
              child: SizedBox(
                width: 2000,
                height: 2000,
                child: Stack(
                  children: [
                    Image.network(
                      _getMapImageForCurrentFloor(),
                      width: 2000,
                      height: 2000,
                      fit: BoxFit.contain,
                    ),
                    // LA RUTA ANIMADA
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _routeAnimationController,
                        builder: (context, child) {
                          return CustomPaint(
                            painter: RoutePainter(
                              route: _currentRoute,
                              animationValue: _routeAnimationController.value,
                            ),
                          );
                        },
                      ),
                    ),
                    // LOS PINES
                    ...nodesOnCurrentFloor.map((node) {
                      if (node.nodeType == 'kiosk' ||
                          node.nodeType == 'store') {
                        Store? store;
                        if (node.nodeType == 'store') {
                          try {
                            store = _stores.firstWhere(
                              (s) => s.nodeId == node.id,
                            );
                          } catch (e) {}
                        }

                        bool isDestination =
                            _currentRoute.isNotEmpty &&
                            _currentRoute.last.id == node.id;

                        return Positioned(
                          left: node.x - 25,
                          top: node.y - 50,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0.8, end: 1.0),
                            duration: const Duration(milliseconds: 600),
                            curve: Curves.elasticOut,
                            builder: (context, scale, child) {
                              double finalScale =
                                  (node.nodeType == 'kiosk' || isDestination)
                                  ? scale * 1.5
                                  : scale;

                              Widget iconWidget = Transform.scale(
                                scale: finalScale,
                                child: Icon(
                                  node.nodeType == 'kiosk'
                                      ? Icons.location_on
                                      : Icons.store,
                                  color: node.nodeType == 'kiosk'
                                      ? Colors.pinkAccent
                                      : (isDestination
                                            ? Colors.amber
                                            : Colors.white54),
                                  size: 50,
                                ),
                              );

                              if (node.nodeType == 'store' && store != null) {
                                return GestureDetector(
                                  onTap: () => _showStoreDialog(store!),
                                  child: iconWidget,
                                );
                              }
                              return iconWidget;
                            },
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }),
                  ],
                ),
              ),
            ),
          ),

          // ==========================================
          // 2. BUSCADOR FLOTANTE Y RESULTADOS (CAPA SUPERIOR)
          // ==========================================
          Positioned(
            top: 40,
            left:
                MediaQuery.of(context).size.width *
                0.15, // Centrado interactivo
            right: MediaQuery.of(context).size.width * 0.15,
            child: Column(
              children: [
                // CAJA DEL BUSCADOR (Glassmorphism)
                ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A).withOpacity(0.8),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white24, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                        ),
                        decoration: InputDecoration(
                          hintText: '¿Buscas alguna tienda en específico?',
                          hintStyle: const TextStyle(color: Colors.white54),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.pinkAccent,
                            size: 28,
                          ),
                          suffixIcon: _isSearching
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white54,
                                  ),
                                  onPressed: _closeSearch,
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // LISTA DE RESULTADOS FLOTANTE
                if (_isSearching && _searchResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    constraints: const BoxConstraints(maxHeight: 400),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A).withOpacity(0.95),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final store = _searchResults[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 25,
                            vertical: 5,
                          ),
                          title: Text(
                            store.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Text(
                            '${store.category} • Local ${store.localNumber}',
                            style: const TextStyle(color: Colors.white54),
                          ),
                          trailing: const Icon(
                            Icons.location_on,
                            color: Colors.pinkAccent,
                          ),
                          onTap: () => _showStoreDialog(store),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // ==========================================
          // 3. SELECTOR DE PISOS (FLOTANTE A LA DERECHA)
          // ==========================================
          Positioned(
            right: 20,
            bottom: MediaQuery.of(context).size.height * 0.3, // Mitad inferior
            child: Column(
              children: _mallFloors.map((floor) {
                final isSelected = _selectedFloor == floor['level'];
                return GestureDetector(
                  onTap: () => setState(() => _selectedFloor = floor['level']),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.amber
                          : const Color(0xFF1A1A1A).withOpacity(0.8),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: isSelected ? Colors.amber : Colors.white24,
                        width: 2,
                      ),
                      boxShadow: [
                        if (isSelected)
                          BoxShadow(
                            color: Colors.amber.withOpacity(0.3),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        floor['name'],
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: isSelected ? Colors.black : Colors.white,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // ==========================================
          // 4. BANNER PATROCINADOR (FLOTANTE ABAJO)
          // ==========================================
          Positioned(
            bottom: 20,
            left: 20,
            right: 100, // Deja espacio para el selector de pisos
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.amber.withOpacity(0.5),
                  width: 2,
                ),
              ),
              child: const Center(
                child: Text(
                  'BANNER PATROCINADOR EXCLUSIVO',
                  style: TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
