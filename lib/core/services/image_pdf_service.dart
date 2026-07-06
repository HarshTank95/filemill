import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum PageSizeOption { auto, a4, letter }

/// Builds a PDF from images. Two isolate-backed stages so the UI can show
/// per-image progress: normalize (decode + bake EXIF orientation + JPEG
/// re-encode) runs once per image, then a single assemble pass.
class ImagePdfService {
  ImagePdfService._();

  static Future<Uint8List> normalize(Uint8List raw) =>
      compute(_normalize, raw);

  static Future<Uint8List> assemble(
    List<Uint8List> normalizedJpegs, {
    PageSizeOption pageSize = PageSizeOption.auto,
    bool margin = false,
  }) {
    return compute(
      _assemble,
      _AssembleArgs(normalizedJpegs, pageSize, margin),
    );
  }
}

class _AssembleArgs {
  final List<Uint8List> images;
  final PageSizeOption pageSize;
  final bool margin;
  const _AssembleArgs(this.images, this.pageSize, this.margin);
}

Uint8List _normalize(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) {
    throw Exception('Unsupported image format');
  }
  final upright = img.bakeOrientation(decoded);
  return Uint8List.fromList(img.encodeJpg(upright, quality: 88));
}

Future<Uint8List> _assemble(_AssembleArgs args) async {
  final doc = pw.Document();
  final marginPt = args.margin ? 24.0 : 0.0;

  for (final bytes in args.images) {
    final image = pw.MemoryImage(bytes);
    final PdfPageFormat format;
    switch (args.pageSize) {
      case PageSizeOption.auto:
        // 1 px = 1 pt: the page hugs the image exactly.
        format = PdfPageFormat(
          image.width!.toDouble() + marginPt * 2,
          image.height!.toDouble() + marginPt * 2,
        );
      case PageSizeOption.a4:
        format = PdfPageFormat.a4;
      case PageSizeOption.letter:
        format = PdfPageFormat.letter;
    }
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.all(marginPt),
        build: (_) => pw.Center(
          child: pw.Image(image, fit: pw.BoxFit.contain),
        ),
      ),
    );
  }
  return doc.save();
}
