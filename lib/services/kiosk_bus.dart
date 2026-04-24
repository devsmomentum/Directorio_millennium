import 'package:flutter/foundation.dart';

/// Bus global para notificar cambios del kiosco actualmente vinculado.
///
/// Se usa porque el `MapScreen` vive dentro de un `IndexedStack` en
/// `MainLayout`, por lo que no se reinicia al volver desde otras pantallas. El
/// selector de kiosco (ahora en `AppHeader`) emite aquí tras guardar en
/// `SharedPreferences` para que cualquier pantalla interesada pueda recargar
/// datos dependientes del kiosco (node_id, piso, rutas, etc.).
///
/// Patrón: `ValueListenable<int>` — el valor es un contador que se incrementa
/// en cada cambio (identidad del kiosco no importa, solo que algo cambió). Los
/// listeners llaman a `SharedPreferences.getInstance()` para leer el nuevo
/// `kiosk_id`.
class KioskBus {
  KioskBus._();

  /// Contador que incrementa cada vez que se elige un kiosco.
  static final ValueNotifier<int> selectionTick = ValueNotifier<int>(0);

  /// Dispara una notificación a todos los listeners suscritos.
  static void notifyKioskChanged() {
    selectionTick.value = selectionTick.value + 1;
  }
}
