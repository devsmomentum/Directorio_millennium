import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../theme/app_theme.dart';

// ============================================================================
// MapViewWeb — Visor 3D basado en InAppWebView + three.js
// ============================================================================
// Este widget carga un HTML estático con three.js para renderizar
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
  // HTML inyectado con three.js y lógica de avatar
  // ══════════════════════════════════════════════════════════════════════════
  String get _initialHtml =>
      '''
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Mapa 3D</title>

  <script type="module" src="https://unpkg.com/@google/model-viewer/dist/model-viewer.min.js"></script>

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

    /* Canvas principal renderizado por three.js */
    #map-canvas {
      width: 100%;
      height: 100%;
      display: block;
      background: transparent;
      touch-action: none;
    }

    /* Overlay del avatar (se mantiene por compatibilidad) */
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

    /* Botón de centrado mejorado estilo App moderna */
    #center-view-btn {
      position: absolute;
      bottom: 16px;
      right: 16px;
      z-index: 40;
      width: 48px;
      height: 48px;
      border: 2px solid rgba(255, 0, 122, 0.4); /* Color primario con transparencia */
      border-radius: 50%;
      background-color: #212121; /* surfaceLight */
      background-image: url('data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="%23FF007A"><path d="M12 8c-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4-1.79-4-4-4zm8.94 3A8.994 8.994 0 0 0 13 3.06V1h-2v2.06A8.994 8.994 0 0 0 3.06 11H1v2h2.06A8.994 8.994 0 0 0 11 20.94V23h2v-2.06A8.994 8.994 0 0 0 20.94 13H23v-2h-2.06zM12 19c-3.87 0-7-3.13-7-7s3.13-7 7-7 7 3.13 7 7-3.13 7-7 7z"/></svg>');
      background-size: 24px 24px;
      background-position: center;
      background-repeat: no-repeat;
      box-shadow: 0 4px 12px rgba(255, 0, 122, 0.2), 0 4px 8px rgba(0, 0, 0, 0.4);
      cursor: pointer;
      color: transparent; /* Ocultar texto */
      font-size: 0;
      transition: transform 0.2s ease, background-color 0.2s ease;
      user-select: none;
      -webkit-user-select: none;
      touch-action: manipulation;
    }

    #center-view-btn:active {
      transform: scale(0.92);
      background-color: #2a2a2a;
    }
  </style>
</head>
<body>
  <div id="viewer-container">
    <canvas id="map-canvas"></canvas>

    <model-viewer
      id="avatar-viewer"
      alt="Avatar del usuario"
      autoplay
      animation-name="Caminar"
      shadow-intensity="0"
      environment-image="neutral"
      exposure="1"
    ></model-viewer>

    <button id="center-view-btn" type="button" aria-label="Centrar mapa"></button>
  </div>

  <script type="module">
    import * as THREE from 'https://cdn.jsdelivr.net/npm/three@0.164.1/+esm';
    import { OrbitControls } from 'https://cdn.jsdelivr.net/npm/three@0.164.1/examples/jsm/controls/OrbitControls.js/+esm';
    import { GLTFLoader } from 'https://cdn.jsdelivr.net/npm/three@0.164.1/examples/jsm/loaders/GLTFLoader.js/+esm';

    const MODEL_URL = '${widget.modelUrl}';
    const AVATAR_URL = '${widget.avatarUrl ?? ''}';

    const container = document.getElementById('viewer-container');
    const canvas = document.getElementById('map-canvas');
    const avatarViewer = document.getElementById('avatar-viewer');
    const centerViewBtn = document.getElementById('center-view-btn');

    let avatarMoving = false;
    let avatarAnimFrame = null;

    const scene = new THREE.Scene();

    const renderer = new THREE.WebGLRenderer({
      canvas: canvas,
      antialias: true,
      alpha: true,
      powerPreference: 'high-performance',
    });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    renderer.setSize(container.clientWidth, container.clientHeight, false);
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.0;
    renderer.shadowMap.enabled = false;

    const camera = new THREE.PerspectiveCamera(
      40,
      container.clientWidth / Math.max(container.clientHeight, 1),
      0.05,
      2500,
    );

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.dampingFactor = 0.08;
    controls.zoomSpeed = 1.2; // Aumentado para un zoom más rápido
    controls.rotateSpeed = 0.55;
    controls.panSpeed = 0.8; // Aumentado para mejor paneo
    controls.enablePan = true;
    controls.screenSpacePanning = false;
    controls.minPolarAngle = THREE.MathUtils.degToRad(6);
    controls.maxPolarAngle = THREE.MathUtils.degToRad(86);
    controls.minDistance = 3.0;
    controls.maxDistance = 18.0;
    controls.target.set(0, 0, 0);

    // Variables para la transición suave de la cámara
    let isCameraTransitioning = false;
    let camTransitionProgress = 0;
    let startCamPos = new THREE.Vector3();
    let targetCamPos = new THREE.Vector3();
    let startCamTarget = new THREE.Vector3();
    let targetCamTarget = new THREE.Vector3();

    // Cancelar transición suave si el usuario interfiere tocando el mapa
    controls.addEventListener('start', function() {
      isCameraTransitioning = false;
    });

    const hemiLight = new THREE.HemisphereLight(0xffffff, 0x77808b, 0.95);
    scene.add(hemiLight);

    const keyLight = new THREE.DirectionalLight(0xffffff, 0.8);
    keyLight.position.set(8, 12, 6);
    scene.add(keyLight);

    let mapModel = null;
    let mapBounds = null;
    let mapCenter = new THREE.Vector3(0, 0, 0);
    let minDistance = 3.0;
    let maxDistance = 18.0;
    let minTargetX = -10.0;
    let maxTargetX = 10.0;
    let minTargetZ = -10.0;
    let maxTargetZ = 10.0;

    const raycaster = new THREE.Raycaster();
    const pointerNdc = new THREE.Vector2();
    let pointerStartX = 0;
    let pointerStartY = 0;
    let pointerStartTime = 0;

    function notifyFlutter(handlerName, payload) {
      if (!window.flutter_inappwebview) return;
      window.flutter_inappwebview.callHandler(handlerName, payload);
    }

    function parseLength(rawValue, fallbackValue) {
      if (rawValue == null) return fallbackValue;
      const raw = String(rawValue).trim().toLowerCase();
      if (!raw || raw === 'auto') return fallbackValue;

      if (raw.endsWith('%')) {
        const percent = parseFloat(raw.slice(0, -1));
        if (!Number.isFinite(percent)) return fallbackValue;
        return (percent / 100.0) * maxDistance;
      }

      const parsed = parseFloat(raw.replace('m', ''));
      return Number.isFinite(parsed) ? parsed : fallbackValue;
    }

    function parseDegrees(rawValue, fallbackValue) {
      if (rawValue == null) return fallbackValue;
      const raw = String(rawValue).trim().toLowerCase();
      if (!raw || raw === 'auto') return fallbackValue;
      const parsed = parseFloat(raw.replace('deg', ''));
      return Number.isFinite(parsed)
        ? THREE.MathUtils.degToRad(parsed)
        : fallbackValue;
    }

    function clampTargetToMap() {
      controls.target.x = THREE.MathUtils.clamp(
        controls.target.x,
        minTargetX,
        maxTargetX,
      );
      controls.target.z = THREE.MathUtils.clamp(
        controls.target.z,
        minTargetZ,
        maxTargetZ,
      );
      controls.target.y = mapCenter.y;
    }

    function enforceCameraLimits() {
      clampTargetToMap();

      const offset = new THREE.Vector3().subVectors(
        camera.position,
        controls.target,
      );

      let distance = offset.length();
      if (!Number.isFinite(distance) || distance < 0.001) {
        distance = minDistance;
        offset.set(0, distance, 0);
      }

      distance = THREE.MathUtils.clamp(distance, minDistance, maxDistance);

      const ratio = THREE.MathUtils.clamp(offset.y / distance, -1, 1);
      let polar = Math.acos(ratio);
      polar = THREE.MathUtils.clamp(
        polar,
        controls.minPolarAngle,
        controls.maxPolarAngle,
      );

      const azimuth = Math.atan2(offset.x, offset.z);
      const sinPolar = Math.sin(polar);
      offset.set(
        distance * sinPolar * Math.sin(azimuth),
        distance * Math.cos(polar),
        distance * sinPolar * Math.cos(azimuth),
      );

      camera.position.copy(controls.target).add(offset);
      camera.lookAt(controls.target);
    }

    // Nueva función para iniciar la animación suave de la cámara
    function startCameraTransition(newCamPos, newTargetPos) {
      // Guardar estados actuales
      const currentCamPos = camera.position.clone();
      const currentTarget = controls.target.clone();

      // Configurar destino temporal para asegurar que respete los limites
      camera.position.copy(newCamPos);
      controls.target.copy(newTargetPos);
      enforceCameraLimits();

      // Guardar destinos finales válidos
      targetCamPos.copy(camera.position);
      targetCamTarget.copy(controls.target);

      // Restaurar cámara a posición inicial y comenzar animación
      camera.position.copy(currentCamPos);
      controls.target.copy(currentTarget);

      startCamPos.copy(camera.position);
      startCamTarget.copy(controls.target);

      isCameraTransitioning = true;
      camTransitionProgress = 0;
    }

    function centerTopView() {
      const radiusX = Math.max((maxTargetX - minTargetX) * 0.5, 1.0);
      const radiusZ = Math.max((maxTargetZ - minTargetZ) * 0.5, 1.0);
      const baseRadius = Math.max(radiusX, radiusZ);
      const distance = THREE.MathUtils.clamp(
        baseRadius * 0.92,
        minDistance + 0.2,
        maxDistance - 0.2,
      );

      const nextTarget = mapCenter.clone();
      const nextCamPos = new THREE.Vector3(
        mapCenter.x,
        mapCenter.y + distance,
        mapCenter.z + distance * 0.2,
      );

      startCameraTransition(nextCamPos, nextTarget);
      console.log('[MapViewWeb] Vista superior centrada');
    }

    function centerCameraOnPoint(point) {
      if (!point || !mapBounds) return false;

      const nextTarget = point.clone();
      nextTarget.y = mapCenter.y;

      // Calcular el offset basado en donde está la cámara ahora mismo (o donde se dirige)
      const offset = new THREE.Vector3().subVectors(
        isCameraTransitioning ? targetCamPos : camera.position,
        isCameraTransitioning ? targetCamTarget : controls.target,
      );

      const nextCamPos = new THREE.Vector3().copy(nextTarget).add(offset);
      startCameraTransition(nextCamPos, nextTarget);
      return true;
    }

    function centerCameraFromScreen(clientX, clientY) {
      if (!mapModel) return false;

      const rect = renderer.domElement.getBoundingClientRect();
      const width = Math.max(rect.width, 1);
      const height = Math.max(rect.height, 1);

      pointerNdc.x = ((clientX - rect.left) / width) * 2 - 1;
      pointerNdc.y = -((clientY - rect.top) / height) * 2 + 1;

      raycaster.setFromCamera(pointerNdc, camera);
      const hits = raycaster.intersectObject(mapModel, true);
      if (!hits || hits.length === 0) return false;

      return centerCameraOnPoint(hits[0].point);
    }

    function centerOnMapPoint(x, y, z) {
      const px = Number(x);
      const py = Number(y);
      const pz = Number(z);
      if (!Number.isFinite(px) || !Number.isFinite(py) || !Number.isFinite(pz)) {
        return false;
      }
      return centerCameraOnPoint(new THREE.Vector3(px, py, pz));
    }

    function updateCamera(target, orbit) {
      if (!mapBounds) return;

      const nextTarget = controls.target.clone();

      if (target) {
        const parts = String(target).trim().split(/\s+/);
        if (parts.length >= 3) {
          nextTarget.set(
            parseLength(parts[0], mapCenter.x),
            parseLength(parts[1], mapCenter.y),
            parseLength(parts[2], mapCenter.z),
          );
        }
      }

      let theta = 0.0;
      let phi = THREE.MathUtils.degToRad(18);
      let radius = (minDistance + maxDistance) * 0.5;

      if (orbit) {
        const parts = String(orbit).trim().split(/\s+/);
        if (parts.length >= 3) {
          theta = parseDegrees(parts[0], theta);
          phi = parseDegrees(parts[1], phi);
          radius = parseLength(parts[2], radius);
        }
      }

      phi = THREE.MathUtils.clamp(phi, controls.minPolarAngle, controls.maxPolarAngle);
      radius = THREE.MathUtils.clamp(radius, minDistance, maxDistance);

      const sinPhi = Math.sin(phi);
      const offset = new THREE.Vector3(
        radius * sinPhi * Math.sin(theta),
        radius * Math.cos(phi),
        radius * sinPhi * Math.cos(theta),
      );

      const nextCamPos = new THREE.Vector3().copy(nextTarget).add(offset);
      startCameraTransition(nextCamPos, nextTarget);

      console.log('[MapViewWeb] Cámara actualizada → target: ' + target + ', orbit: ' + orbit);
    }

    function resetCamera() {
      centerTopView();
      console.log('[MapViewWeb] Cámara reseteada');
    }

    function loadAvatar(avatarSrc) {
      if (!avatarViewer || !avatarSrc) return;
      avatarViewer.src = avatarSrc;
      avatarViewer.style.display = 'block';
      console.log('[MapViewWeb] Avatar cargado: ' + avatarSrc);
    }

    function setAvatarPosition(x, y, z) {
      if (!avatarViewer) return;

      avatarViewer.style.left = x + '%';
      avatarViewer.style.bottom = y + '%';
      avatarViewer.style.transform = 'translateX(-50%) scale(' + (z || 1) + ')';

      if (!avatarMoving) {
        avatarMoving = true;
        avatarViewer.animationName = 'Caminar';
        avatarViewer.play();
      }

      if (avatarAnimFrame) clearTimeout(avatarAnimFrame);
      avatarAnimFrame = setTimeout(function() {
        avatarMoving = false;
        try {
          avatarViewer.animationName = 'Idle';
          avatarViewer.play();
        } catch (e) {
          avatarViewer.pause();
        }
      }, 500);

      console.log('[MapViewWeb] Avatar posición → x:' + x + ' y:' + y + ' z:' + z);
    }

    function hideAvatar() {
      if (!avatarViewer) return;
      avatarViewer.style.display = 'none';
      console.log('[MapViewWeb] Avatar oculto');
    }

    window.updateCamera = updateCamera;
    window.resetCamera = resetCamera;
    window.centerTopView = centerTopView;
    window.centerOnMapPoint = centerOnMapPoint;
    window.loadAvatar = loadAvatar;
    window.setAvatarPosition = setAvatarPosition;
    window.hideAvatar = hideAvatar;

    if (centerViewBtn) {
      centerViewBtn.addEventListener('click', function(event) {
        event.preventDefault();
        event.stopPropagation();
        centerTopView();
      });
    }

    function onResize() {
      const width = Math.max(container.clientWidth, 1);
      const height = Math.max(container.clientHeight, 1);
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
      renderer.setSize(width, height, false);
      renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    }
    window.addEventListener('resize', onResize);

    function onCanvasPointerDown(event) {
      if (event.pointerType === 'mouse' && event.button !== 0) return;
      pointerStartX = event.clientX;
      pointerStartY = event.clientY;
      pointerStartTime = performance.now();
    }

    function onCanvasPointerUp(event) {
      if (event.pointerType === 'mouse' && event.button !== 0) return;

      const dx = event.clientX - pointerStartX;
      const dy = event.clientY - pointerStartY;
      const movedSquared = (dx * dx) + (dy * dy);
      const elapsed = performance.now() - pointerStartTime;

      if (movedSquared > 64 || elapsed > 500) return;

      const centered = centerCameraFromScreen(event.clientX, event.clientY);
      if (centered) {
        console.log('[MapViewWeb] Centro actualizado por seleccion de punto');
      }
    }

    renderer.domElement.addEventListener('pointerdown', onCanvasPointerDown);
    renderer.domElement.addEventListener('pointerup', onCanvasPointerUp);

    const loader = new GLTFLoader();
    loader.load(
      MODEL_URL,
      function(gltf) {
        mapModel = gltf.scene;
        scene.add(mapModel);

        mapModel.traverse(function(obj) {
          if (!obj.isMesh) return;
          if (Array.isArray(obj.material)) {
            obj.material.forEach(function(mat) {
              if (mat && 'roughness' in mat) {
                mat.roughness = Math.max(mat.roughness ?? 1.0, 0.65);
              }
              if (mat && 'metalness' in mat) {
                mat.metalness = Math.min(mat.metalness ?? 0.0, 0.25);
              }
              if (mat) mat.needsUpdate = true;
            });
          } else if (obj.material) {
            if ('roughness' in obj.material) {
              obj.material.roughness = Math.max(obj.material.roughness ?? 1.0, 0.65);
            }
            if ('metalness' in obj.material) {
              obj.material.metalness = Math.min(obj.material.metalness ?? 0.0, 0.25);
            }
            obj.material.needsUpdate = true;
          }
        });

        mapBounds = new THREE.Box3().setFromObject(mapModel);
        if (mapBounds.isEmpty()) {
          throw new Error('Bounding box del mapa vacía');
        }

        mapCenter = mapBounds.getCenter(new THREE.Vector3());
        const size = mapBounds.getSize(new THREE.Vector3());
        const radiusXZ = Math.max(size.x, size.z) * 0.5;

        minDistance = Math.max(radiusXZ * 0.32, 1.2);
        maxDistance = Math.max(radiusXZ * 0.95, minDistance + 2.4);
        controls.minDistance = minDistance;
        controls.maxDistance = maxDistance;

        const marginX = Math.max(size.x * 0.03, 0.35);
        const marginZ = Math.max(size.z * 0.03, 0.35);
        minTargetX = mapBounds.min.x - marginX;
        maxTargetX = mapBounds.max.x + marginX;
        minTargetZ = mapBounds.min.z - marginZ;
        maxTargetZ = mapBounds.max.z + marginZ;

        camera.near = Math.max(0.03, minDistance * 0.03);
        camera.far = Math.max(2500, maxDistance * 60.0);
        camera.updateProjectionMatrix();

        centerTopView();
        if (AVATAR_URL) loadAvatar(AVATAR_URL);

        console.log('[MapViewWeb] Modelo del mapa cargado correctamente');
        notifyFlutter('onMapLoaded', 'ok');
      },
      undefined,
      function(error) {
        const message = error && error.message
          ? error.message
          : 'Error al cargar el modelo';
        console.log('[MapViewWeb][ERROR] ' + message);
        notifyFlutter('onMapError', message);
      },
    );

    function animate() {
      requestAnimationFrame(animate);

      // Lógica de transición suave (Ease-Out Cubic)
      if (isCameraTransitioning) {
        camTransitionProgress += 0.04; // Ajusta este valor para hacer la animación más rápida o lenta
        if (camTransitionProgress >= 1) {
          camTransitionProgress = 1;
          isCameraTransitioning = false;
        }
        
        const t = camTransitionProgress;
        const ease = 1 - Math.pow(1 - t, 3); // Ease-Out para frenar suavemente

        camera.position.lerpVectors(startCamPos, targetCamPos, ease);
        controls.target.lerpVectors(startCamTarget, targetCamTarget, ease);
      } else {
        enforceCameraLimits(); // Solo aplicar los límites rígidos si no estamos transicionando
      }

      controls.update();
      renderer.render(scene, camera);
    }
    animate();
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
  /// three.js continúa la descarga/render del .glb en segundo plano.
  /// Removemos el overlay de Flutter para revelar el visor.
  void _startWebLoadFallback() {
    if (!kIsWeb) return;

    debugPrint('[MapViewWeb][Web] Iniciando fallback de carga por timeout');

    // Timeout corto: revelar el visor después de 3 segundos.
    // three.js continuará el render aunque el modelo siga cargando.
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
    await _webViewController!.evaluateJavascript(source: "resetCamera();");
  }

  /// Centra el mapa con una vista superior y cercana.
  Future<void> centerTopView() async {
    if (_webViewController == null) return;
    await _webViewController!.evaluateJavascript(source: "centerTopView();");
    debugPrint('[MapViewWeb][Flutter→Web] centerTopView()');
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
    await _webViewController!.evaluateJavascript(source: "hideAvatar();");
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Build del WebView
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── InAppWebView con renderer three.js ──
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

            // Permisos necesarios para scripts WebGL/three.js
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
              debugPrint('[MapViewWeb] Usando polling como fallback');
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
            debugPrint('[MapViewWeb][Console] ${consoleMessage.message}');

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
            debugPrint('[MapViewWeb][ERROR] ${error.description}');
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
                      style: TextStyle(color: AppColors.textHint, fontSize: 12),
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