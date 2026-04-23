import 'dart:io' show Platform;

/// Returns true if the current platform supports WebView-based 3D rendering.
bool get isWebViewSupported {
  return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
}
