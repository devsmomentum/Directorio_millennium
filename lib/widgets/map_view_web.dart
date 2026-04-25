import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../theme/app_theme.dart';
import 'map_view_post_msg.dart'
    if (dart.library.js_interop) 'map_view_post_msg_web.dart';

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

  /// Callback cuando el avatar llega al último waypoint de la ruta.
  final VoidCallback? onAvatarArrived;

  const MapViewWeb({
    super.key,
    required this.modelUrl,
    this.avatarUrl,
    this.onMapLoaded,
    this.onError,
    this.onAvatarArrived,
  });

  @override
  State<MapViewWeb> createState() => MapViewWebState();
}

class MapViewWebState extends State<MapViewWeb> {
  InAppWebViewController? _webViewController;
  bool _isLoading = true;
  bool _hasError = false;
  Timer? _webLoadPoller;
  String _webCommandBootstrap = '';

  // ── Canal postMessage (Flutter Web → iframe). Permite empujar comandos
  // sin recargar el HTML cada vez. El primer comando puede llegar antes de
  // que la iframe haga el handshake `mapview-ready`; en ese caso caemos al
  // bootstrap-reload tradicional. Llamadas posteriores ya usan postMessage.
  final String _instanceId = _generateInstanceId();
  final MapViewPostBridge _postBridge = MapViewPostBridge();
  bool _postBridgeReady = false;

  static String _generateInstanceId() {
    final r = Random.secure();
    final bytes = List<int>.generate(8, (_) => r.nextInt(256));
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

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

    /* Panel de calibración (debug) */
    #calib-panel {
      position: absolute;
      top: 12px;
      right: 12px;
      z-index: 60;
      width: 220px;
      padding: 10px 10px 8px;
      border-radius: 10px;
      background: rgba(10, 12, 18, 0.78);
      border: 1px solid rgba(255, 255, 255, 0.10);
      backdrop-filter: blur(10px);
      color: rgba(255,255,255,0.92);
      font-family: system-ui, -apple-system, Segoe UI, Roboto, sans-serif;
      display: none; /* toggle con tecla C */
    }
    #calib-panel h4 {
      font-size: 12px;
      margin: 0 0 8px;
      letter-spacing: 0.3px;
      opacity: 0.95;
    }
    .calib-row { margin-bottom: 7px; }
    .calib-row label {
      display: flex;
      justify-content: space-between;
      font-size: 11px;
      opacity: 0.85;
      margin-bottom: 3px;
    }
    .calib-row input[type="range"] { width: 100%; }
    #calib-hint {
      font-size: 10px;
      opacity: 0.75;
      margin-top: 6px;
      line-height: 1.25;
    }
  </style>
