import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/store.dart';
import '../../../services/avatar_navigation_service.dart';
import '../controllers/character_animator_controller.dart';
import '../controllers/path_renderer_controller.dart';
import '../services/store_selection_service.dart';
import 'map_view_state.dart';

/// Callback que delega al consumidor (MapScreen) el cálculo de la ruta y el
/// envío de los waypoints al motor 3D. Devuelve `true` si el dispatch arrancó
/// correctamente; `false` si por algún motivo (kiosko sin nodo, navegación no
/// lista, ruta vacía, etc.) no se pudo iniciar — en ese caso el manager
/// vuelve a `Idle`.
typedef RouteDispatcher = Future<bool> Function(Store store);

/// Callback que ordena al motor 3D detener tanto el avatar como el trail.
/// Es el "lado opuesto" del [RouteDispatcher]: el state manager no conoce
/// el WebView, sólo sabe pedir "para todo".
typedef RouteStopper = Future<void> Function();

/// Callback que reproduce un segmento subsiguiente de una ruta cross-floor.
/// Lo invoca el manager tras la pausa de transición; el consumidor (MapScreen)
/// debe: (1) cambiar `_selectedFloor` al piso del segmento, (2) colocar al
/// avatar en el nodo de entrada (primer waypoint), (3) llamar a
/// `startAvatarRoute(segment.waypoints)`. Devuelve `true` si la animación
/// arrancó.
typedef NextSegmentDispatcher = Future<bool> Function(FloorSegment segment);

/// Orquestador de la vista del mapa. Es la **única** entidad autorizada para
/// transicionar entre estados y para invocar `clearPath()`/`stop()` de los
/// controladores. Lo demás (UI, JS bridge) sólo lo escucha o lo alimenta.
class MapStateManager extends ChangeNotifier {
  final StoreSelectionService selectionService;
  final PathRendererController pathRenderer;
  final CharacterAnimatorController characterAnimator;

  /// Inyectado por [MapScreen]. El manager no conoce el grafo, los kioscos
  /// ni el WebView; sólo le pide al consumidor "dispatch" cuando llega una
  /// nueva tienda.
  RouteDispatcher? routeDispatcher;

  /// Inyectado por [MapScreen]. Se invoca dentro de `_resetToIdle` para
  /// detener efectivamente el avatar y borrar el trail en el motor 3D.
  /// Sin él, el state manager actualizaría sus flags pero el JS seguiría
  /// corriendo el loop de caminar.
  RouteStopper? routeStopper;

  /// Inyectado por [MapScreen]. Se invoca al terminar un segmento intermedio
  /// de una ruta cross-floor para reproducir el siguiente. Si es `null`, las
  /// rutas multi-piso se comportan como rutas de un solo piso (compatibilidad).
  NextSegmentDispatcher? nextSegmentDispatcher;

  /// Duración de la pausa visual entre dos segmentos cross-floor. Coincide con
  /// el tiempo conceptual de "subir/bajar" la escalera o ascensor.
  Duration transitionPause = const Duration(seconds: 2);

  StreamSubscription<Store>? _selectionSub;
  MapViewState _state = const MapIdleState();

  // Estado de la ruta cross-floor en curso.
  AvatarRoute? _activeRoute;
  int _currentSegmentIndex = 0;

  MapStateManager({
    required this.selectionService,
    required this.pathRenderer,
    required this.characterAnimator,
    this.routeDispatcher,
    this.routeStopper,
    this.nextSegmentDispatcher,
  }) {
    _selectionSub =
        selectionService.onStoreSelected.listen(_handleStoreSelected);
  }

  MapViewState get state => _state;

  /// Tienda activa según el último estado no `Idle`. Útil para reintentos
  /// (ej. cuando el usuario cambia de piso y queremos relanzar la ruta).
  Store? get activeStore => switch (_state) {
        MapPathRenderingState s => s.store,
        MapCharacterWalkingState s => s.store,
        MapTransitioningState s => s.store,
        MapArrivedState s => s.store,
        MapIdleState _ => null,
      };

  /// Llamado por [MapScreen] inmediatamente después de calcular la ruta y
  /// antes de iniciar la animación del primer segmento. El manager guarda la
  /// ruta para encadenar los segmentos siguientes cuando llegue cada
  /// `notifyCharacterArrived`.
  void registerActiveRoute(AvatarRoute route) {
    _activeRoute = route;
    _currentSegmentIndex = 0;
  }

  void _setState(MapViewState next) {
    if (identical(_state, next)) return;
    _state = next;
    notifyListeners();
  }

