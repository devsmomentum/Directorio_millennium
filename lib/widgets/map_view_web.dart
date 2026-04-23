import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../theme/app_theme.dart';

// ============================================================================
// MapViewWeb — Visor 3D basado en InAppWebView + <model-viewer> de Google
// ============================================================================
// Este widget carga un HTML estático con el motor model-viewer para renderizar
// modelos .glb del centro comercial. Soporta:
//  • Comunicación bidireccional Flutter ↔ JavaScript
//  • Posicionamiento dinámico de avatar con animación de caminar
//  • Optimizaciones específicas para Sunmi K2 Pro (hardware acceleration)
// ============================================================================

class MapViewWeb extends StatefulWidget {
  /// URL del modelo .glb del plano a renderizar
  final String modelUrl;

  /// URL opcional del modelo .glb del avatar/personaje
  final String? avatarUrl;

  /// Callback cuando el mapa termina de cargar
  final VoidCallback? onMapLoaded;

  /// Callback cuando ocurre un error de carga
  final VoidCallback? onError;

  const MapViewWeb({
    Key? key,
    required this.modelUrl,
    this.avatarUrl,
    this.onMapLoaded,
    this.onError,
  }) : super(key: key);

  @override
  State<MapViewWeb> createState() => MapViewWebState();
}

class MapViewWebState extends State<MapViewWeb> {
  InAppWebViewController? _webViewController;
  bool _isLoading = true;
  bool _hasError = false;
  Timer? _webLoadPoller;

