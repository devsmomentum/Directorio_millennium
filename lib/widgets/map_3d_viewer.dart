import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';

import '../theme/app_theme.dart';
import 'platform_check_stub.dart'
    if (dart.library.io) 'platform_check_io.dart' as platform_check;

/// Visor 3D interactivo para planos de centro comercial (.glb).
///
/// Usa [Flutter3DViewer] de flutter_3d_controller con gesture interceptor.
/// En Linux/Windows muestra un fallback elegante.
class Map3DViewer extends StatefulWidget {
  final String modelUrl;
  final bool isInteractive;
  final String? highlightTargetId;

  const Map3DViewer({
    super.key,
    required this.modelUrl,
    this.isInteractive = true,
    this.highlightTargetId,
  });

  @override
  State<Map3DViewer> createState() => _Map3DViewerState();
}

class _Map3DViewerState extends State<Map3DViewer> {
  final Flutter3DController _controller = Flutter3DController();

  bool _isLoading = true;
  bool _hasError = false;
  double _loadProgress = 0.0;
  final Stopwatch _sw = Stopwatch();

  bool get _supported {
    if (kIsWeb) return true;
    return platform_check.isWebViewSupported;
  }

  @override
  void initState() {
    super.initState();
    _sw.start();
    debugPrint('[Map3DViewer][INIT] URL: ${widget.modelUrl}');

    if (_supported) {
      _controller.onModelLoaded.addListener(_onLoaded);
    }
  }

  @override
  void dispose() {
    _sw.stop();
    debugPrint('[Map3DViewer][DISPOSE] Vida: ${_sw.elapsed.inSeconds}s');
    if (_supported) {
      _controller.onModelLoaded.removeListener(_onLoaded);
    }
    super.dispose();
  }

  void _onLoaded() {
    if (_controller.onModelLoaded.value && mounted) {
      _sw.stop();
      debugPrint('[Map3DViewer][LOADED] ${_sw.elapsed.inMilliseconds}ms');
      setState(() {
        _isLoading = false;
        _hasError = false;
      });
      _setupCamera();
    }
  }

  /// Configura la vista inicial de cámara tras carga del modelo.
  void _setupCamera() {
    try {
      // Vista cenital inclinada: theta=0 (frente), phi=45 (inclinado), radius=5
      _controller.setCameraOrbit(0, 45, 5);
      _controller.setCameraTarget(0, 0, 0);
    } catch (e) {
      debugPrint('[Map3DViewer][CAMERA] Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return _buildFallback();

    return Stack(
      children: [
        // ── Visor 3D ──
        Positioned.fill(
          child: Flutter3DViewer(
            activeGestureInterceptor: true,
            progressBarColor: Colors.transparent,
            enableTouch: widget.isInteractive,
            controller: _controller,
            src: widget.modelUrl,
            onProgress: (double v) {
              if (mounted) setState(() => _loadProgress = v);
              final pct = (v * 100).toInt();
              if (pct % 20 == 0 || v == 1.0) {
                debugPrint('[Map3DViewer][PROGRESS] $pct%');
              }
            },
            onLoad: (String addr) {
              _sw.stop();
              debugPrint('[Map3DViewer][ON_LOAD] OK en ${_sw.elapsed.inMilliseconds}ms');
              if (mounted) {
                setState(() { _isLoading = false; _hasError = false; });
                _setupCamera();
              }
            },
            onError: (String error) {
              _sw.stop();
              debugPrint('[Map3DViewer][ERROR] $error');
              if (mounted) {
                setState(() { _isLoading = false; _hasError = true; });
              }
            },
          ),
        ),

        // ── Loading overlay ──
        if (_isLoading)
          Positioned.fill(
            child: Container(
              color: AppColors.surfaceLight,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 48, height: 48,
                      child: CircularProgressIndicator(
                        value: _loadProgress > 0 ? _loadProgress : null,
                        color: AppColors.primary, strokeWidth: 3,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _loadProgress > 0
                          ? 'Cargando mapa… ${(_loadProgress * 100).toInt()}%'
                          : 'Cargando mapa…',
                      style: const TextStyle(
                          color: AppColors.textSecondaryMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ── Error overlay ──
        if (_hasError)
          Positioned.fill(
            child: Container(
              color: AppColors.surfaceLight,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.error.withAlpha(25),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.map_outlined, size: 32,
                          color: AppColors.error.withAlpha(180)),
                    ),
                    const SizedBox(height: 16),
                    const Text('No se pudo cargar el mapa',
                        style: TextStyle(color: AppColors.textSecondaryMuted,
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    const Text('Verifica tu conexión o intenta de nuevo',
                        style: TextStyle(color: AppColors.textHint, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Fallback para plataformas sin soporte de WebView.
  Widget _buildFallback() {
    return Container(
      color: AppColors.surfaceLight,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.desktop_windows_outlined, size: 40,
                  color: AppColors.primary.withAlpha(150)),
            ),
            const SizedBox(height: 20),
            const Text('Vista 3D no disponible',
                style: TextStyle(color: AppColors.textPrimary,
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'El visor 3D requiere Android o Web (Chrome).\n'
              'Usa flutter run -d chrome para probar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondaryMuted,
                  fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
