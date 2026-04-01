import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:qr_flutter/qr_flutter.dart'; // 🚀 Asegúrate de tener este paquete
import 'main_layout.dart';
import '../services/telemetry_service.dart';
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
            bool currentAdStillExists = _ads.any(
              (ad) => ad['id'] == _currentAd!['id'],
            );

            if (!currentAdStillExists) {
              _currentAdIndex = 0;
              _currentAd = _ads[0];
              _prepareCurrentMedia();
            } else {
              _currentAdIndex = _ads.indexWhere(
                (ad) => ad['id'] == _currentAd!['id'],
              );
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

    if (_currentAd != null &&
        _currentAd!['media_type'] == 'video' &&
        _currentAd!['local_path'] != null) {
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
        print('❌ Error de Hardware al reproducir video local: $e');
        _videoController = null;
        if (mounted) setState(() {});
      }
    }
  }

  // 🚀 FUNCIÓN PARA MOSTRAR EL QR EN GRANDE (POP-UP)
  void _showExpandedQR(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Colors.pinkAccent.withOpacity(0.5),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.pinkAccent.withOpacity(0.2),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "WIFI GRATIS",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Escanea para conectarte automáticamente",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: QrImageView(
                  data:
                      "WIFI:S:Millennium_Mall;T:WPA;P:mall2026;;", // QR Ficticio de WiFi
                  version: QrVersions.auto,
                  size: 250.0,
                  foregroundColor: Colors.black,
                ),
              ),
              const SizedBox(height: 25),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pinkAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 15,
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "CERRAR",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _adTimer?.cancel();
    _videoController?.dispose();
    super.dispose();
  }

  Widget _buildMediaBackground() {
    if (_currentAd != null && _currentAd!['media_type'] == 'video') {
      if (_videoController != null && _videoController!.value.isInitialized) {
        return SizedBox.expand(
          key: ValueKey<String>(_currentAd!['local_path'] ?? 'video_local'),
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _videoController!.value.size.width,
              height: _videoController!.value.size.height,
              child: VideoPlayer(_videoController!),
            ),
          ),
        );
      } else {
        return const Center(
          key: ValueKey('loading_video'),
          child: CircularProgressIndicator(color: Color(0xFFFF007A)),
        );
      }
    }

    if (_currentAd != null && _currentAd!['local_path'] != null) {
      final file = File(_currentAd!['local_path']);
      if (file.existsSync()) {
        return Image.file(
          file,
          key: ValueKey<String>(_currentAd!['local_path']),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _fallbackImage(),
        );
      }
    }

    return _fallbackImage();
  }

  Widget _fallbackImage() {
    return Image.network(
      'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?q=80&w=2070&auto=format&fit=crop',
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        color: Colors.black,
        child: const Center(
          child: Icon(Icons.broken_image, color: Colors.white24, size: 50),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(seconds: 1),
              child: _buildMediaBackground(),
            ),
          ),

          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.1),
                    Colors.black.withOpacity(0.7),
                    Colors.black.withOpacity(1.0),
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 20.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Spacer(),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      _currentAd != null
                          ? '📍 SLOT PUBLICITARIO - ${_currentAd!['plan_type']}'
                          : '📍 DIRECTORIO DIGITAL MORNA',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    child: Text(
                      _currentAd != null
                          ? _currentAd!['brand_name']
                          : 'Millennium Mall',
                      key: ValueKey<String>(
                        _currentAd?['brand_name'] ?? 'default_title',
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 45,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Toca la pantalla para encontrar tu tienda ideal',
                    style: TextStyle(color: Colors.white70, fontSize: 18),
                  ),
                  const SizedBox(height: 40),

                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const MainLayout(),
                        ),
                      );
                    },
                    child: Container(
                      height: 60,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          const Icon(Icons.search, color: Colors.pinkAccent),
                          const SizedBox(width: 15),
                          const Expanded(
                            child: Text(
                              'Buscar tiendas o servicios...',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          CircleAvatar(
                            backgroundColor: Colors.pinkAccent,
                            radius: 18,
                            child: const Icon(
                              Icons.arrow_forward_ios,
                              size: 15,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),

                  // --- CAJA DE WIFI CON CLICK PARA QR ---
                  GestureDetector(
                    onTap: () =>
                        _showExpandedQR(context), // 🚀 AL TOCAR SE ABRE EL QR
                    child: Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.05),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.wifi,
                            color: Colors.pinkAccent,
                            size: 30,
                          ),
                          const SizedBox(width: 15),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'WiFi Marketing Gratis',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  'Toca el código para conectar',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 50,
                            height: 50,
                            color: Colors.white,
                            child: const Icon(
                              Icons.qr_code_2,
                              size: 40,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 25),

                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const MainLayout(),
                        ),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF007A), Color(0xFFFF5900)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(40),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF007A).withOpacity(0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'TOCA PARA COMENZAR',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                              ),
                            ),
                            Text(
                              'Explorar tiendas y servicios del mall',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // 🚀 NUEVO FOOTER: LOGOS Y CREDITOS
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Logo CC Millennium (Izquierda)
                      Image.network(
                        'https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/mapas/logo.png',
                        height: 45,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox(height: 45, width: 45),
                      ),

                      // Label Morna Tech (Derecha)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "Desarrollado por ",
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Image.network(
                            'https://lrjgocjubpxruobshtoe.supabase.co/storage/v1/object/public/mapas/Recurso%203@2x.png',
                            height: 25,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const SizedBox(height: 25, width: 25),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