  // ══════════════════════════════════════════════════════════════════════════
  // Color de fondo de la app convertido a hex CSS para evitar parpadeos blancos
  // ══════════════════════════════════════════════════════════════════════════
  String get _backgroundColorCss {
    final color = AppColors.background;
    final r = color.r.toInt();
    final g = color.g.toInt();
    final b = color.b.toInt();
    return 'rgb($r, $g, $b)';
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HTML inyectado con <model-viewer> y lógica de avatar
  // ══════════════════════════════════════════════════════════════════════════
  String get _initialHtml => '''
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Mapa 3D</title>

  <!-- Motor model-viewer de Google -->
  <script type="module"
    src="https://unpkg.com/@google/model-viewer/dist/model-viewer.min.js">
  </script>

  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }

    html, body {
      width: 100%;
      height: 100%;
      overflow: hidden;
      background: $_backgroundColorCss;
    }

    /* Contenedor principal del visor 3D */
    #viewer-container {
      width: 100%;
      height: 100%;
      position: relative;
      background: transparent;
    }

    /* Visor del mapa (modelo principal) */
    model-viewer#map-viewer {
      width: 100%;
      height: 100%;
      background: transparent;
      --poster-color: transparent;
    }

    /* Visor del avatar (superpuesto al mapa) */
    model-viewer#avatar-viewer {
      position: absolute;
      width: 60px;
      height: 60px;
      bottom: 20px;
      left: 50%;
      transform: translateX(-50%);
      background: transparent;
      --poster-color: transparent;
      pointer-events: none;
      display: none; /* Oculto hasta que se cargue un avatar */
    }

    /* Indicador de carga nativo oculto */
    model-viewer .progress-bar { display: none; }
  </style>
</head>
<body>
  <div id="viewer-container">

    <!-- Modelo principal: plano del centro comercial -->
    <model-viewer
      id="map-viewer"
      src="${widget.modelUrl}"
      alt="Mapa 3D del centro comercial"
      shadow-intensity="1"
      environment-image="neutral"
      exposure="1"
      camera-controls
      touch-action="pan-y"
      interaction-prompt="none"
      min-camera-orbit="auto auto 0m"
      interpolation-decay="100"
      disable-zoom="false"
    ></model-viewer>

    <!-- Modelo secundario: avatar/personaje (opcional) -->
    <model-viewer
      id="avatar-viewer"
      alt="Avatar del usuario"
      autoplay
      animation-name="Caminar"
      shadow-intensity="0"
      environment-image="neutral"
      exposure="1"
    ></model-viewer>

  </div>

  <script>
    // ════════════════════════════════════════════════════════════════════
    // Referencias a los elementos del DOM
    // ════════════════════════════════════════════════════════════════════
    const mapViewer    = document.getElementById('map-viewer');
    const avatarViewer = document.getElementById('avatar-viewer');

    // Variable para rastrear si el avatar se está moviendo
    let avatarMoving = false;
    let avatarAnimFrame = null;

    // ════════════════════════════════════════════════════════════════════
    // Evento: Mapa cargado → Notificar a Flutter
    // ════════════════════════════════════════════════════════════════════
    mapViewer.addEventListener('load', function() {
      console.log('[MapViewWeb] Modelo del mapa cargado correctamente');

      // Notificar a Flutter vía JavaScriptHandler
      if (window.flutter_inappwebview) {
        window.flutter_inappwebview.callHandler('onMapLoaded', 'ok');
      }
    });

    // Evento de error en el modelo
    mapViewer.addEventListener('error', function(e) {
      console.log('[MapViewWeb][ERROR] ' + (e.detail || 'Error desconocido'));

      if (window.flutter_inappwebview) {
        window.flutter_inappwebview.callHandler('onMapError',
          e.detail || 'Error al cargar el modelo');
      }
    });

    // ════════════════════════════════════════════════════════════════════
    // Funciones invocadas desde Flutter (evaluateJavascript)
    // ════════════════════════════════════════════════════════════════════

    /**
     * Mueve la cámara suavemente hacia un punto y órbita específicos.
     * @param {string} target - Coordenadas del objetivo, ej: "0m 1m 0m"
     * @param {string} orbit  - Órbita de cámara, ej: "45deg 55deg 5m"
     */
    function updateCamera(target, orbit) {
      if (!mapViewer) return;

      // Aplicar transición suave
      mapViewer.interpolationDecay = 100;

      if (target) {
        mapViewer.cameraTarget = target;
      }
      if (orbit) {
        mapViewer.cameraOrbit = orbit;
      }

      console.log('[MapViewWeb] Cámara actualizada → target: '
        + target + ', orbit: ' + orbit);
    }

    /**
     * Resetea la cámara a la vista inicial por defecto.
     */
    function resetCamera() {
      if (!mapViewer) return;
      mapViewer.cameraTarget = 'auto auto auto';
      mapViewer.cameraOrbit = 'auto auto auto';
      console.log('[MapViewWeb] Cámara reseteada');
    }

    /**
     * Carga un modelo de avatar en el visor secundario.
     * @param {string} avatarSrc - URL del modelo .glb del avatar
     */
    function loadAvatar(avatarSrc) {
      if (!avatarViewer || !avatarSrc) return;
      avatarViewer.src = avatarSrc;
      avatarViewer.style.display = 'block';
      console.log('[MapViewWeb] Avatar cargado: ' + avatarSrc);
    }

    /**
     * Posiciona el avatar en coordenadas de pantalla (porcentaje).
     * Cuando la posición cambia, activa la animación "Caminar".
     * Cuando se detiene, cambia a animación "Idle" (si existe).
     * @param {number} x - Posición X en porcentaje (0-100)
     * @param {number} y - Posición Y en porcentaje (0-100)
     * @param {number} z - Escala/tamaño del avatar (1.0 = normal)
     */
    function setAvatarPosition(x, y, z) {
      if (!avatarViewer) return;

      // Posicionar el avatar en la escena
      avatarViewer.style.left = x + '%';
      avatarViewer.style.bottom = y + '%';
      avatarViewer.style.transform = 'translateX(-50%) scale(' + (z || 1) + ')';

      // Activar animación de caminar
      if (!avatarMoving) {
        avatarMoving = true;
        avatarViewer.animationName = 'Caminar';
        avatarViewer.play();
      }

      // Detener animación después de 500ms sin cambio
      if (avatarAnimFrame) clearTimeout(avatarAnimFrame);
      avatarAnimFrame = setTimeout(function() {
        avatarMoving = false;
        // Intentar cambiar a Idle si la animación existe
        try {
          avatarViewer.animationName = 'Idle';
          avatarViewer.play();
        } catch(e) {
          avatarViewer.pause();
        }
      }, 500);

      console.log('[MapViewWeb] Avatar posición → x:' + x
        + ' y:' + y + ' z:' + z);
    }

    /**
     * Oculta el avatar de la escena.
     */
    function hideAvatar() {
      if (!avatarViewer) return;
      avatarViewer.style.display = 'none';
      console.log('[MapViewWeb] Avatar oculto');
    }
  </script>
</body>
</html>
''';

  // ══════════════════════════════════════════════════════════════════════════
  // Ciclo de vida del widget
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _webLoadPoller?.cancel();
    _webViewController = null;
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Fallback de carga para Web (las APIs de InAppWebView no funcionan en web)
  // ══════════════════════════════════════════════════════════════════════════

  /// En web, addJavaScriptHandler, onConsoleMessage, onLoadStop, y
  /// evaluateJavascript NO están implementados en flutter_inappwebview.
  /// Usamos un timeout prudente: el HTML se carga casi inmediatamente y
  /// model-viewer muestra su propio indicador de progreso mientras descarga
  /// el .glb. Removemos el overlay de Flutter para revelar el visor.
  void _startWebLoadFallback() {
    if (!kIsWeb) return;

    debugPrint('[MapViewWeb][Web] Iniciando fallback de carga por timeout');

    // Timeout corto: revelar el visor después de 3 segundos.
    // model-viewer muestra su propio progreso para el modelo .glb
    _webLoadPoller?.cancel();
    _webLoadPoller = Timer(const Duration(seconds: 3), () {
      if (mounted && _isLoading) {
        debugPrint('[MapViewWeb][Web] Timeout alcanzado → revelando visor');
        setState(() {
          _isLoading = false;
          _hasError = false;
        });
        widget.onMapLoaded?.call();
      }
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // API pública: Comunicación Flutter → Web
  // ══════════════════════════════════════════════════════════════════════════

  /// Mueve la cámara suavemente hacia un punto y órbita específicos.
  /// [target] → Coordenadas del objetivo, ej: "0m 1m 0m"
  /// [orbit]  → Órbita de cámara, ej: "45deg 55deg 5m"
  Future<void> updateCamera(String target, String orbit) async {
    if (_webViewController == null) return;
    await _webViewController!.evaluateJavascript(
      source: "updateCamera('$target', '$orbit');",
    );
    debugPrint('[MapViewWeb][Flutter→Web] updateCamera($target, $orbit)');
  }

  /// Resetea la cámara a la posición por defecto.
  Future<void> resetCamera() async {
    if (_webViewController == null) return;
    await _webViewController!.evaluateJavascript(
      source: "resetCamera();",
    );
  }

  /// Carga un modelo de avatar en el visor secundario.
  Future<void> loadAvatar(String avatarSrc) async {
    if (_webViewController == null) return;
    await _webViewController!.evaluateJavascript(
      source: "loadAvatar('$avatarSrc');",
    );
  }

  /// Posiciona el avatar en la escena 3D.
  /// [x], [y] → Posición en porcentaje (0-100)
  /// [z] → Escala del avatar (1.0 = tamaño normal)
  Future<void> setAvatarPosition(double x, double y, double z) async {
    if (_webViewController == null) return;
    await _webViewController!.evaluateJavascript(
      source: "setAvatarPosition($x, $y, $z);",
    );
  }

  /// Oculta el avatar de la escena.
  Future<void> hideAvatar() async {
    if (_webViewController == null) return;
    await _webViewController!.evaluateJavascript(
      source: "hideAvatar();",
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Build del WebView
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── InAppWebView con el motor model-viewer ──
        InAppWebView(
          initialData: InAppWebViewInitialData(
            data: _initialHtml,
            mimeType: 'text/html',
            encoding: 'utf-8',
            baseUrl: WebUri('https://localhost'),
          ),

          // ── Configuración optimizada para Sunmi K2 Pro ──
          initialSettings: InAppWebViewSettings(
            // Rendimiento
            hardwareAcceleration: true,
            useHybridComposition: true,
            transparentBackground: true,

            // Permisos necesarios para model-viewer
            javaScriptEnabled: true,
            allowFileAccessFromFileURLs: true,
            allowUniversalAccessFromFileURLs: true,
            mediaPlaybackRequiresUserGesture: false,

            // Evitar scroll no deseado dentro del WebView
            supportZoom: false,
            builtInZoomControls: false,
            displayZoomControls: false,

            // WebGL y 3D
            useWideViewPort: true,
            loadWithOverviewMode: true,

            // Caché agresivo para modelos pesados
            cacheEnabled: true,
            cacheMode: CacheMode.LOAD_DEFAULT,

            // Depuración (desactivar en producción)
            isInspectable: true,
          ),

          // ── Evento: WebView creado ──
          onWebViewCreated: (controller) {
            _webViewController = controller;

            // Registrar handlers para comunicación JS → Flutter.
            // NOTA: addJavaScriptHandler NO está implementado en web,
            //       por eso usamos try-catch y fallback por polling.
            try {
              controller.addJavaScriptHandler(
                handlerName: 'onMapLoaded',
                callback: (args) {
                  debugPrint('[MapViewWeb][Web→Flutter] Mapa cargado: $args');
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                      _hasError = false;
                    });
                    widget.onMapLoaded?.call();
                  }
                  return null;
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'onMapError',
                callback: (args) {
                  debugPrint('[MapViewWeb][Web→Flutter] Error: $args');
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                      _hasError = true;
                    });
                    widget.onError?.call();
                  }
                  return null;
                },
              );
            } catch (e) {
              debugPrint(
                '[MapViewWeb] addJavaScriptHandler no soportado (web): $e',
              );
              debugPrint(
                '[MapViewWeb] Usando polling como fallback',
              );
            }

            // En web, los callbacks onLoadStop/onConsoleMessage no funcionan
            // con flutter_inappwebview. Iniciamos polling directamente con
            // un pequeño delay para dar tiempo al HTML a cargar.
            if (kIsWeb) {
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted && _isLoading) {
                  _startWebLoadFallback();
                }
              });
            }
          },

          // ── Mensajes de consola del WebView (depuración) ──
          onConsoleMessage: (controller, consoleMessage) {
            debugPrint(
              '[MapViewWeb][Console] ${consoleMessage.message}',
            );

            // Detectar mensaje de carga como respaldo
            if (consoleMessage.message.contains('cargado correctamente')) {
              if (mounted && _isLoading) {
                setState(() {
                  _isLoading = false;
                  _hasError = false;
                });
                widget.onMapLoaded?.call();
              }
            }
          },

          // ── Carga completada del HTML ──
          onLoadStop: (controller, url) {
            debugPrint('[MapViewWeb] HTML cargado en WebView');

            // En web, iniciar polling para detectar carga del modelo
            if (kIsWeb) {
              _startWebLoadFallback();
            }

            // Si hay un avatar configurado, cargarlo automáticamente
            if (widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty) {
              loadAvatar(widget.avatarUrl!);
            }
          },

          // ── Error de carga ──
          onReceivedError: (controller, request, error) {
            debugPrint(
              '[MapViewWeb][ERROR] ${error.description}',
            );
            // Solo marcar error si es la carga principal, no recursos secundarios
            if (request.url.toString().contains('localhost')) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _hasError = true;
                });
                widget.onError?.call();
              }
            }
          },
        ),

        // ── Overlay de carga con indicador ──
        if (_isLoading)
          Positioned.fill(
            child: Container(
              color: AppColors.background,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Indicador de progreso circular
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 3,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Cargando mapa 3D…',
                      style: TextStyle(
                        color: AppColors.textSecondaryMuted,
                        fontSize: 13,
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
              color: AppColors.background,
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
                    const SizedBox(height: 20),

                    // Botón para reintentar
                    TextButton.icon(
                      onPressed: () {
                        if (mounted) {
                          setState(() {
                            _isLoading = true;
                            _hasError = false;
                          });
                          _webViewController?.reload();
                        }
                      },
                      icon: const Icon(
                        Icons.refresh_rounded,
                        color: AppColors.primary,
                        size: 18,
                      ),
                      label: const Text(
                        'Reintentar',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
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
