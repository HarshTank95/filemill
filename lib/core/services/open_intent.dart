import 'package:flutter/services.dart';

/// Flutter side of the "Open with FileMill" bridge (see MainActivity.kt).
/// Checks for a pending ACTION_VIEW PDF at startup and listens for ones that
/// arrive while the app is already running.
class OpenIntent {
  OpenIntent._();

  static const MethodChannel _channel = MethodChannel('filemill/open_intent');

  static void init(void Function(String path, String name) onPdf) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onOpenedPdf') {
        await _fetchPending(onPdf);
      }
    });
    _fetchPending(onPdf);
  }

  static Future<void> _fetchPending(
      void Function(String path, String name) onPdf) async {
    try {
      final result =
          await _channel.invokeMapMethod<String, String>('getOpenedPdf');
      final path = result?['path'];
      if (path != null) {
        onPdf(path, result?['name'] ?? 'document.pdf');
      }
    } catch (_) {
      // Plugin absent (tests) or intent already consumed — never fatal.
    }
  }
}
