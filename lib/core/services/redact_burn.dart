import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// A redaction burned directly into the rendered page image, so the effect
/// (like the flattening itself) is irreversible pixels, not an overlay.
class BurnBox {
  final Rect rectPx; // in rendered-image pixels
  final bool pixelate; // false = solid black
  const BurnBox(this.rectPx, this.pixelate);
}

class RedactBurn {
  RedactBurn._();

  static Future<Uint8List> burn(Uint8List jpg, List<BurnBox> boxes) =>
      compute(_burn, _BurnArgs(jpg, boxes));
}

class _BurnArgs {
  final Uint8List jpg;
  final List<BurnBox> boxes;
  const _BurnArgs(this.jpg, this.boxes);
}

Uint8List _burn(_BurnArgs args) {
  final image = img.decodeImage(args.jpg);
  if (image == null) throw Exception('Unsupported image format');
  for (final box in args.boxes) {
    final x0 = box.rectPx.left.round().clamp(0, image.width - 1);
    final y0 = box.rectPx.top.round().clamp(0, image.height - 1);
    final x1 = box.rectPx.right.round().clamp(0, image.width - 1);
    final y1 = box.rectPx.bottom.round().clamp(0, image.height - 1);
    if (x1 <= x0 || y1 <= y0) continue;
    if (box.pixelate) {
      _mosaic(image, x0, y0, x1, y1);
    } else {
      img.fillRect(image,
          x1: x0, y1: y0, x2: x1, y2: y1, color: img.ColorRgb8(0, 0, 0));
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 88));
}

/// Coarse mosaic: large cells so the content is unrecognizable (safer than
/// gaussian blur, which can sometimes be partially reversed).
void _mosaic(img.Image image, int x0, int y0, int x1, int y1) {
  final cell = ((y1 - y0) / 4).clamp(14, 64).round();
  for (var cy = y0; cy <= y1; cy += cell) {
    for (var cx = x0; cx <= x1; cx += cell) {
      final cw = (cx + cell > x1) ? x1 - cx + 1 : cell;
      final ch = (cy + cell > y1) ? y1 - cy + 1 : cell;
      // Average the cell's color.
      var r = 0, g = 0, b = 0, n = 0;
      for (var y = cy; y < cy + ch; y += 3) {
        for (var x = cx; x < cx + cw; x += 3) {
          final p = image.getPixel(x, y);
          r += p.r.toInt();
          g += p.g.toInt();
          b += p.b.toInt();
          n++;
        }
      }
      if (n == 0) continue;
      img.fillRect(image,
          x1: cx,
          y1: cy,
          x2: cx + cw - 1,
          y2: cy + ch - 1,
          color: img.ColorRgb8(r ~/ n, g ~/ n, b ~/ n));
    }
  }
}
