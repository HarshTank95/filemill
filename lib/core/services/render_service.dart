import 'dart:typed_data';

import 'package:pdfx/pdfx.dart' as px;

/// A PDF opened through the platform renderer (Android PdfRenderer via pdfx),
/// used for page thumbnails, PDF→image export, and OCR input.
///
/// PdfRenderer is not safe for concurrent page access, so all render calls
/// are serialized through a simple future chain.
class RenderedDoc {
  final px.PdfDocument _doc;
  Future<void> _queue = Future.value();

  RenderedDoc._(this._doc);

  static Future<RenderedDoc> openFile(String path) async =>
      RenderedDoc._(await px.PdfDocument.openFile(path));

  static Future<RenderedDoc> openData(Uint8List bytes) async =>
      RenderedDoc._(await px.PdfDocument.openData(bytes));

  int get pageCount => _doc.pagesCount;

  /// Renders 0-based [index]. [scale] multiplies the page's natural size
  /// (72 dpi), so scale 2 ≈ 144 dpi.
  Future<Uint8List> renderPage(
    int index, {
    double scale = 2,
    bool png = true,
    int jpgQuality = 90,
  }) {
    final completer = _queue.then((_) async {
      final page = await _doc.getPage(index + 1);
      try {
        final image = await page.render(
          width: page.width * scale,
          height: page.height * scale,
          format:
              png ? px.PdfPageImageFormat.png : px.PdfPageImageFormat.jpeg,
          quality: jpgQuality,
          backgroundColor: '#FFFFFF',
        );
        if (image == null) {
          throw Exception('Page ${index + 1} could not be rendered');
        }
        return image.bytes;
      } finally {
        await page.close();
      }
    });
    _queue = completer.then((_) {}, onError: (_) {});
    return completer;
  }

  Future<void> close() => _doc.close();
}
