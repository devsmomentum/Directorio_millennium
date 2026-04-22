import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'main_layout.dart';
import '../services/ad_cache_manager.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _ads = [];
  Map<String, dynamic>? _currentAd;
  Timer? _adTimer;
  int _currentAdIndex = 0;
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    _initAdServer();
  }

  Future<void> _initAdServer() async {
    final cacheManager = AdCacheManager();

    cacheManager.onCacheUpdated = () async {
      if (mounted) {
        setState(() {
          _ads = cacheManager.cachedAds;
          if (_ads.isEmpty) {
            _currentAd = null;
            _prepareCurrentMedia();
            _adTimer?.cancel();
          } else if (_currentAd == null) {
            _currentAd = _ads[0];
            _currentAdIndex = 0;
            _prepareCurrentMedia();
            _startAdRotation();
          } else {
            bool currentAdStillExists = _ads.any((ad) => ad['id'] == _currentAd!['id']);
            if (!currentAdStillExists) {
              _currentAdIndex = 0;
              _currentAd = _ads[0];
              _prepareCurrentMedia();
            } else {
              _currentAdIndex = _ads.indexWhere((ad) => ad['id'] == _currentAd!['id']);
            }
          }
        });
      }
    };

    await cacheManager.init();

    if (cacheManager.cachedAds.isNotEmpty) {
      setState(() {
        _ads = cacheManager.cachedAds;
        _currentAd = _ads[0];
      });
      await _prepareCurrentMedia();
      _startAdRotation();
    }
  }

  void _startAdRotation() {
    _adTimer?.cancel();
    _adTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      if (_ads.isEmpty || !mounted) return;
      setState(() {
        _currentAdIndex = (_currentAdIndex + 1) % _ads.length;
        _currentAd = _ads[_currentAdIndex];
      });
      await _prepareCurrentMedia();
    });
  }

  Future<void> _prepareCurrentMedia() async {
    _videoController?.dispose();
    _videoController = null;

    if (_currentAd != null && _currentAd!['media_type'] == 'video' && _currentAd!['local_path'] != null) {
      try {
        final file = File(_currentAd!['local_path']);
        if (await file.exists()) {
          _videoController = VideoPlayerController.file(file);
          await _videoController!.initialize();
          if (mounted) {
            setState(() {});
            _videoController!.setVolume(0.0);
            _videoController!.setLooping(true);
            _videoController!.play();
          }
        }
      } catch (e) {
        debugPrint('❌ Error de Video: $e');
        _videoController = null;
        if (mounted) setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _adTimer?.cancel();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Fondo Publicitario
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(seconds: 1),
              child: _buildMediaBackground(),
            ),
          ),

          // 2. Overlay Gradiente
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.0),
                    Colors.black.withOpacity(0.4),
                    Colors.black.withOpacity(0.85),
                  ],
                ),
              ),
            ),
          ),

          // 3. LOGO MILLENNIUM (Arriba Derecha)
          Positioned(
            top: 20,
            right: 25,
            child: Image.network(
              'https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/mapas/Logo_millennium.png',
              height: 100,
              fit: BoxFit.contain,
            ),
          ),

          // 4. Contenido Principal
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badge Slot
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Text(
                          _currentAd != null ? '📍 SLOT PUBLICITARIO' : '📍 DIRECTORIO DIGITAL',
                          style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Marca
                      Text(
                        _currentAd != null ? _currentAd!['brand_name'] : 'Millennium Mall',
                        style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
                      ),
                       Text(
                        (_currentAd != null && _currentAd!['description'] != null && _currentAd!['description'].toString().trim().isNotEmpty)
                            ? _currentAd!['description'] 
                            : 'Toca para explorar el mall',
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                        maxLines: 2, // Evita que una descripción muy larga rompa el diseño
                        overflow: TextOverflow.ellipsis, // Agrega "..." si el texto es muy largo
                      ),
                      const SizedBox(height: 20),

                      // Info de WiFi y QR (Integrado en una sola fila)
                      _buildSmallWifiInfo(),
                      const SizedBox(height: 15), // Espacio antes del botón COMENZAR

                      // Botón Principal
                      _buildSmallStartButton(context),
                      const SizedBox(height: 10),

                      // Footer Colaborativo
                      _buildCollaborativeFooter(),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

Widget _buildSmallWifiInfo() {
    const double targetHeight = 50.0; // Altura objetivo para ambos widgets

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center, 
      children: [
        // 1. Texto de WiFi Gratis (Ocupando todo el espacio disponible)
        Expanded(
          child: Container(
            height: targetHeight,
            padding: const EdgeInsets.symmetric(horizontal: 15),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(targetHeight / 2), 
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center, // Centramos el contenido internamente
              children: [
                Icon(Icons.wifi, color: Colors.pinkAccent, size: 18),
                SizedBox(width: 10),
                // Expanded interno opcional por si la pantalla es muy pequeña y el texto choca
                Flexible(
                  child: Text(
                    'WiFi Gratis: Millennium_Mall', 
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),

        // 2. Espacio fijo entre el contenedor de WiFi y el QR
        const SizedBox(width: 15),

        // 3. Código QR (Tamaño fijo a la derecha)
        Container(
          height: targetHeight,
          width: targetHeight,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10)
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: QrImageView(
              data: "WIFI:S:Millennium_Mall;T:WPA;P:mall2026;;",
              version: QrVersions.auto,
              padding: const EdgeInsets.all(2.0),
              backgroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
}

  Widget _buildSmallStartButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MainLayout())),
      child: Container(
        width: double.infinity,
        height: 55,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFFF007A), Color(0xFFFF5900)]),
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Center(
          child: Text(
            ' COMENZAR ',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1),
          ),
        ),
      ),
    );
  }

  Widget _buildCollaborativeFooter() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("Desarrollado por ", style: TextStyle(color: Colors.white38, fontSize: 9)),
            const SizedBox(width: 4),
            Image.network('https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/mapas/Recurso%203@2x.png', height: 16),
            const SizedBox(width: 4),
            const Text(" en colaboración con ", style: TextStyle(color: Colors.white38, fontSize: 9)),
            Image.network('https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/mapas/ANAVI.png', height: 25),
            const SizedBox(width: 6),
            Image.network('https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/mapas/Logo_sunmi.png', height: 35),
          ],
        ),
      ],
    );
  }

  Widget _buildMediaBackground() {
    if (_currentAd != null && _currentAd!['media_type'] == 'video') {
      if (_videoController != null && _videoController!.value.isInitialized) {
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _videoController!.value.size.width,
              height: _videoController!.value.size.height,
              child: VideoPlayer(_videoController!),
            ),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFF007A)));
    }
    if (_currentAd != null && _currentAd!['local_path'] != null) {
      final file = File(_currentAd!['local_path']);
      if (file.existsSync()) return Image.file(file, fit: BoxFit.cover);
    }
    return Image.network('https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?q=80&w=2070', fit: BoxFit.cover);
  }
}