import 'package:flutter/foundation.dart';

/// Controlador del personaje 3D (avatar). Modela su ciclo de animación
/// (caminando / llegado) **sin tocar la ruta dibujada**.
///
/// El motor 3D corre el clip de "walk" en loop hasta que el orquestador
/// (`MapStateManager`) decide detenerlo. La señal `notifyArrived` se dispara
/// la primera vez que el avatar alcanza el último waypoint; veces sucesivas
/// del loop NO re-emiten para evitar transiciones de estado redundantes.
class CharacterAnimatorController extends ChangeNotifier {
  bool _isWalking = false;
  bool _hasArrived = false;

  bool get isWalking => _isWalking;
  bool get hasArrived => _hasArrived;

  /// Marca el inicio del recorrido. Lo invoca el [MapStateManager] cuando
  /// la ruta ya está dibujada y se confirma `onPathRendered`.
  void beginWalk() {
    _isWalking = true;
    _hasArrived = false;
    notifyListeners();
  }

  /// Se invoca cuando el motor 3D notifica `onAvatarArrived`. Importante:
  /// **no** dispara ninguna limpieza de la ruta — la persistencia del trail
  /// está garantizada por el aislamiento entre este controlador y
  /// [PathRendererController].
  void notifyArrived() {
    if (_hasArrived) return;
    _hasArrived = true;
    // Mantenemos isWalking=true porque el clip sigue corriendo en loop.
    notifyListeners();
  }

  /// Detiene la animación del personaje (cambio de vista / nueva tienda).
  void stop() {
    if (!_isWalking && !_hasArrived) return;
    _isWalking = false;
    _hasArrived = false;
    notifyListeners();
  }
}
