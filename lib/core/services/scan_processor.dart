import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Scan look applied after perspective correction.
enum ScanFilter { original, enhanced, grayscale, blackWhite }

extension ScanFilterLabel on ScanFilter {
  String get label {
    switch (this) {
      case ScanFilter.original:
        return 'Original';
      case ScanFilter.enhanced:
        return 'Enhanced';
      case ScanFilter.grayscale:
        return 'Grayscale';
      case ScanFilter.blackWhite:
        return 'B&W';
    }
  }
}

/// Result of edge detection: image aspect + suggested corners (normalized
/// 0..1, order TL TR BR BL).
class DetectResult {
  final double aspect; // width / height after EXIF orientation is applied
  final List<Offset> corners;
  const DetectResult(this.aspect, this.corners);
}

class ScanJob {
  final Uint8List bytes;
  final List<Offset> corners; // normalized TL TR BR BL
  final ScanFilter filter;
  final int maxDim;
  const ScanJob({
    required this.bytes,
    required this.corners,
    required this.filter,
    this.maxDim = 1800,
  });
}

/// Pure-Dart document scan pipeline (isolate-backed): edge suggestion via
/// gradient projections, perspective correction via a 4-point homography,
/// and print-style filters. No native code, no network — by design.
class ScanProcessor {
  ScanProcessor._();

  static Future<DetectResult> detect(Uint8List jpeg) =>
      compute(_detect, jpeg);

  static Future<Uint8List> process(ScanJob job) => compute(_process, job);
}

// ---------------------------------------------------------------------------
// Edge suggestion
// ---------------------------------------------------------------------------

DetectResult _detect(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return const DetectResult(0.75, _insetQuad);
  }
  final oriented = img.bakeOrientation(decoded);
  final aspect = oriented.width / oriented.height;

  final small = img.copyResize(oriented, width: 240);
  final w = small.width, h = small.height;
  final gray = Uint8List(w * h);
  final rgb = small.getBytes(order: img.ChannelOrder.rgb);
  for (var i = 0, p = 0; i < gray.length; i++, p += 3) {
    gray[i] =
        (0.299 * rgb[p] + 0.587 * rgb[p + 1] + 0.114 * rgb[p + 2]).round();
  }

  // Sobel gradient magnitude.
  final mag = Float32List(w * h);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final gx = (gray[i - w + 1] + 2 * gray[i + 1] + gray[i + w + 1]) -
          (gray[i - w - 1] + 2 * gray[i - 1] + gray[i + w - 1]);
      final gy = (gray[i + w - 1] + 2 * gray[i + w] + gray[i + w + 1]) -
          (gray[i - w - 1] + 2 * gray[i - w] + gray[i - w + 1]);
      mag[i] = math.sqrt((gx * gx + gy * gy).toDouble());
    }
  }

  // Column / row projections of edge energy.
  final colSum = Float32List(w);
  final rowSum = Float32List(h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = mag[y * w + x];
      colSum[x] += v;
      rowSum[y] += v;
    }
  }

  final x0 = _firstStrong(colSum, reverse: false);
  final x1 = _firstStrong(colSum, reverse: true);
  final y0 = _firstStrong(rowSum, reverse: false);
  final y1 = _firstStrong(rowSum, reverse: true);

  // Sanity: the suggested region must be a plausible document.
  if (x1 - x0 < w * 0.35 || y1 - y0 < h * 0.35) {
    return DetectResult(aspect, _insetQuad);
  }
  final left = x0 / w, right = x1 / w, top = y0 / h, bottom = y1 / h;
  return DetectResult(aspect, [
    Offset(left, top),
    Offset(right, top),
    Offset(right, bottom),
    Offset(left, bottom),
  ]);
}

const List<Offset> _insetQuad = [
  Offset(0.06, 0.06),
  Offset(0.94, 0.06),
  Offset(0.94, 0.94),
  Offset(0.06, 0.94),
];

int _firstStrong(Float32List sums, {required bool reverse}) {
  var max = 0.0;
  for (final v in sums) {
    if (v > max) max = v;
  }
  final threshold = max * 0.18;
  if (reverse) {
    for (var i = sums.length - 1; i >= 0; i--) {
      if (sums[i] > threshold) return i;
    }
    return sums.length - 1;
  }
  for (var i = 0; i < sums.length; i++) {
    if (sums[i] > threshold) return i;
  }
  return 0;
}