</head>
<body>
  <div id="viewer-container">
    <canvas id="map-canvas"></canvas>

    <button id="center-view-btn" type="button" aria-label="Centrar mapa"></button>

    <div id="calib-panel">
      <h4>Calibración mapa (C)</h4>
      <div class="calib-row">
        <label><span>Scale</span><span id="calib-scale-val">1.00</span></label>
        <input id="calib-scale" type="range" min="0.1" max="10" step="0.01" value="1">
      </div>
      <div class="calib-row">
        <label><span>Offset X</span><span id="calib-ox-val">0.00</span></label>
        <input id="calib-ox" type="range" min="-200" max="200" step="0.1" value="0">
      </div>
      <div class="calib-row">
        <label><span>Offset Y</span><span id="calib-oy-val">0.00</span></label>
        <input id="calib-oy" type="range" min="-50" max="50" step="0.1" value="0">
      </div>
      <div class="calib-row">
        <label><span>Offset Z</span><span id="calib-oz-val">0.00</span></label>
        <input id="calib-oz" type="range" min="-200" max="200" step="0.1" value="0">
      </div>
      <div class="calib-row">
        <label><span>Rot Y (°)</span><span id="calib-rot-val">0.0</span></label>
        <input id="calib-rot" type="range" min="-180" max="180" step="0.5" value="0">
      </div>
      <div id="calib-hint">Ajusta hasta que nodos/recorrido coincidan. Se guarda por URL del modelo.</div>
    </div>
  </div>

  <script>
    // Comandos que Flutter web no puede inyectar vía evaluateJavascript.
    // Se rellenan desde Dart y se ejecutan al final del módulo.
    window.__flutterBootstrapCommands = ${jsonEncode(_webCommandBootstrap)};
    // Identificador único de esta instancia: usado por el host Flutter Web
    // para enrutar comandos via postMessage cuando hay varias iframes.
    window.__milemiumInstanceId = ${jsonEncode(_instanceId)};
  </script>

  <script type="module">
    import * as THREE from 'https://cdn.jsdelivr.net/npm/three@0.164.1/+esm';
    import { OrbitControls } from 'https://cdn.jsdelivr.net/npm/three@0.164.1/examples/jsm/controls/OrbitControls.js/+esm';
    import { GLTFLoader } from 'https://cdn.jsdelivr.net/npm/three@0.164.1/examples/jsm/loaders/GLTFLoader.js/+esm';

    console.log('[MapViewWeb][Debug] JS actualizado: walk-loop + postMessage (2026-04-25)');
    // Handshake para que Flutter sepa que el módulo inicializó.
    window.__bridgeReady = true;

    // ── Canal postMessage entrante: el host (Flutter Web) empuja comandos
    //    sin recargar el HTML. Cada caso resuelve a la función global
    //    correspondiente que ya expone el módulo (window.startAvatarRoute,
    //    etc). Si la función aún no está definida (módulo todavía cargando
    //    THREE.js / GLBs), simplemente hacemos no-op; el host reintentará.
    window.addEventListener('message', function(event) {
      try {
        const raw = event.data;
        if (typeof raw !== 'string' || raw.length === 0) return;
        const msg = JSON.parse(raw);
        if (!msg || typeof msg !== 'object') return;
        const cmd = msg.cmd;
        if (!cmd) return;
        switch (cmd) {
          case 'startAvatarRoute':
            if (window.startAvatarRoute) window.startAvatarRoute(msg.payload, msg.opts);
            break;
          case 'stopAvatarRoute':
            if (window.stopAvatarRoute) window.stopAvatarRoute();
            break;
          case 'hideAvatar':
            if (window.hideAvatar) window.hideAvatar();
            break;
          case 'setAvatarAtWorld':
            if (window.setAvatarAtWorld) window.setAvatarAtWorld(msg.x, msg.y, msg.z);
            break;
          case 'setMapCalibration':
            if (window.setMapCalibration) window.setMapCalibration(msg.calib);
            break;
        }
      } catch (e) {
        console.log('[MapViewWeb][postMessage] error: ' + String(e));
      }
    });

    // Handshake hacia el host: avisamos que estamos listos para recibir
    // comandos. El host (Dart) guarda event.source como nuestra ventana.
    try {
      const ready = JSON.stringify({
        kind: 'mapview-ready',
        instanceId: window.__milemiumInstanceId || '',
      });
      window.parent && window.parent.postMessage(ready, '*');
    } catch (_) { /* iframe en sandbox/sin parent: ignorar */ }

    const MODEL_URL = '${widget.modelUrl}';
    const AVATAR_URL = '${widget.avatarUrl ?? ''}';

    const container = document.getElementById('viewer-container');
    const canvas = document.getElementById('map-canvas');
    const centerViewBtn = document.getElementById('center-view-btn');
    const calibPanel = document.getElementById('calib-panel');
    const calibScale = document.getElementById('calib-scale');
    const calibOx = document.getElementById('calib-ox');
    const calibOy = document.getElementById('calib-oy');
    const calibOz = document.getElementById('calib-oz');
    const calibRot = document.getElementById('calib-rot');

    const calibScaleVal = document.getElementById('calib-scale-val');
    const calibOxVal = document.getElementById('calib-ox-val');
    const calibOyVal = document.getElementById('calib-oy-val');
    const calibOzVal = document.getElementById('calib-oz-val');
    const calibRotVal = document.getElementById('calib-rot-val');

    const calibStorageKey = 'milemium:mapCalib:' + MODEL_URL;
    let mapCalibration = { scale: 1, ox: 0, oy: 0, oz: 0, rotY: 0 };

    function loadStoredCalibration() {
      try {
        const raw = localStorage.getItem(calibStorageKey);
        if (!raw) return;
        const obj = JSON.parse(raw);
        if (!obj) return;
        mapCalibration = {
          scale: Number(obj.scale) || 1,
          ox: Number(obj.ox) || 0,
          oy: Number(obj.oy) || 0,
          oz: Number(obj.oz) || 0,
          rotY: Number(obj.rotY) || 0,
        };
      } catch (_) {}
    }

    function persistCalibration() {
      try {
        localStorage.setItem(calibStorageKey, JSON.stringify(mapCalibration));
      } catch (_) {}
    }

    function syncCalibUI() {
      calibScale.value = String(mapCalibration.scale);
      calibOx.value = String(mapCalibration.ox);
      calibOy.value = String(mapCalibration.oy);
      calibOz.value = String(mapCalibration.oz);
      calibRot.value = String(mapCalibration.rotY);
      calibScaleVal.textContent = mapCalibration.scale.toFixed(2);
      calibOxVal.textContent = mapCalibration.ox.toFixed(2);
      calibOyVal.textContent = mapCalibration.oy.toFixed(2);
      calibOzVal.textContent = mapCalibration.oz.toFixed(2);
      calibRotVal.textContent = mapCalibration.rotY.toFixed(1);
    }

    function applyMapCalibration() {
      if (!mapModel) return;
      const c = mapCalibration;
      mapModel.position.set(c.ox, c.oy, c.oz);
      mapModel.scale.setScalar(Math.max(0.001, c.scale));
      mapModel.rotation.y = (c.rotY || 0) * (Math.PI / 180);
      // Recalcular bounds/centro para cámara y fitting de waypoints.
      mapBounds = new THREE.Box3().setFromObject(mapModel);
      mapCenter = mapBounds.getCenter(new THREE.Vector3());
    }

    function setCalibrationFromUI() {
      mapCalibration.scale = Number(calibScale.value) || 1;
      mapCalibration.ox = Number(calibOx.value) || 0;
      mapCalibration.oy = Number(calibOy.value) || 0;
      mapCalibration.oz = Number(calibOz.value) || 0;
      mapCalibration.rotY = Number(calibRot.value) || 0;
      syncCalibUI();
      applyMapCalibration();
      persistCalibration();
      console.log('[MapViewWeb][Calib]', JSON.stringify(mapCalibration));
    }

    // Exponer setter para Flutter (por si luego quieres guardar en Supabase).
    window.setMapCalibration = function(c) {
      if (!c) return;
      mapCalibration = {
        scale: Number(c.scale) || 1,
        ox: Number(c.ox) || 0,
        oy: Number(c.oy) || 0,
        oz: Number(c.oz) || 0,
        rotY: Number(c.rotY) || 0,
      };
      syncCalibUI();
      applyMapCalibration();
      persistCalibration();
    };

    // Toggle panel con tecla C.
    window.addEventListener('keydown', function(e) {
      if (e.key === 'c' || e.key === 'C') {
        calibPanel.style.display = (calibPanel.style.display === 'none' || !calibPanel.style.display)
          ? 'block'
          : 'none';
      }
    });

    [calibScale, calibOx, calibOy, calibOz, calibRot].forEach(function(input) {
      input.addEventListener('input', setCalibrationFromUI);
    });

    // ─────────────────────────────────────────────────────────────────
    // Estado del avatar 3D (in-scene, no DOM overlay)
    // ─────────────────────────────────────────────────────────────────
    const avatarState = {
      root: null,               // THREE.Group cargado del .glb
      mixer: null,              // THREE.AnimationMixer
      clips: {},                // {walk, idle} → THREE.AnimationClip
      activeAction: null,       // THREE.AnimationAction actual
      scale: 1.0,               // escala opcional para ajustar al mapa
      yOffset: 0.0,             // corrección para apoyar los pies en el piso
      ready: false,
      pendingRoute: null,       // ruta recibida antes de que el modelo estuviera listo

      // Estado de navegación
      route: [],                // Array<Vector3>
      segmentIndex: 0,          // tramo actual (de route[i] a route[i+1])
      segmentProgress: 0.0,     // 0..1 dentro del tramo
      segmentDuration: 0.0,     // segundos para completar el tramo actual
      speed: 1.2,               // unidades/segundo por defecto
      isWalking: false,
      targetQuat: new THREE.Quaternion(),
    };

    // Waypoint markers (debug): esferas para verificar alineación con el mapa.
    let waypointMarkers = [];
    const waypointMarkerMaterial = new THREE.MeshBasicMaterial({
      color: 0xff3b30,
      // Queremos que SIEMPRE se vean para depurar alineación.
      depthTest: false,
      depthWrite: false,
    });

    function clearWaypointMarkers() {
      if (!waypointMarkers || waypointMarkers.length === 0) return;
      for (const m of waypointMarkers) {
        scene.remove(m);
        if (m.geometry) m.geometry.dispose?.();
      }
      waypointMarkers = [];
    }

    function drawWaypointMarkers(waypoints) {
      clearWaypointMarkers();
      if (!Array.isArray(waypoints) || waypoints.length === 0) return;
      const radius = 0.18;
      const geom = new THREE.SphereGeometry(radius, 10, 8);
      for (let i = 0; i < waypoints.length; i++) {
        const w = waypoints[i];
        const mesh = new THREE.Mesh(geom.clone(), waypointMarkerMaterial);
        mesh.position.copy(w);
        // Un poquito arriba para evitar z-fighting con el piso del .glb.
        mesh.position.y += 0.04;
        mesh.renderOrder = 999;
        mesh.frustumCulled = false;
        scene.add(mesh);
        waypointMarkers.push(mesh);
      }
    }

    // ─────────────────────────────────────────────────────────────────
    // Path trail — guía visual animada en el piso del mapa
    // ─────────────────────────────────────────────────────────────────
    const trailState = {
      line: null,        // THREE.Line (línea punteada)
      lineMat: null,     // LineDashedMaterial
      dots: [],          // Meshes de puntos intermedios
      dotKeys: [],       // Progreso 0..1 al que cada dot debe estar visible
      destDot: null,     // Mesh del marcador de destino
      destHalo: null,    // Halo rosa alrededor del destino
      time: 0,           // Acumulador para animaciones de pulso
      // ── Fase de intro: la ruta se "dibuja" en el piso antes de caminar ──
      introDuration: 0.9, // segundos
      introProgress: 0,   // 0..1
      introComplete: false,
      totalLineVerts: 0,  // vértices densificados de la línea (para drawRange)
      onIntroDone: null,  // callback al completarse el intro
    };

    function clearPathTrail() {
      if (trailState.line) {
        scene.remove(trailState.line);
        if (trailState.line.geometry) trailState.line.geometry.dispose();
        if (trailState.lineMat) trailState.lineMat.dispose();
        trailState.line = null;
        trailState.lineMat = null;
      }
      if (trailState.destDot) {
        scene.remove(trailState.destDot);
        if (trailState.destDot.geometry) trailState.destDot.geometry.dispose();
        if (trailState.destDot.material) trailState.destDot.material.dispose();
        trailState.destDot = null;
      }
      if (trailState.destHalo) {
        scene.remove(trailState.destHalo);
        if (trailState.destHalo.geometry) trailState.destHalo.geometry.dispose();
        if (trailState.destHalo.material) trailState.destHalo.material.dispose();
        trailState.destHalo = null;
      }
      for (const d of trailState.dots) {
        scene.remove(d);
        if (d.geometry) d.geometry.dispose();
        if (d.material) d.material.dispose();
      }
      trailState.dots = [];
      trailState.dotKeys = [];
      trailState.time = 0;
      trailState.introProgress = 0;
      trailState.introComplete = false;
      trailState.totalLineVerts = 0;
      trailState.onIntroDone = null;
    }

    function spawnPathTrail(waypoints) {
      clearPathTrail();
      if (!waypoints || waypoints.length < 2) return;

      // Offset mínimo sobre el piso para evitar z-fighting.
      // depthTest:false igual garantiza visibilidad, pero el offset
      // mantiene el trail visualmente "pegado" al suelo desde cualquier ángulo.
      const Y_FLOOR = 0.028;

      // ── Línea punteada animada (marching-ants) ──────────────────────
      // Densificamos la polilínea para que la animación de "dibujado"
      // (drawRange creciendo) se vea fluida aunque haya pocos waypoints.
      const basePts = waypoints.map(function(w) {
        return new THREE.Vector3(w.x, w.y + Y_FLOOR, w.z);
      });
      const SUBDIV = 10; // pasos por segmento original
      const pts = [];
      for (let i = 0; i < basePts.length - 1; i++) {
        const a = basePts[i];
        const b = basePts[i + 1];
        for (let j = 0; j < SUBDIV; j++) {
          const t = j / SUBDIV;
          pts.push(new THREE.Vector3(
            a.x + (b.x - a.x) * t,
            a.y + (b.y - a.y) * t,
            a.z + (b.z - a.z) * t,
          ));
        }
      }
      pts.push(basePts[basePts.length - 1]);

      const lineGeo = new THREE.BufferGeometry().setFromPoints(pts);
      lineGeo.computeLineDistances(); // obligatorio para LineDashedMaterial
      // Arrancamos sin nada visible: la fase de intro ampliará drawRange
      // hasta cubrir todos los vértices y ahí "se dibuja" la ruta en el piso.
      lineGeo.setDrawRange(0, 0);
      const lineMat = new THREE.LineDashedMaterial({
        color: 0xFF007A,
        dashSize: 0.20,
        gapSize: 0.12,
        transparent: true,
        opacity: 0.92, // un poco más fuerte para que "resalte" al dibujarse
        depthTest: false,
        depthWrite: false,
      });
      const pathLine = new THREE.Line(lineGeo, lineMat);
      pathLine.renderOrder = 995;
      pathLine.frustumCulled = false;
      scene.add(pathLine);
      trailState.line = pathLine;
      trailState.lineMat = lineMat;
      trailState.totalLineVerts = pts.length;

      // ── Puntos intermedios (máx. 25 para no saturar Sunmi) ──────────
      const dotBaseGeo = new THREE.CircleGeometry(0.065, 10);
      const MAX_DOTS = 25;
      const totalIntermediate = waypoints.length - 2; // excluir inicio y destino
      const step = totalIntermediate <= MAX_DOTS
        ? 1
        : Math.ceil(totalIntermediate / MAX_DOTS);

      const lastIdx = Math.max(waypoints.length - 1, 1);
      for (let i = 1; i < waypoints.length - 1; i += step) {
        const w = waypoints[i];
        const dot = new THREE.Mesh(
          dotBaseGeo.clone(),
          new THREE.MeshBasicMaterial({
            color: 0xFF007A,
            transparent: true,
            opacity: 0.0, // arranca invisible; el intro lo va revelando
            depthTest: false,
            depthWrite: false,
            side: THREE.DoubleSide,
          }),
        );
        dot.position.set(w.x, w.y + Y_FLOOR, w.z);
        dot.rotation.x = -Math.PI / 2; // plano horizontal (XZ)
        dot.renderOrder = 996;
        dot.frustumCulled = false;
        scene.add(dot);
        trailState.dots.push(dot);
        trailState.dotKeys.push(i / lastIdx);
      }

      // ── Marcador de destino (círculo blanco + halo rosa) ────────────
      const dest = waypoints[waypoints.length - 1];
      const destDot = new THREE.Mesh(
        new THREE.CircleGeometry(0.22, 18),
        new THREE.MeshBasicMaterial({
          color: 0xFFFFFF,
          transparent: true,
          opacity: 0.0, // se revela al final del intro
          depthTest: false,
          depthWrite: false,
          side: THREE.DoubleSide,
        }),
      );
      destDot.position.set(dest.x, dest.y + Y_FLOOR, dest.z);
      destDot.rotation.x = -Math.PI / 2;
      destDot.renderOrder = 999;
      destDot.frustumCulled = false;
      scene.add(destDot);
      trailState.destDot = destDot;

      // Halo exterior rosa alrededor del destino
      const halo = new THREE.Mesh(
        new THREE.RingGeometry(0.23, 0.32, 18),
        new THREE.MeshBasicMaterial({
          color: 0xFF007A,
          transparent: true,
          opacity: 0.0, // también se revela al final del intro
          depthTest: false,
          depthWrite: false,
          side: THREE.DoubleSide,
        }),
      );
      halo.position.set(dest.x, dest.y + Y_FLOOR, dest.z);
      halo.rotation.x = -Math.PI / 2;
      halo.renderOrder = 998;
      halo.frustumCulled = false;
      scene.add(halo);
      trailState.destHalo = halo;
    }

    // ─────────────────────────────────────────────────────────────────

    function computeXZBounds(points) {
      if (!points || points.length === 0) return null;
      let minX = points[0].x, maxX = points[0].x;
      let minZ = points[0].z, maxZ = points[0].z;
      for (let i = 1; i < points.length; i++) {
        const p = points[i];
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        if (p.z < minZ) minZ = p.z;
        if (p.z > maxZ) maxZ = p.z;
      }
      return { minX, maxX, minZ, maxZ };
    }

    function rotateXZ(x, z, angleRad) {
      const c = Math.cos(angleRad);
      const s = Math.sin(angleRad);
      return { x: x * c - z * s, z: x * s + z * c };
    }

    function fitWaypointsToMap(waypoints) {
      if (!mapBounds || !waypoints || waypoints.length === 0) {
        return { waypoints: waypoints, fitted: false };
      }

      const mapSize = mapBounds.getSize(new THREE.Vector3());
      const mapSpanX = Math.max(mapSize.x, 1e-3);
      const mapSpanZ = Math.max(mapSize.z, 1e-3);
      const mapSpan = Math.max(mapSpanX, mapSpanZ, 1e-3);
      const mapC = mapBounds.getCenter(new THREE.Vector3());

      const wpB0 = computeXZBounds(waypoints);
      if (!wpB0) return { waypoints: waypoints, fitted: false };
      const wpCx0 = (wpB0.minX + wpB0.maxX) * 0.5;
      const wpCz0 = (wpB0.minZ + wpB0.maxZ) * 0.5;

      // Evaluamos rotaciones 0/90/180/270 y escogemos la que mejor "encaje".
      const candidates = [0, 90, 180, 270].map(function(deg) {
        return deg * (Math.PI / 180);
      });

      function scoreFor(angleRad) {
        // Rotar alrededor del centro del conjunto de waypoints.
        let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
        for (let i = 0; i < waypoints.length; i++) {
          const p = waypoints[i];
          const rxz = rotateXZ(p.x - wpCx0, p.z - wpCz0, angleRad);
          if (rxz.x < minX) minX = rxz.x;
          if (rxz.x > maxX) maxX = rxz.x;
          if (rxz.z < minZ) minZ = rxz.z;
          if (rxz.z > maxZ) maxZ = rxz.z;
        }
        const spanX = Math.max(maxX - minX, 1e-3);
        const spanZ = Math.max(maxZ - minZ, 1e-3);
        const span = Math.max(spanX, spanZ, 1e-3);

        const scale = (mapSpan * 0.92) / span;

        // Aspect ratio penalty (queremos que el bbox tenga proporción similar al mapa).
        const arWp = spanX / spanZ;
        const arMap = mapSpanX / mapSpanZ;
        const aspectPenalty = Math.abs(Math.log(arWp) - Math.log(arMap));

        // Out-of-bounds penalty: cuántos puntos quedan fuera del bbox del mapa.
        const marginX = mapSpanX * 0.06;
        const marginZ = mapSpanZ * 0.06;
        const minAllowedX = mapBounds.min.x - marginX;
        const maxAllowedX = mapBounds.max.x + marginX;
        const minAllowedZ = mapBounds.min.z - marginZ;
        const maxAllowedZ = mapBounds.max.z + marginZ;

        let oob = 0;
        for (let i = 0; i < waypoints.length; i++) {
          const p = waypoints[i];
          const rxz = rotateXZ(p.x - wpCx0, p.z - wpCz0, angleRad);
          const tx = rxz.x * scale + mapC.x;
          const tz = rxz.z * scale + mapC.z;
          if (tx < minAllowedX || tx > maxAllowedX || tz < minAllowedZ || tz > maxAllowedZ) {
            oob += 1;
          }
        }

        // Ponderación simple: priorizar encaje (oob), luego proporción.
        return { angleRad, scale, spanX, spanZ, aspectPenalty, oob };
      }

      let best = null;
      for (const a of candidates) {
        const s = scoreFor(a);
        if (!best) {
          best = s;
          continue;
        }
        const bestScore = (best.oob * 10.0) + best.aspectPenalty;
        const curScore = (s.oob * 10.0) + s.aspectPenalty;
        if (curScore < bestScore) best = s;
      }

      if (!best) return { waypoints: waypoints, fitted: false };

      // Aplicar transformación ganadora.
      for (let i = 0; i < waypoints.length; i++) {
        const p = waypoints[i];
        const rxz = rotateXZ(p.x - wpCx0, p.z - wpCz0, best.angleRad);
        p.x = rxz.x * best.scale + mapC.x;
        p.z = rxz.z * best.scale + mapC.z;
      }

      console.log(
        '[MapViewWeb][Avatar][Fit] rotY=' + (best.angleRad * 180 / Math.PI).toFixed(0)
        + '° scale=' + best.scale.toFixed(4)
        + ' oob=' + best.oob
        + ' aspectPenalty=' + best.aspectPenalty.toFixed(3)
      );
      return { waypoints: waypoints, fitted: true };
    }

    const clock = new THREE.Clock();

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
        const parts = String(target).trim().split(/s+/);
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
        const parts = String(orbit).trim().split(/s+/);
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

    // ─────────────────────────────────────────────────────────────────
    // AVATAR 3D — sistema completo de carga, animación y pathfinding
    // ─────────────────────────────────────────────────────────────────

    function pickClip(clips, preferredNames) {
      if (!clips || clips.length === 0) return null;
      for (const name of preferredNames) {
        const found = clips.find(function(c) {
          return c.name && c.name.toLowerCase() === name.toLowerCase();
        });
        if (found) return found;
      }
      // Partial match
      for (const name of preferredNames) {
        const found = clips.find(function(c) {
          return c.name && c.name.toLowerCase().indexOf(name.toLowerCase()) !== -1;
        });
        if (found) return found;
      }
      // Fallback absoluto: primer clip disponible (evita T-pose cuando los nombres no coinciden)
      return clips[0] || null;
    }

    // playAction: núcleo del sistema de animación.
    // Política: cambio inmediato sin crossfade para que la animación sea
    // perceptible al instante. En un kiosco la respuesta instantánea
    // prima sobre la transición suave.
    function playAction(clip, loop) {
      if (!clip || !avatarState.mixer) return;
      const loopMode = (loop !== undefined) ? loop : THREE.LoopRepeat;
      const action = avatarState.mixer.clipAction(clip);

      action.setLoop(loopMode, Infinity);
      action.clampWhenFinished = false;
      action.enabled = true;

      // Guard: mismo clip ya corriendo sin pausa → no hacer reset (evita salto a t=0)
      if (action === avatarState.activeAction && action.isRunning() && !action.paused) {
        return;
      }

      // Detener acción previa inmediatamente (sin fade) para evitar conflictos de weight
      if (avatarState.activeAction && avatarState.activeAction !== action) {
        avatarState.activeAction.stop();
      }

      avatarState.activeAction = action;
      action.reset().play();
    }

    function playWalk() {
      const clip = avatarState.clips.walk || avatarState.clips.idle;
      if (clip) playAction(clip);
    }

    function playIdle() {
      const idleClip = avatarState.clips.idle;
      if (idleClip && idleClip !== avatarState.clips.walk) {
        playAction(idleClip);
      } else if (avatarState.activeAction) {
        // Sin clip idle dedicado: pausar en el frame actual
        avatarState.activeAction.paused = true;
      }
    }

    function loadAvatar(avatarSrc, opts) {
      if (!avatarSrc) return;
      const options = opts || {};

      // Si ya hay un avatar con la misma URL, no recargamos.
      if (avatarState.root && avatarState.sourceUrl === avatarSrc) {
        console.log('[MapViewWeb][Avatar] Ya cargado: ' + avatarSrc);
        return;
      }

      // Limpiar avatar previo
      if (avatarState.root) {
        scene.remove(avatarState.root);
        avatarState.root.traverse(function(o) {
          if (o.geometry) o.geometry.dispose?.();
          if (o.material) {
            if (Array.isArray(o.material)) {
              o.material.forEach(function(m) { m.dispose?.(); });
            } else {
              o.material.dispose?.();
            }
          }
        });
      }

      avatarState.root = null;
      avatarState.mixer = null;
      avatarState.clips = {};
      avatarState.activeAction = null;
      avatarState.ready = false;

      const avatarLoader = new GLTFLoader();
      avatarLoader.load(
        avatarSrc,
        function(gltf) {
          const root = gltf.scene;
          root.name = 'avatar-root';
          root.visible = false;
          // La escala final se decide tras medir el bounding box del avatar
          // y compararlo con el tamaño del mapa (si existe).
          root.scale.setScalar(1.0);

          root.traverse(function(obj) {
            if (!obj.isMesh) return;
            obj.castShadow = false;
            obj.receiveShadow = false;
            obj.frustumCulled = false; // evita desaparecer durante movimientos rápidos
            if (obj.material) {
              const mats = Array.isArray(obj.material) ? obj.material : [obj.material];
              mats.forEach(function(m) {
                m.transparent = m.transparent ?? false;
                m.needsUpdate = true;
              });
            }
          });

          // ── Auto-ajuste para que el avatar sea visible en el mapa ──
          // Problema típico: el origen del rig está en la pelvis → el modelo
          // queda enterrado en el piso; o la escala no coincide con el mapa → invisible.
          const wantsScale = Number.isFinite(options.scale) ? Number(options.scale) : null;
          const wantsYOffset =
            options.yOffset !== undefined && options.yOffset !== null
              ? Number(options.yOffset)
              : null;

          // Medir altura del avatar en unidades del mundo (escala 1.0).
          const avatarBox0 = new THREE.Box3().setFromObject(root);
          const avatarSize0 = avatarBox0.getSize(new THREE.Vector3());
          const avatarHeight0 = Math.max(avatarSize0.y, 1e-3);

          let finalScale = wantsScale;
          if (!Number.isFinite(finalScale) || finalScale <= 0) {
            // Escala automática basada en el tamaño del mapa (si está disponible).
            // Objetivo: ~1.7 unidades de altura (escala humana) dentro del mall.
            // Usamos 1.8% del span mayor X/Z como referencia, clampado a [0.4, 1.8].
            if (mapBounds && !mapBounds.isEmpty()) {
              const mapSize = mapBounds.getSize(new THREE.Vector3());
              const mapSpan = Math.max(mapSize.x, mapSize.z, 1.0);
              const desiredHeight = THREE.MathUtils.clamp(mapSpan * 0.018, 0.4, 1.8);
              finalScale = desiredHeight / avatarHeight0;
            } else {
              finalScale = avatarState.scale || 1.0;
            }
          }

          root.scale.setScalar(finalScale);

          // Recalcular bounding box con la escala aplicada para alinear pies al piso.
          const avatarBox = new THREE.Box3().setFromObject(root);
          const autoYOffset = -avatarBox.min.y; // eleva hasta que min.y quede en 0
          const finalYOffset =
            Number.isFinite(wantsYOffset) ? wantsYOffset : (Number.isFinite(autoYOffset) ? autoYOffset : 0.0);

          avatarState.root = root;
          avatarState.sourceUrl = avatarSrc;
          avatarState.yOffset = finalYOffset;
          avatarState.scale = finalScale;
          avatarState.baseScale = finalScale; // referencia estable para fade de respawn

          avatarState.mixer = new THREE.AnimationMixer(root);
          avatarState.mixer.timeScale = 1.0;

          const clips = gltf.animations || [];
          avatarState.clips = {
            walk: pickClip(clips, ['Walk', 'Caminar', 'Walking', 'walk']),
            idle: pickClip(clips, ['Idle', 'Quieto', 'Stand', 'idle']),
          };

          console.log(
            '[MapViewWeb][Avatar] Clips detectados: ' +
            clips.map(function(c) { return c.name; }).join(', ')
          );

          scene.add(root);
          avatarState.ready = true;

          // Reproducir Idle por defecto para no ver al avatar en T-pose
          playIdle();

          // Si llegó una ruta antes de que el modelo estuviera listo, aplicarla
          if (avatarState.pendingRoute) {
            const pending = avatarState.pendingRoute;
            avatarState.pendingRoute = null;
            startAvatarRoute(pending.waypoints, pending.opts);
          }

          console.log('[MapViewWeb][Avatar] Cargado: ' + avatarSrc);
        },
        undefined,
        function(error) {
          const message = (error && error.message) || String(error);
          console.log('[MapViewWeb][Avatar][ERROR] ' + message);
        },
      );
    }

    function placeAvatarAt(world) {
      if (!avatarState.ready || !avatarState.root) return;
      avatarState.root.position.set(
        world.x,
        (world.y || 0) + avatarState.yOffset,
        world.z,
      );
      avatarState.root.visible = true;
    }

    function faceAvatarTowards(target) {
      if (!avatarState.ready || !avatarState.root) return;
      const pos = avatarState.root.position;

      // Mantener la cabeza nivelada: ignorar diferencia en Y
      const dx = target.x - pos.x;
      const dz = target.z - pos.z;
      if ((dx * dx) + (dz * dz) < 1e-6) return;

      const yaw = Math.atan2(dx, dz);
      avatarState.targetQuat.setFromEuler(new THREE.Euler(0, yaw, 0, 'YXZ'));
    }

    function normalizeWaypoints(raw) {
      if (!Array.isArray(raw)) return [];
      const out = [];
      for (const w of raw) {
        if (!w) continue;
        const x = Number(w.x);
        const y = Number(w.y);
        const z = Number(w.z);
        if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z)) continue;
        out.push(new THREE.Vector3(x, y, z));
      }
      return out;
    }

    function computeSegmentDuration(from, to, speed) {
      const distance = from.distanceTo(to);
      if (distance < 1e-4) return 0.0001;
      return distance / Math.max(speed, 0.01);
    }

    // Encuadra la cámara para ver el recorrido completo (kiosco → tienda).
    // Calcula el bounding box XZ de todos los waypoints y posiciona la cámara
    // a la altura/distancia óptima para que el usuario vea todo el trayecto.
    function fitCameraToRoute(waypoints) {
      if (!waypoints || waypoints.length === 0 || !mapBounds) return;

      let minX = Infinity, maxX = -Infinity;
      let minZ = Infinity, maxZ = -Infinity;
      for (const w of waypoints) {
        if (w.x < minX) minX = w.x;
        if (w.x > maxX) maxX = w.x;
        if (w.z < minZ) minZ = w.z;
        if (w.z > maxZ) maxZ = w.z;
      }

      const cx = (minX + maxX) * 0.5;
      const cz = (minZ + maxZ) * 0.5;
      const spanX = Math.max(maxX - minX, 1.5);
      const spanZ = Math.max(maxZ - minZ, 1.5);
      const span  = Math.max(spanX, spanZ);

      // Distancia de cámara: suficiente para ver el span con margen (factor 0.6),
      // siempre dentro de los límites permitidos por el mapa.
      const dist = THREE.MathUtils.clamp(span * 0.60, minDistance, maxDistance * 0.92);

      const nextTarget = new THREE.Vector3(cx, mapCenter.y, cz);
      // Posición: directamente sobre el centro, inclinada ~14° hacia adelante
      const nextCamPos = new THREE.Vector3(cx, mapCenter.y + dist, cz + dist * 0.24);

      startCameraTransition(nextCamPos, nextTarget);

      console.log(
        '[MapViewWeb][Camera] fitRoute: span=' + span.toFixed(2)
        + ' dist=' + dist.toFixed(2)
        + ' cx=' + cx.toFixed(2) + ' cz=' + cz.toFixed(2)
      );
    }

    function startAvatarRoute(rawWaypoints, opts) {
      const options = opts || {};
      // Las coordenadas vienen en world-space de Three.js (el editor las captura
      // via raycaster con la calibración ya aplicada al modelo; NodeWorldMapping
      // hace el swap correcto x/y/z_height→x/y/z). NO aplicar fitWaypointsToMap:
      // esa heurística reescala y recentra coordenadas que ya son correctas,
      // produciendo doble transformación y desalineación del avatar.
      const waypoints = normalizeWaypoints(rawWaypoints);

      if (waypoints.length === 0) {
        console.log('[MapViewWeb][Avatar] Ruta vacía');
        stopAvatarRoute();
        return;
      }

      // Si el avatar aún no está listo, NO arrancamos el trail ni la cámara:
      // dejarlo así produce un intro huérfano (sin onIntroDone) que después
      // condena la animación a quedarse en idle. Guardamos la ruta cruda y
      // dejamos que el callback de loadAvatar reintente cuando todo esté
      // listo, ahí sí arrancamos trail + cámara + walk en bloque.
      if (!avatarState.ready || !avatarState.root) {
        avatarState.pendingRoute = { waypoints: rawWaypoints, opts: options };
        console.log('[MapViewWeb][Avatar] Ruta en cola — esperando modelo');
        return;
      }

      console.log(
        '[MapViewWeb][Avatar][Route] wp=' + waypoints.length
        + ' dest=(' + waypoints[waypoints.length - 1].x.toFixed(2)
        + ', ' + waypoints[waypoints.length - 1].y.toFixed(2)
        + ', ' + waypoints[waypoints.length - 1].z.toFixed(2) + ')'
      );

      // Velocidad: si el caller no la especifica, se calcula como el 8% del span
      // del mapa por segundo (≈ cruzar el mapa en ~12 s), proporcional a la escala
      // del GLB. Esto evita que un avatar parezca estático en mapas grandes.
      if (!Number.isFinite(options.speed) && mapBounds) {
        const sz = mapBounds.getSize(new THREE.Vector3());
        options.speed = Math.max(sz.x, sz.z, 1.0) * 0.08;
      }
      avatarState.speed = Number.isFinite(options.speed) ? options.speed : 1.2;
      avatarState.route = waypoints;
      avatarState.segmentIndex = 0;
      avatarState.segmentProgress = 0.0;
      avatarState.arrivalNotified = false;
      avatarState.respawning = false;
      avatarState.respawnT = 0.0;

      // Trail + cámara + walk SOLO cuando el avatar está listo: así el intro
      // siempre va emparejado con un onIntroDone válido.
      try {
        spawnPathTrail(waypoints);
      } catch (trailErr) {
        console.log('[MapViewWeb][Trail] Error al crear trail: ' + String(trailErr));
      }
      if (options.autoCenter !== false) {
        try { fitCameraToRoute(waypoints); } catch (_) {}
      }

      // Colocar avatar en el primer waypoint
      placeAvatarAt(waypoints[0]);

      if (waypoints.length === 1) {
        // Ruta de un solo punto: solo posicionamos y entramos en idle
        avatarState.isWalking = false;
        playIdle();
        console.log('[MapViewWeb][Avatar] Ruta de 1 nodo — idle');
        return;
      }

      avatarState.segmentDuration = computeSegmentDuration(
        waypoints[0],
        waypoints[1],
        avatarState.speed,
      );

      // Rotación inicial instantánea para no verlo girar 180° al arrancar
      faceAvatarTowards(waypoints[1]);
      if (avatarState.root && avatarState.targetQuat) {
        avatarState.root.quaternion.copy(avatarState.targetQuat);
      }

      // Caminar SOLO después de que la ruta termine de dibujarse en el piso.
      // Mientras tanto el avatar queda quieto en el primer waypoint (idle).
      avatarState.isWalking = false;
      playIdle();
      const startWalking = function() {
        avatarState.isWalking = true;
        playWalk();
        const walkClipName = (avatarState.clips.walk && avatarState.clips.walk.name) || '<none>';
        console.log('[MapViewWeb][Avatar] intro→walk OK (clip=' + walkClipName + ')');
      };
      // Si por algún motivo el trail no se construyó (caso defensivo), no
      // dejar al avatar atascado en idle: arranca a caminar en el siguiente
      // tick.
      if (!trailState.lineMat) {
        console.log('[MapViewWeb][Avatar] Trail ausente → caminando sin intro');
        startWalking();
      } else {
        trailState.onIntroDone = startWalking;
      }
      console.log(
        '[MapViewWeb][Avatar] Ruta iniciada — ' + waypoints.length + ' waypoints'
      );
    }

    function stopAvatarRoute() {
      avatarState.route = [];
      avatarState.segmentIndex = 0;
      avatarState.segmentProgress = 0.0;
      avatarState.isWalking = false;
      avatarState.arrivalNotified = false;
      avatarState.respawning = false;
      avatarState.respawnT = 0.0;
      avatarState.respawnTeleported = false;
      // Si quedó a media escala por un respawn interrumpido, restaurar.
      if (avatarState.root && avatarState.baseScale) {
        avatarState.root.scale.setScalar(avatarState.baseScale);
      }
      clearPathTrail();
      clearWaypointMarkers(); // limpia cualquier esfera de debug residual
      if (avatarState.ready) {
        playIdle();
      }
      console.log('[MapViewWeb][Avatar] Ruta detenida');
    }

    function setAvatarAtWorld(x, y, z) {
      const px = Number(x);
      const py = Number(y);
      const pz = Number(z);
      if (!Number.isFinite(px) || !Number.isFinite(py) || !Number.isFinite(pz)) return;
      placeAvatarAt({ x: px, y: py, z: pz });
    }

    function hideAvatar() {
      if (avatarState.root) {
        avatarState.root.visible = false;
      }
      clearPathTrail();
      stopAvatarRoute();
    }

    function updateAvatarTick(dt) {
      if (avatarState.mixer) {
        avatarState.mixer.update(dt);
      }

      // ── Animar trail de pasos ────────────────────────────────────────
      if (trailState.lineMat) {
        trailState.time += dt;
        // Marching-ants: desplazar los guiones en la dirección del avance
        trailState.lineMat.dashOffset -= dt * 0.75;

        if (!trailState.introComplete) {
          // ── Fase de intro: la ruta se "dibuja" en el piso ──
          trailState.introProgress = Math.min(
            1.0,
            trailState.introProgress + dt / Math.max(trailState.introDuration, 0.001),
          );
          const p = trailState.introProgress;
          // Ease-out cubic para que el dibujado se sienta enérgico al inicio
          const eased = 1 - Math.pow(1 - p, 3);

          // Crecer la línea desde el origen hasta el destino
          if (trailState.line && trailState.line.geometry && trailState.totalLineVerts > 0) {
            const visibleVerts = Math.max(
              2,
              Math.floor(trailState.totalLineVerts * eased),
            );
            trailState.line.geometry.setDrawRange(0, visibleVerts);
          }
          // Opacidad de la línea creciendo de 0 a 0.88
          trailState.lineMat.opacity = 0.88 * eased;

          // Revelar dots conforme el "frente" de dibujado los alcanza
          for (let i = 0; i < trailState.dots.length; i++) {
            const dot = trailState.dots[i];
            const key = trailState.dotKeys[i] || 0;
            const local = THREE.MathUtils.clamp((eased - key) / 0.08, 0, 1);
            dot.material.opacity = 0.60 * local;
          }

          // Destino: aparece en el último tramo del intro
          const destReveal = THREE.MathUtils.clamp((eased - 0.85) / 0.15, 0, 1);
          if (trailState.destDot) {
            trailState.destDot.material.opacity = 0.95 * destReveal;
          }
          if (trailState.destHalo) {
            trailState.destHalo.material.opacity = 0.55 * destReveal;
          }

          if (p >= 1.0) {
            trailState.introComplete = true;
            // Asegurar geometría completa al cerrar la fase
            if (trailState.line && trailState.line.geometry && trailState.totalLineVerts > 0) {
              trailState.line.geometry.setDrawRange(0, trailState.totalLineVerts);
            }
            const cb = trailState.onIntroDone;
            trailState.onIntroDone = null;
            if (typeof cb === 'function') {
              try { cb(); } catch (e) { console.log('[MapViewWeb][Trail] onIntroDone error: ' + String(e)); }
            }
          }
        } else {
          // ── Post-intro: pulso suave + marching-ants ──
          // Pulso suave de la línea (0.62 → 0.88 → 0.62, período ~2.5 s)
          trailState.lineMat.opacity = 0.62 + 0.26 * Math.sin(trailState.time * 2.5);
          // Pulso del marcador de destino (más rápido, más llamativo)
          if (trailState.destDot) {
            trailState.destDot.material.opacity =
              0.68 + 0.27 * Math.abs(Math.sin(trailState.time * 4.2));
          }
        }
        // Watchdog: si el intro ya terminó pero el callback sigue pendiente
        // (tab en background, dt clampado, etc.), forzamos su ejecución para
        // no dejar al avatar atascado en idle.
        if (trailState.introComplete && typeof trailState.onIntroDone === 'function') {
          const cb2 = trailState.onIntroDone;
          trailState.onIntroDone = null;
          console.log('[MapViewWeb][Trail] Watchdog: forzando intro→walk');
          try { cb2(); } catch (e) { console.log('[MapViewWeb][Trail] Watchdog error: ' + String(e)); }
        }
      }

      if (!avatarState.ready || !avatarState.root) return;

      // Rotación suave hacia el próximo waypoint
      if (avatarState.targetQuat) {
        avatarState.root.quaternion.slerp(avatarState.targetQuat, 0.18);
      }

      if (!avatarState.isWalking) return;
      const route = avatarState.route;
      if (!route || route.length < 2) return;

      // ── Fase de respawn: shrink → teleport → grow, en vez de teleport
      // instantáneo al cerrar el loop. Evita el flash visual del salto.
      if (avatarState.respawning) {
        avatarState.respawnT += dt / Math.max(avatarState.respawnDuration || 0.35, 0.0001);
        const rt = Math.min(1.0, avatarState.respawnT);
        let scaleFactor;
        if (rt < 0.5) {
          scaleFactor = 1.0 - rt * 2.0; // 1 → 0
        } else {
          if (!avatarState.respawnTeleported) {
            avatarState.respawnTeleported = true;
            avatarState.segmentIndex = 0;
            avatarState.segmentProgress = 0;
            placeAvatarAt(route[0]);
            faceAvatarTowards(route[1]);
            if (avatarState.root && avatarState.targetQuat) {
              avatarState.root.quaternion.copy(avatarState.targetQuat);
            }
            avatarState.segmentDuration = computeSegmentDuration(
              route[0],
              route[1],
              avatarState.speed,
            );
          }
          scaleFactor = (rt - 0.5) * 2.0; // 0 → 1
        }
        const base = avatarState.baseScale || avatarState.scale || 1.0;
        avatarState.root.scale.setScalar(base * scaleFactor);
        if (rt >= 1.0) {
          avatarState.respawning = false;
          avatarState.respawnTeleported = false;
          avatarState.root.scale.setScalar(base);
        }
        return; // mientras respawnea, no avanzamos el segmento
      }

      const i = avatarState.segmentIndex;
      if (i >= route.length - 1) return;

      const from = route[i];
      const to = route[i + 1];

      avatarState.segmentProgress += dt / Math.max(avatarState.segmentDuration, 0.0001);
      let t = avatarState.segmentProgress;

      if (t >= 1.0) {
        // Completamos este tramo: avanzar al siguiente
        avatarState.segmentIndex += 1;
        if (avatarState.segmentIndex >= route.length - 1) {
          // Llegada al destino: arrancar fase de respawn (shrink+teleport+grow)
          // en lugar de teleport instantáneo. La animación se repite hasta
          // que el usuario cambie de mapa/sección/tienda (stopAvatarRoute).
          if (!avatarState.arrivalNotified) {
            notifyFlutter('onAvatarArrived', { waypoints: route.length });
            avatarState.arrivalNotified = true;
          }
          avatarState.respawning = true;
          avatarState.respawnT = 0.0;
          avatarState.respawnDuration = 0.35;
          avatarState.respawnTeleported = false;
          // El clip "Walk" sigue corriendo durante el respawn — no llamar
          // playWalk() aquí evita el reset/T-pose de 1 frame.
          console.log('[MapViewWeb][Avatar] Llegada a destino → respawn (loop)');
          return;
        }
        avatarState.segmentProgress = 0;
        const nextFrom = route[avatarState.segmentIndex];
        const nextTo = route[avatarState.segmentIndex + 1];
        avatarState.segmentDuration = computeSegmentDuration(
          nextFrom,
          nextTo,
          avatarState.speed,
        );
        faceAvatarTowards(nextTo);
        t = 0;
      }

      // Interpolar posición con lerp dentro del segmento
      const pos = avatarState.root.position;
      pos.x = from.x + (to.x - from.x) * t;
      pos.y = (from.y + (to.y - from.y) * t) + avatarState.yOffset;
      pos.z = from.z + (to.z - from.z) * t;
    }

    window.updateCamera = updateCamera;
    window.resetCamera = resetCamera;
    window.centerTopView = centerTopView;
    window.centerOnMapPoint = centerOnMapPoint;
    window.loadAvatar = loadAvatar;
    window.startAvatarRoute = startAvatarRoute;
    window.stopAvatarRoute = stopAvatarRoute;
    window.setAvatarAtWorld = setAvatarAtWorld;
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

        // Calibración persistida (misma idea que el editor 3D).
        loadStoredCalibration();
        syncCalibUI();
        applyMapCalibration();

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

      // Clamp delta para evitar saltos si la pestaña estuvo en background
      const dt = Math.min(clock.getDelta(), 0.1);

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

      // Actualiza mixer, rotación y movimiento del avatar en el mismo tick
      updateAvatarTick(dt);

      controls.update();
      renderer.render(scene, camera);
    }
    animate();

    // En Flutter web, ejecutamos comandos que vienen embebidos en el HTML.
    try {
      const boot = window.__flutterBootstrapCommands;
      if (boot && typeof boot === 'string' && boot.trim().length > 0) {
        console.log('[MapViewWeb][WebBootstrap] Ejecutando comandos');
        // eslint-disable-next-line no-eval
        eval(boot);
      }
    } catch (e) {
      console.log('[MapViewWeb][WebBootstrap][ERROR]', e && (e.stack || e.message || e));
    }
  </script>
