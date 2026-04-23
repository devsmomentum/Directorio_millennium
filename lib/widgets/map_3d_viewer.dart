import 'package:flutter/material.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';

import '../theme/app_theme.dart';

/// Widget reutilizable que renderiza un modelo 3D (.glb) de forma interactiva.
///
/// Usa [flutter_3d_controller] internamente con gesture interceptor activo
/// para evitar conflictos de gestos con el layout padre (scroll, swipe, etc.).
class Map3DViewer extends StatefulWidget {
  /// URL del archivo .glb (Supabase Storage o cualquier URL pública).
  final String modelUrl;

  /// Si es `true`, permite orbitar, pan y zoom con gestos táctiles.
  final bool isInteractive;

  /// (Futuro) ID del objetivo a resaltar o enfocar en el mapa.
  /// Cuando se implemente, se usará [Flutter3DController.setCameraTarget].
  final String? highlightTargetId;

  const Map3DViewer({
    Key? key,
    required this.modelUrl,
    this.isInteractive = true,
    this.highlightTargetId,
  }) : super(key: key);

  @override
  State<Map3DViewer> createState() => _Map3DViewerState();
}

class _Map3DViewerState extends State<Map3DViewer> {
  final Flutter3DController _controller = Flutter3DController();

  bool _isLoading = true;
  bool _hasError = false;
  double _loadProgress = 0.0;

  // ── Logging ──
  final Stopwatch _loadStopwatch = Stopwatch();
  double _lastLoggedProgress = -1; // Para no loguear el mismo % repetido

  @override
  void initState() {
    super.initState();
    _log('🟢 INIT', 'Widget creado para URL: ${widget.modelUrl}');
    _log('🟢 INIT', 'isInteractive: ${widget.isInteractive}');
    _loadStopwatch.start();

    // Listener para saber cuando el modelo termina de cargar
    _controller.onModelLoaded.addListener(_onModelLoadedChanged);
  }

  @override
  void dispose() {
    _loadStopwatch.stop();
    _log('🔴 DISPOSE', 'Widget destruido. Tiempo total de vida: ${_loadStopwatch.elapsed.inSeconds}s');
    _controller.onModelLoaded.removeListener(_onModelLoadedChanged);
    super.dispose();
  }

  void _onModelLoadedChanged() {
    final loaded = _controller.onModelLoaded.value;
    _log('📡 LISTENER', 'onModelLoaded cambió a: $loaded');
    if (loaded && mounted) {
      _loadStopwatch.stop();
      _log('✅ LISTENER', 'Modelo cargado vía listener en ${_loadStopwatch.elapsed.inMilliseconds}ms');
      setState(() {
        _isLoading = false;
        _hasError = false;
      });
    }
  }

  /// Log centralizado con timestamp y etiqueta
  void _log(String tag, String message) {
    final elapsed = _loadStopwatch.isRunning ? '${_loadStopwatch.elapsed.inMilliseconds}ms' : '--';
    debugPrint('[Map3DViewer][$tag][$elapsed] $message');
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Visor 3D ──
        Positioned.fill(
          child: Flutter3DViewer(
            // Previene conflictos de gestos con widgets padre (scroll, etc.)
            activeGestureInterceptor: true,
            // Ocultamos la barra de progreso nativa — usamos la nuestra
            progressBarColor: Colors.transparent,
            // Habilita o deshabilita interacción táctil
            enableTouch: widget.isInteractive,
            controller: _controller,
            src: widget.modelUrl,
            onProgress: (double progressValue) {
              // Solo logueamos cada 10% para no inundar la consola
              final progressPercent = (progressValue * 100).toInt();
              final lastPercent = (_lastLoggedProgress * 100).toInt();
              if (progressPercent ~/ 10 != lastPercent ~/ 10 || progressValue == 1.0) {
                _log('📊 PROGRESS', '$progressPercent% — elapsed: ${_loadStopwatch.elapsed.inMilliseconds}ms');
                _lastLoggedProgress = progressValue;
              }

              if (mounted) {
                setState(() => _loadProgress = progressValue);
              }
            },
            onLoad: (String modelAddress) {
              _loadStopwatch.stop();
              _log('✅ ON_LOAD', 'Modelo cargado exitosamente');
              _log('✅ ON_LOAD', 'Dirección: $modelAddress');
              _log('✅ ON_LOAD', 'Tiempo total de carga: ${_loadStopwatch.elapsed.inMilliseconds}ms');
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _hasError = false;
                });
              }
            },
            onError: (String error) {
              _loadStopwatch.stop();
              _log('❌ ON_ERROR', 'Error al cargar modelo');
              _log('❌ ON_ERROR', 'Detalle: $error');
              _log('❌ ON_ERROR', 'URL intentada: ${widget.modelUrl}');
              _log('❌ ON_ERROR', 'Tiempo hasta el error: ${_loadStopwatch.elapsed.inMilliseconds}ms');
              _log('❌ ON_ERROR', 'Progreso alcanzado: ${(_loadProgress * 100).toInt()}%');
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _hasError = true;
                });
              }
            },
          ),
        ),

        // ── Overlay de carga ──
        if (_isLoading)
          Positioned.fill(
            child: Container(
              color: AppColors.surfaceLight,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        value: _loadProgress > 0 ? _loadProgress : null,
                        color: AppColors.primary,
                        strokeWidth: 3,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _loadProgress > 0
                          ? 'Cargando mapa… ${(_loadProgress * 100).toInt()}%'
                          : 'Cargando mapa…',
                      style: const TextStyle(
                        color: AppColors.textSecondaryMuted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_loadStopwatch.elapsed.inSeconds}s',
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ── Overlay de error ──
        if (_hasError)
          Positioned.fill(
            child: Container(
              color: AppColors.surfaceLight,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.error.withAlpha(25),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.map_outlined,
                        size: 32,
                        color: AppColors.error.withAlpha(180),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No se pudo cargar el mapa',
                      style: TextStyle(
                        color: AppColors.textSecondaryMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Verifica tu conexión o intenta de nuevo',
                      style: TextStyle(
                        color: AppColors.textHint,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