// ---------------------------------------------------------------------------
// Perspective correction + filters
// ---------------------------------------------------------------------------

Uint8List _process(ScanJob job) {
  final decoded = img.decodeImage(job.bytes);
  if (decoded == null) throw Exception('Unsupported image format');
  final src = img.bakeOrientation(decoded);
  final sw = src.width, sh = src.height;

  final quad = [
    for (final c in job.corners) Offset(c.dx * sw, c.dy * sh),
  ];

  // Output size from average opposite-edge lengths, capped at maxDim.
  double dist(Offset a, Offset b) => (a - b).distance;
  var outW = ((dist(quad[0], quad[1]) + dist(quad[3], quad[2])) / 2).round();
  var outH = ((dist(quad[0], quad[3]) + dist(quad[1], quad[2])) / 2).round();
  final scale = job.maxDim / math.max(outW, outH);
  if (scale < 1) {
    outW = (outW * scale).round();
    outH = (outH * scale).round();
  }
  outW = math.max(outW, 8);
  outH = math.max(outH, 8);

  // Homography mapping output rect -> source quad.
  final hMatrix = _homography(
    [
      const Offset(0, 0),
      Offset(outW - 1.0, 0),
      Offset(outW - 1.0, outH - 1.0),
      Offset(0, outH - 1.0),
    ],
    quad,
  );

  final srcRgb = src.getBytes(order: img.ChannelOrder.rgb);
  final out = Uint8List(outW * outH * 3);
  final h11 = hMatrix[0], h12 = hMatrix[1], h13 = hMatrix[2];
  final h21 = hMatrix[3], h22 = hMatrix[4], h23 = hMatrix[5];
  final h31 = hMatrix[6], h32 = hMatrix[7];

  var o = 0;
  for (var y = 0; y < outH; y++) {
    for (var x = 0; x < outW; x++) {
      final denom = h31 * x + h32 * y + 1;
      final fx = (h11 * x + h12 * y + h13) / denom;
      final fy = (h21 * x + h22 * y + h23) / denom;
      // Bilinear sample, clamped to the source.
      final x0 = fx.floor().clamp(0, sw - 1);
      final y0 = fy.floor().clamp(0, sh - 1);
      final x1 = (x0 + 1).clamp(0, sw - 1);
      final y1 = (y0 + 1).clamp(0, sh - 1);
      final tx = (fx - x0).clamp(0.0, 1.0);
      final ty = (fy - y0).clamp(0.0, 1.0);
      final p00 = (y0 * sw + x0) * 3;
      final p10 = (y0 * sw + x1) * 3;
      final p01 = (y1 * sw + x0) * 3;
      final p11 = (y1 * sw + x1) * 3;
      for (var c = 0; c < 3; c++) {
        final top = srcRgb[p00 + c] * (1 - tx) + srcRgb[p10 + c] * tx;
        final bot = srcRgb[p01 + c] * (1 - tx) + srcRgb[p11 + c] * tx;
        out[o + c] = (top * (1 - ty) + bot * ty).round().clamp(0, 255);
      }
      o += 3;
    }
  }

  _applyFilter(out, outW, outH, job.filter);

  final result = img.Image.fromBytes(
    width: outW,
    height: outH,
    bytes: out.buffer,
    order: img.ChannelOrder.rgb,
  );
  return Uint8List.fromList(img.encodeJpg(result, quality: 90));
}

