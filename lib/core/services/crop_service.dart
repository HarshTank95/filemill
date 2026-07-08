import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Detects the content bounds of a rendered page (to trim white margins).
class CropService {
  CropService._();

  /// Returns the content region of [jpg] as a normalized (0..1) rect, or a
  /// small default inset if nothing distinct is found.
  static Future<Rect> autoTrim(Uint8List jpg) => compute(_autoTrim, jpg);
}

Rect _autoTrim(Uint8List jpg) {
  final image = img.decodeImage(jpg);
  if (image == null) return const Rect.fromLTWH(0.04, 0.04, 0.92, 0.92);
  final w = image.width, h = image.height;
  final rgb = image.getBytes(order: img.ChannelOrder.rgb);
  const threshold = 244; // below this (per channel) counts as content
  var minX = w, minY = h, maxX = 0, maxY = 0;
  for (var y = 0; y < h; y += 2) {
    for (var x = 0; x < w; x += 2) {
      final p = (y * w + x) * 3;
      if (rgb[p] < threshold || rgb[p + 1] < threshold || rgb[p + 2] < threshold) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX <= minX || maxY <= minY) {
    return const Rect.fromLTWH(0.04, 0.04, 0.92, 0.92);
  }
  // Small padding around the detected content.
  final padX = w * 0.01, padY = h * 0.01;
  final left = ((minX - padX) / w).clamp(0.0, 1.0);
  final top = ((minY - padY) / h).clamp(0.0, 1.0);
  final right = ((maxX + padX) / w).clamp(0.0, 1.0);
  final bottom = ((maxY + padY) / h).clamp(0.0, 1.0);
  return Rect.fromLTRB(left, top, right, bottom);
}
