import 'package:flutter/foundation.dart';

import '../../../models/store.dart';

/// Estados que recorre el visor 3D al ejecutar una navegación.
///
/// Flujo esperado:
/// `Idle` → `PathRendering` → `CharacterWalking` → `Arrived`
/// (la ruta dibujada permanece en pantalla en `Arrived` y solo se limpia
///  en `Idle`, disparado por cambio de vista o nueva selección de tienda).
@immutable
sealed class MapViewState {
  const MapViewState();
}

class MapIdleState extends MapViewState {
  const MapIdleState();
}

/// Se está dibujando la ruta de pasos en el suelo. Aún no camina nadie.
class MapPathRenderingState extends MapViewState {
  final Store store;
  const MapPathRenderingState(this.store);
}

/// La ruta ya está dibujada y el modelo 3D está caminando hacia el destino.
/// La colección de pasos persiste en la escena durante esta fase.
class MapCharacterWalkingState extends MapViewState {
  final Store store;
  const MapCharacterWalkingState(this.store);
}

/// El personaje completó (al menos una vez) el recorrido. El loop puede
/// continuar; lo importante es que la ruta dibujada NO se limpia aquí.
class MapArrivedState extends MapViewState {
  final Store store;
  const MapArrivedState(this.store);
}
