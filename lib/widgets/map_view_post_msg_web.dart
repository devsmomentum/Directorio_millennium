import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

typedef MapViewMessageHandler = void Function();

/// Canal `window.postMessage` entre el host Flutter Web y la iframe
/// del visor 3D. Evita tener que recargar el HTML cada vez que se
/// dispara un comando (`startAvatarRoute`, etc.) — la recarga era lo
/// que causaba el flash negro y el reset de la cámara.
class MapViewPostBridge {
  String? _instanceId;
  MapViewMessageHandler? _onReady;
  MapViewMessageHandler? _onLoaded;
  web.Window? _target;
  JSFunction? _listenerRef;

  void register({
    required String instanceId,
    required MapViewMessageHandler onReady,
    MapViewMessageHandler? onLoaded,
  }) {
    _instanceId = instanceId;
    _onReady = onReady;
    _onLoaded = onLoaded;
    final listener = _handleMessage.toJS;
    _listenerRef = listener;
    web.window.addEventListener('message', listener);
  }

  bool tryPostCommand(String jsonPayload) {
    final t = _target;
    if (t == null) return false;
    try {
      t.postMessage(jsonPayload.toJS, '*'.toJS);
      return true;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    final l = _listenerRef;
    if (l != null) {
      web.window.removeEventListener('message', l);
    }
    _listenerRef = null;
    _target = null;
    _onReady = null;
    _onLoaded = null;
  }

  void _handleMessage(web.MessageEvent ev) {
    try {
      final raw = ev.data;
      String str;
      if (raw.isA<JSString>()) {
        str = (raw as JSString).toDart;
      } else {
        return;
      }
      final decoded = jsonDecode(str);
      if (decoded is! Map) return;
      final kind = decoded['kind'];
      if (decoded['instanceId'] != _instanceId) return;
      if (kind == 'mapview-ready') {
        final src = ev.source;
        if (src == null) return;
        // event.source es el WindowProxy de la iframe.
        _target = src as web.Window;
        _onReady?.call();
      } else if (kind == 'mapview-loaded') {
        _onLoaded?.call();
      }
    } catch (_) {
      // Ignorar mensajes con formato inesperado.
    }
  }
}