  Future<void> _handleStoreSelected(Store store) async {
    // 1. Nueva selección → SIEMPRE limpiamos la ruta previa antes de empezar.
    //    Es el ÚNICO lugar (junto a onViewChanged) donde se autoriza.
    //    Importante: también pedimos al motor 3D que pare el loop anterior;
    //    si no lo hacemos, una nueva ruta arrancaría sobre la animación
    //    previa y se acumularían trails residuales.
    _activeRoute = null;
    _currentSegmentIndex = 0;
    await routeStopper?.call();
    pathRenderer.clearPath();
    characterAnimator.stop();

    pathRenderer.beginRender(store);
    _setState(MapPathRenderingState(store));

    final dispatcher = routeDispatcher;
    if (dispatcher == null) {
      debugPrint('[MapStateManager] routeDispatcher no inyectado');
      _resetToIdle();
      return;
    }

    final ok = await dispatcher(store);
    if (!ok) {
      debugPrint('[MapStateManager] dispatch falló para "${store.name}"');
      _resetToIdle();
    }
    // Si ok=true: esperamos a que el WebView emita `onPathRendered` para
    // transicionar a CharacterWalking (vía notifyPathRendered).
  }

  /// Notificación desde el motor 3D: la ruta terminó de dibujarse en el piso.
  /// A partir de aquí el personaje puede arrancar la animación de caminar.
  void notifyPathRendered({int? stepCount}) {
    final current = _state;
    if (current is! MapPathRenderingState) {
      debugPrint(
        '[MapStateManager] onPathRendered ignorado en estado ${current.runtimeType}',
      );
      return;
    }
    pathRenderer.completeRender(stepCount: stepCount);
    characterAnimator.beginWalk();
    _setState(MapCharacterWalkingState(current.store));
  }

  /// Notificación desde el motor 3D: el avatar alcanzó el destino la primera
  /// vez. La ruta dibujada NO se toca (el loop de caminar puede continuar).
  ///
  /// Si la ruta activa tiene más segmentos pendientes (cross-floor), entra en
  /// `MapTransitioningState`, espera la pausa de transición, cambia de piso y
  /// reproduce el siguiente segmento. Si era el último, termina en
  /// `MapArrivedState`.
  void notifyCharacterArrived() {
    final current = _state;
    if (current is! MapCharacterWalkingState) {
      debugPrint(
        '[MapStateManager] onAvatarArrived ignorado en estado ${current.runtimeType}',
      );
      return;
    }
    characterAnimator.notifyArrived();

    final route = _activeRoute;
    final nextIndex = _currentSegmentIndex + 1;
    final hasNext = route != null && nextIndex < route.segments.length;

    if (!hasNext || nextSegmentDispatcher == null) {
      _setState(MapArrivedState(current.store));
      return;
    }

    // Hay siguiente segmento → pausa de transición + cambio de piso.
    final fromSeg = route.segments[_currentSegmentIndex];
    final nextSeg = route.segments[nextIndex];
    _setState(MapTransitioningState(
      store: current.store,
      fromFloor: fromSeg.floorLevel,
      toFloor: nextSeg.floorLevel,
      completedSegmentIndex: _currentSegmentIndex,
    ));
    // ignore: discarded_futures
    _runTransitionAndContinue(current.store, nextSeg, nextIndex);
  }

  Future<void> _runTransitionAndContinue(
    Store store,
    FloorSegment nextSeg,
    int nextIndex,
  ) async {
    await Future<void>.delayed(transitionPause);

    // Si en medio de la pausa el usuario cambió de tienda o salió de la
    // pantalla, abortar: ya no estamos en transición.
    if (_state is! MapTransitioningState) return;

    final dispatcher = nextSegmentDispatcher;
    if (dispatcher == null) {
      _setState(MapArrivedState(store));
      return;
    }

    // El consumidor cambia de piso, coloca al avatar en el nodo de entrada y
    // arranca la animación del segmento. Mientras tanto, el manager limpia el
    // trail del piso anterior para no acumular residuos.
    pathRenderer.clearPath();

    final ok = await dispatcher(nextSeg);
    if (!ok) {
      debugPrint(
        '[MapStateManager] nextSegmentDispatcher falló en segmento $nextIndex',
      );
      _resetToIdle();
      return;
    }

    _currentSegmentIndex = nextIndex;
    pathRenderer.beginRender(store);
    _setState(MapPathRenderingState(store));
  }

  /// Llamar al cambiar de pantalla (dispose de MapScreen) o cuando el
  /// usuario sale del módulo del mapa. Limpia ruta y personaje.
  void onViewChanged() {
    if (_state is MapIdleState && !pathRenderer.hasPath) return;
    _resetToIdle();
  }

  void _resetToIdle() {
    // 1. Detener el motor 3D PRIMERO (avatar + trail) — fire-and-forget
    //    para no bloquear el dispose de MapScreen.
    final stopper = routeStopper;
    if (stopper != null) {
      // ignore: discarded_futures
      stopper();
    }
    // 2. Sincronizar flags internos.
    _activeRoute = null;
    _currentSegmentIndex = 0;
    pathRenderer.clearPath();
    characterAnimator.stop();
    _setState(const MapIdleState());
  }

  @override
  void dispose() {
    _selectionSub?.cancel();
    pathRenderer.dispose();
    characterAnimator.dispose();
    super.dispose();
  }
}
