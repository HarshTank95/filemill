import 'dart:async';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Wires the Android share-sheet entry point ("share to FileMill") into the
/// app. Errors are swallowed: intake must never crash startup (and the
/// plugin is absent in widget tests).
class ShareIntake {
  ShareIntake._();

  static StreamSubscription<List<SharedMediaFile>>? _sub;

  static void init(void Function(List<SharedMediaFile> files) onFiles) {
    try {
      ReceiveSharingIntent.instance.getInitialMedia().then((files) {
        if (files.isNotEmpty) {
          onFiles(files);
          ReceiveSharingIntent.instance.reset();
        }
      }).catchError((_) {});
      _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
        (files) {
          if (files.isNotEmpty) onFiles(files);
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  static void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
