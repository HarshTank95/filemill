import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

// Generates FileMill's icon assets: an infinity mark (matching the in-app
// logo) on the brand gradient. Run: dart run tool/gen_icons.dart
void main() {
  Directory('assets/icon').createSync(recursive: true);
  _write('assets/icon/icon.png', _icon(gradientBg: true, r: 168, off: 150, th: 46));
  _write('assets/icon/foreground.png',
      _icon(gradientBg: false, r: 132, off: 118, th: 38));
  stdout.writeln('Icons generated.');
}

void _write(String path, img.Image image) {
  File(path).writeAsBytesSync(img.encodePng(image));
  stdout.writeln('  $path');
}

img.Image _icon({
  required bool gradientBg,
  required double r,
  required double off,
  required double th,
  int size = 1024,
  bool rounded = false,
}) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  final cx = size / 2, cy = size / 2;
  final c1x = cx - off, c2x = cx + off;
  final radius = size * 0.22; // corner radius when [rounded]

  // Brand gradient endpoints — deep indigo -> bright violet for a visible
  // sweep even inside Android 12's circular splash crop.
  const a = [0x2E, 0x2A, 0xE0];
  const bb = [0x9A, 0x6B, 0xFF];

  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      // Ring coverage (soft-edged) for the two lobes of the infinity.
      final d1 = sqrt((x - c1x) * (x - c1x) + (y - cy) * (y - cy));
      final d2 = sqrt((x - c2x) * (x - c2x) + (y - cy) * (y - cy));
      final cover = max(_ring(d1, r, th), _ring(d2, r, th));

      if (gradientBg) {
        // Optional rounded-corner alpha so the tile matches the in-app logo.
        var tileA = 1.0;
        if (rounded) {
          final dx = max(radius - x, x - (size - radius)).clamp(0.0, radius);
          final dy = max(radius - y, y - (size - radius)).clamp(0.0, radius);
          final corner = sqrt(dx * dx + dy * dy);
          if (corner > radius) {
            tileA = (radius + 1.5 - corner).clamp(0.0, 1.0);
          }
        }
        final t = (x + y) / (2 * size);
        final br = _lerp(a[0], bb[0], t);
        final bg = _lerp(a[1], bb[1], t);
        final bl = _lerp(a[2], bb[2], t);
        // White mark over the gradient.
        final rr = _mix(br, 255, cover);
        final gg = _mix(bg, 255, cover);
        final blu = _mix(bl, 255, cover);
        image.setPixelRgba(x, y, rr, gg, blu, (tileA * 255).round());
      } else {
        // Transparent bg, white mark with soft alpha.
        image.setPixelRgba(x, y, 255, 255, 255, (cover * 255).round());
      }
    }
  }
  return image;
}

double _ring(double d, double r, double th) {
  final e = (d - r).abs();
  if (e <= th) return 1.0;
  if (e <= th + 3) return (th + 3 - e) / 3;
  return 0.0;
}

int _lerp(int x, int y, double t) => (x + (y - x) * t).round().clamp(0, 255);
int _mix(int base, int over, double a) =>
    (base + (over - base) * a).round().clamp(0, 255);
