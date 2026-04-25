import 'package:flutter/foundation.dart';

import '../../../models/store.dart';

/// Controlador de la **ruta de pasos** dibujada en el piso del mapa.
///
/// Responsabilidad única: gestionar el ciclo de vida del trail visual
/// (idle → renderizando → dibujado). NUNCA se acopla al ciclo del personaje
/// — eso pertenece a [CharacterAnimatorController]. El único método que
/// destruye la ruta es [clearPath] y solo el [MapStateManager] está
/// autorizado a invocarlo, vinculado a "cambio de vista" o "nueva selección
/// de tienda" (jamás al `AnimationStatus.completed` del personaje).
class PathRendererController extends ChangeNotifier {
  bool _isRendering = false;
  bool _hasPath = false;
  Store? _activeStore;
  int _stepCount = 0;

  bool get isRendering => _isRendering;
  bool get hasPath => _hasPath;
  Store? get activeStore => _activeStore;
  int get stepCount => _stepCount;

  /// Marca el inicio del dibujado del trail para [store]. Reinicia cualquier
  /// estado previo de "dibujado completo" y notifica a los listeners para
  /// que la UI pueda mostrar un overlay de "calculando ruta…" si aplica.
  void beginRender(Store store, {int stepCount = 0}) {
    _activeStore = store;
    _isRendering = true;
    _hasPath = false;
    _stepCount = stepCount;
    notifyListeners();
  }

  /// Se invoca cuando el motor 3D (JS) confirma que la ruta terminó de
  /// dibujarse en el piso. A partir de aquí el personaje puede arrancar.
  void completeRender({int? stepCount}) {
    _isRendering = false;
    _hasPath = true;
    if (stepCount != null) _stepCount = stepCount;
    notifyListeners();
  }

  /// **Único** punto autorizado para borrar el trail. Llamarlo:
  ///   • al cambiar de vista (`MapScreen.dispose`, salir del módulo).
  ///   • al recibir una NUEVA selección de tienda distinta a la activa.
  /// **No** llamarlo cuando el personaje termina su animación.
  void clearPath() {
    if (!_hasPath && !_isRendering && _activeStore == null) return;
    _activeStore = null;
    _isRendering = false;
    _hasPath = false;
    _stepCount = 0;
    notifyListeners();
  }
}