/// Solves the 4-point homography H (h33 = 1) with src -> dst via Gaussian
/// elimination on the standard 8x8 DLT system.
List<double> _homography(List<Offset> src, List<Offset> dst) {
  final a = List.generate(8, (_) => Float64List(9));
  for (var i = 0; i < 4; i++) {
    final x = src[i].dx, y = src[i].dy;
    final bigX = dst[i].dx, bigY = dst[i].dy;
    a[i * 2]
      ..[0] = x
      ..[1] = y
      ..[2] = 1
      ..[6] = -bigX * x
      ..[7] = -bigX * y
      ..[8] = bigX;
    a[i * 2 + 1]
      ..[3] = x
      ..[4] = y
      ..[5] = 1
      ..[6] = -bigY * x
      ..[7] = -bigY * y
      ..[8] = bigY;
  }
  // Gaussian elimination with partial pivoting.
  for (var col = 0; col < 8; col++) {
    var pivot = col;
    for (var r = col + 1; r < 8; r++) {
      if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
    }
    final tmp = a[col];
    a[col] = a[pivot];
    a[pivot] = tmp;
    final div = a[col][col];
    if (div.abs() < 1e-12) continue;
    for (var c = col; c < 9; c++) {
      a[col][c] /= div;
    }
    for (var r = 0; r < 8; r++) {
      if (r == col) continue;
      final factor = a[r][col];
      if (factor == 0) continue;
      for (var c = col; c < 9; c++) {
        a[r][c] -= factor * a[col][c];
      }
    }
  }
  return [for (var r = 0; r < 8; r++) a[r][8]];
}

void _applyFilter(Uint8List rgb, int w, int h, ScanFilter filter) {
  switch (filter) {
    case ScanFilter.original:
      return;
    case ScanFilter.enhanced:
      _stretchContrast(rgb, keepColor: true);
    case ScanFilter.grayscale:
      _toGray(rgb);
      _stretchContrast(rgb, keepColor: false);
    case ScanFilter.blackWhite:
      _toGray(rgb);
      _adaptiveThreshold(rgb, w, h);
  }
}

void _toGray(Uint8List rgb) {
  for (var i = 0; i < rgb.length; i += 3) {
    final v =
        (0.299 * rgb[i] + 0.587 * rgb[i + 1] + 0.114 * rgb[i + 2]).round();
    rgb[i] = v;
    rgb[i + 1] = v;
    rgb[i + 2] = v;
  }
}

/// Percentile (2..98) luminance stretch — brightens paper, deepens ink.
void _stretchContrast(Uint8List rgb, {required bool keepColor}) {
  final hist = List<int>.filled(256, 0);
  var count = 0;
  for (var i = 0; i < rgb.length; i += 30) {
    final v =
        (0.299 * rgb[i] + 0.587 * rgb[i + 1] + 0.114 * rgb[i + 2]).round();
    hist[v]++;
    count++;
  }
  if (count == 0) return;
  int percentile(double p) {
    final target = (count * p).round();
    var acc = 0;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= target) return v;
    }
    return 255;
  }

  final lo = percentile(0.02);
  final hi = percentile(0.98);
  if (hi - lo < 24) return;
  final factor = 255 / (hi - lo);
  final lut = Uint8List(256);
  for (var v = 0; v < 256; v++) {
    lut[v] = ((v - lo) * factor).round().clamp(0, 255);
  }
  for (var i = 0; i < rgb.length; i++) {
    rgb[i] = lut[rgb[i]];
  }
}

/// Mean adaptive threshold over a sliding window (integral image), the
/// classic "photocopy" scan look. Input must already be grayscale.
void _adaptiveThreshold(Uint8List rgb, int w, int h) {
  final integral = Int64List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var rowAcc = 0;
    for (var x = 0; x < w; x++) {
      rowAcc += rgb[(y * w + x) * 3];
      integral[(y + 1) * (w + 1) + (x + 1)] =
          integral[y * (w + 1) + (x + 1)] + rowAcc;
    }
  }
  final half = math.max(8, math.min(w, h) ~/ 24);
  const bias = 9;
  for (var y = 0; y < h; y++) {
    final y0 = math.max(0, y - half), y1 = math.min(h - 1, y + half);
    for (var x = 0; x < w; x++) {
      final x0 = math.max(0, x - half), x1 = math.min(w - 1, x + half);
      final area = (x1 - x0 + 1) * (y1 - y0 + 1);
      final sum = integral[(y1 + 1) * (w + 1) + (x1 + 1)] -
          integral[y0 * (w + 1) + (x1 + 1)] -
          integral[(y1 + 1) * (w + 1) + x0] +
          integral[y0 * (w + 1) + x0];
      final i = (y * w + x) * 3;
      final v = rgb[i] * area > (sum - bias * area) ? 255 : 0;
      rgb[i] = v;
      rgb[i + 1] = v;
      rgb[i + 2] = v;
    }
  }
}
