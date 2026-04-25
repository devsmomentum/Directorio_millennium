import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/store.dart';
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

  StreamSubscription<Store>? _selectionSub;
  MapViewState _state = const MapIdleState();

  MapStateManager({
    required this.selectionService,
    required this.pathRenderer,
    required this.characterAnimator,
    this.routeDispatcher,
    this.routeStopper,
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
        MapArrivedState s => s.store,
        MapIdleState _ => null,
      };

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
  void notifyCharacterArrived() {
    final current = _state;
    if (current is! MapCharacterWalkingState) {
      debugPrint(
        '[MapStateManager] onAvatarArrived ignorado en estado ${current.runtimeType}',
      );
      return;
    }
    characterAnimator.notifyArrived();
    _setState(MapArrivedState(current.store));
    // ¡IMPORTANTE! No invocamos pathRenderer.clearPath() aquí.
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