</body>
</html>
''';

  Future<void> _reloadHtmlIfPossible() async {
    final c = _webViewController;
    if (c == null) return;
    await c.loadData(
      data: _initialHtml,
      mimeType: 'text/html',
      encoding: 'utf-8',
      baseUrl: WebUri('https://localhost'),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Ciclo de vida del widget
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void didUpdateWidget(covariant MapViewWeb oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Si cambió el .glb del mapa (p.ej. el usuario cambió de piso), recargamos
    // el WebView. Así mantenemos la misma instancia —y por tanto el
    // GlobalKey<MapViewWebState>— sin necesidad de ValueKey externo.
    if (oldWidget.modelUrl != widget.modelUrl && _webViewController != null) {
      debugPrint(
        '[MapViewWeb] modelUrl cambió → recargando HTML con '
        '${widget.modelUrl}',
      );
      if (mounted) {
        setState(() {
          _isLoading = true;
          _hasError = false;
        });
      }
      // Reinyecta el HTML (el getter ya resuelve el nuevo widget.modelUrl).
      _webViewController!.loadData(
        data: _initialHtml,
        mimeType: 'text/html',
        encoding: 'utf-8',
        baseUrl: WebUri('https://localhost'),
      );
    }

    // Si cambió el avatar (normalmente no pasa), pedimos recarga al JS.
    if (oldWidget.avatarUrl != widget.avatarUrl &&
        widget.avatarUrl != null &&
        widget.avatarUrl!.isNotEmpty) {
      loadAvatar(widget.avatarUrl!);
    }
  }

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _postBridge.register(
        instanceId: _instanceId,
        onReady: () {
          _postBridgeReady = true;
          debugPrint('[MapViewWeb][PostBridge] iframe lista ($_instanceId)');
        },
      );
    }
  }

  @override
  void dispose() {
    _webLoadPoller?.cancel();
    _webViewController = null;
    if (kIsWeb) {
      _postBridge.dispose();
    }
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

  Future<dynamic> _evalJs(String source) async {
    final c = _webViewController;
    if (c == null) return null;
    // `evaluateJavascript` es lo único estable en este proyecto actualmente.
    // Añadimos un handshake (`window.__bridgeReady`) para no llamar antes de tiempo.
    return await c.evaluateJavascript(source: source);
  }

  Future<bool> _waitBridgeReady({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final ready = await _evalJs("window.__bridgeReady === true ? 'yes' : 'no';");
      if (ready == 'yes') return true;
      await Future.delayed(const Duration(milliseconds: 120));
    }
    return false;
  }

  /// Web-only: empuja un comando a la iframe vía postMessage.
  /// Devuelve `true` si se entregó por postMessage; `false` si aún no
  /// hay handshake con la iframe (el caller debe usar el bootstrap-reload
  /// como fallback de la primera vez).
  bool _postCommandToIframe(Map<String, dynamic> cmd) {
    if (!kIsWeb) return false;
    if (!_postBridgeReady) return false;
    final payload = jsonEncode(cmd);
    return _postBridge.tryPostCommand(payload);
  }

  /// Espera (con un pequeño timeout) a que la iframe complete el
  /// handshake `mapview-ready`. Devuelve `true` si ya está lista.
  Future<bool> _waitPostBridge({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (!kIsWeb) return false;
    if (_postBridgeReady) return true;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_postBridgeReady) return true;
      await Future.delayed(const Duration(milliseconds: 80));
    }
    return _postBridgeReady;
  }

  /// Sincroniza la calibración del mapa con los valores usados en el editor.
  /// Debe llamarse tras cargar el mapa (onMapLoaded) y antes de startAvatarRoute.
  /// Los valores deben coincidir exactamente con los que se usaron en el editor
  /// cuando se capturaron los nodos (scale, ox, oy, oz, rotY).
  Future<void> setMapCalibration({
    double scale = 1.0,
    double ox = 0.0,
    double oy = 0.0,
    double oz = 0.0,
    double rotY = 0.0,
  }) async {
    if (_webViewController == null) return;
    await _waitBridgeReady();
    final calib = jsonEncode({
      'scale': scale,
      'ox': ox,
      'oy': oy,
      'oz': oz,
      'rotY': rotY,
    });
    await _evalJs("window.setMapCalibration?.($calib);");
    debugPrint('[MapViewWeb][Flutter→Web] setMapCalibration(scale=$scale, ox=$ox, oy=$oy, oz=$oz, rotY=$rotY)');
  }

  /// Mueve la cámara suavemente hacia un punto y órbita específicos.
  /// [target] → Coordenadas del objetivo, ej: "0m 1m 0m"
  /// [orbit]  → Órbita de cámara, ej: "45deg 55deg 5m"
  Future<void> updateCamera(String target, String orbit) async {
    if (_webViewController == null) return;
    await _waitBridgeReady();
    await _evalJs(
      "window.updateCamera?.('${target.replaceAll("'", "\\'")}', '${orbit.replaceAll("'", "\\'")}');",
    );
    debugPrint('[MapViewWeb][Flutter→Web] updateCamera($target, $orbit)');
  }

  /// Resetea la cámara a la posición por defecto.
  Future<void> resetCamera() async {
    if (_webViewController == null) return;
    await _waitBridgeReady();
    await _evalJs("window.resetCamera?.();");
  }

  /// Centra el mapa con una vista superior y cercana.
  Future<void> centerTopView() async {
    if (_webViewController == null) return;
    await _waitBridgeReady();
    await _evalJs("window.centerTopView?.();");
    debugPrint('[MapViewWeb][Flutter→Web] centerTopView()');
  }

  /// Centra la cámara sobre un punto de mundo 3D (coordenadas three.js).
  Future<void> centerOnMapPoint(double x, double y, double z) async {
    if (_webViewController == null) return;
    await _waitBridgeReady();
    final result = await _evalJs("(function(){"
        "try{"
        "if(!window.centerOnMapPoint){console.log('[MapViewWeb][Bridge] centerOnMapPoint undefined'); return 'missing';}"
        "window.centerOnMapPoint($x,$y,$z);"
        "return 'ok';"
        "}catch(e){"
        "console.log('[MapViewWeb][Bridge] centerOnMapPoint error', String(e));"
        "return 'error';"
        "}"
        "})()");
    debugPrint('[MapViewWeb][Flutter→Web] centerOnMapPoint($x, $y, $z) → $result');
  }

  /// Carga un modelo de avatar .glb y lo añade DENTRO de la escena three.js.
  /// Debe ejecutarse una sola vez; cambia entre mapas sin recargar.
  /// [opts] admite: `scale` (double), `yOffset` (double).
  Future<void> loadAvatar(String avatarSrc, {Map<String, dynamic>? opts}) async {
    if (_webViewController == null) return;
    await _waitBridgeReady();
    final optsJson = jsonEncode(opts ?? const <String, dynamic>{});
    await _evalJs("window.loadAvatar?.(${jsonEncode(avatarSrc)}, $optsJson);");
    debugPrint('[MapViewWeb][Flutter→Web] loadAvatar($avatarSrc)');
  }

  /// Inicia la animación del avatar sobre la ruta indicada.
  ///
  /// [waypoints] debe ser una lista de mapas `{x, y, z}` en coordenadas del
  /// mundo three.js (ver `NodeWorldMapping`).
  /// [speed] está en unidades/segundo del mundo.
  Future<void> startAvatarRoute(
    List<Map<String, dynamic>> waypoints, {
    double speed = 1.2,
  }) async {
    if (_webViewController == null) return;
    final payload = jsonEncode(waypoints);
    final opts = jsonEncode({'speed': speed});

    // Flutter Web: evitamos recargar el HTML — eso es lo que producía el
    // flash negro al seleccionar tienda. Empujamos el comando a la iframe
    // por postMessage; sólo si la iframe aún no hizo el handshake caemos
    // al bootstrap-reload (típicamente sólo en la primera invocación).
    if (kIsWeb) {
      await _waitPostBridge(timeout: const Duration(seconds: 4));
      final ok = _postCommandToIframe({
        'cmd': 'startAvatarRoute',
        'payload': waypoints,
        'opts': {'speed': speed},
      });
      if (ok) {
        debugPrint('[MapViewWeb][Flutter→Web][WEB] startAvatarRoute postMessage (${waypoints.length} wp)');
        return;
      }
      _webCommandBootstrap = "window.startAvatarRoute?.($payload,$opts);";
      await _reloadHtmlIfPossible();
      debugPrint('[MapViewWeb][Flutter→Web][WEB] startAvatarRoute bootstrap (${waypoints.length} wp)');
      return;
    }

    await _waitBridgeReady();
    final result = await _evalJs("(function(){"
        "try{"
        "if(!window.startAvatarRoute){console.log('[MapViewWeb][Bridge] startAvatarRoute undefined'); return 'missing';}"
        "window.startAvatarRoute($payload,$opts);"
        "return 'ok';"
        "}catch(e){"
        "console.log('[MapViewWeb][Bridge] startAvatarRoute error', String(e));"
        "return 'error';"
        "}"
        "})()");
    debugPrint('[MapViewWeb][Flutter→Web] startAvatarRoute(${waypoints.length} wp) → $result');
  }

  /// Detiene el recorrido en curso y deja al avatar en animación idle.
  Future<void> stopAvatarRoute() async {
    if (_webViewController == null) return;
    if (kIsWeb && _postCommandToIframe({'cmd': 'stopAvatarRoute'})) return;
    await _waitBridgeReady();
    await _evalJs("window.stopAvatarRoute?.();");
  }

  /// Coloca el avatar instantáneamente en una coordenada de mundo.
  Future<void> setAvatarAtWorld(double x, double y, double z) async {
    if (_webViewController == null) return;
    if (kIsWeb &&
        _postCommandToIframe({
          'cmd': 'setAvatarAtWorld',
          'x': x,
          'y': y,
          'z': z,
        })) {
      return;
    }
    await _waitBridgeReady();
    await _evalJs("window.setAvatarAtWorld?.($x, $y, $z);");
  }

  /// Oculta el avatar de la escena (p.ej. al cambiar de piso sin destino).
  Future<void> hideAvatar() async {
    if (_webViewController == null) return;
    if (kIsWeb && _postCommandToIframe({'cmd': 'hideAvatar'})) return;
    await _waitBridgeReady();
    await _evalJs("window.hideAvatar?.();");
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

              controller.addJavaScriptHandler(
                handlerName: 'onAvatarArrived',
                callback: (args) {
                  debugPrint('[MapViewWeb][Web→Flutter] Avatar llegó: $args');
                  widget.onAvatarArrived?.call();
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