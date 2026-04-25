import 'dart:async';

import '../../../models/store.dart';

/// Bus de selección de tienda. Desacopla la fuente del evento (lista del
/// directorio, deep-link, realtime de Supabase, etc.) del consumidor que
/// dispara la navegación en el mapa.
///
/// El [MapStateManager] se suscribe a [onStoreSelected] y reacciona a cada
/// emisión sin conocer quién la originó.
class StoreSelectionService {
  final StreamController<Store> _controller = StreamController<Store>.broadcast();

  Stream<Store> get onStoreSelected => _controller.stream;

  void select(Store store) {
    if (_controller.isClosed) return;
    _controller.add(store);
  }

  void dispose() {
    _controller.close();
  }
}
