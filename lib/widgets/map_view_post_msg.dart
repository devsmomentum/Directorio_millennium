// Stub usado en plataformas no-web (Android/iOS/desktop).
// La versión real vive en `map_view_post_msg_web.dart` y se
// resuelve vía conditional import (`dart.library.js_interop`).

typedef MapViewMessageHandler = void Function();

class MapViewPostBridge {
  /// Registra el listener global para capturar el handshake
  /// `mapview-ready` proveniente de la iframe del WebView.
  void register({
    required String instanceId,
    required MapViewMessageHandler onReady,
    MapViewMessageHandler? onLoaded,
  }) {}

  /// Envía un comando JSON a la iframe ya capturada.
  /// Devuelve `true` si se pudo enviar; `false` si aún no hay
  /// referencia al `contentWindow` (caller debe usar fallback).
  bool tryPostCommand(String jsonPayload) => false;

  void dispose() {}
}
