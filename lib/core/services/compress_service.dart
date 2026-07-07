import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'render_service.dart';

/// Honest lossy PDF compression: every page is re-rendered as a JPEG at reduced
/// resolution and rebuilt into a new PDF with identical page sizes. Text
/// becomes non-selectable — the UI must say so.
class CompressService {
  CompressService._();

  /// Quality ladder used by the "fit under target" search, strongest first.
  static const List<(double scale, int quality)> ladder = [
    (1.6, 70),
    (1.3, 60),
    (1.0, 50),
    (0.9, 40),
    (0.75, 35),
  ];

  static Future<Uint8List> compress(
    RenderedDoc doc, {
    required double scale,
    required int jpgQuality,
    void Function(int done, int total)? onProgress,
  }) async {
    final images = <Uint8List>[];
    final sizes = <Size>[];
    for (var i = 0; i < doc.pageCount; i++) {
      sizes.add(await doc.pageSize(i));
      images.add(await doc.renderPage(
        i,
        scale: scale,
        png: false,
        jpgQuality: jpgQuality,
      ));
      onProgress?.call(i + 1, doc.pageCount);
    }
    return compute(_rebuild, _RebuildArgs(images, sizes));
  }

  /// Walks the quality ladder until the output fits [targetBytes]. Returns
  /// the best attempt even if the target was not reachable.
  static Future<Uint8List> fitUnder(
    RenderedDoc doc, {
    required int targetBytes,
    void Function(String status)? onStatus,
  }) async {
    Uint8List? best;
    for (var step = 0; step < ladder.length; step++) {
      final (scale, quality) = ladder[step];
      final result = await compress(
        doc,
        scale: scale,
        jpgQuality: quality,
        onProgress: (done, total) => onStatus?.call(
            'Pass ${step + 1} — page $done of $total'),
      );
      if (best == null || result.length < best.length) best = result;
      if (result.length <= targetBytes) return result;
    }
    return best!;
  }
}

class _RebuildArgs {
  final List<Uint8List> images;
  final List<Size> sizes;
  const _RebuildArgs(this.images, this.sizes);
}

Future<Uint8List> _rebuild(_RebuildArgs args) async {
  final doc = pw.Document();
  for (var i = 0; i < args.images.length; i++) {
    final image = pw.MemoryImage(args.images[i]);
    doc.addPage(
      pw.Page(
        pageFormat:
            PdfPageFormat(args.sizes[i].width, args.sizes[i].height),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
      ),
    );
  }
  return doc.save();
}
