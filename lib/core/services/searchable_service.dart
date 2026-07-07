import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// One page of a searchable PDF: the visible page image plus recognized
/// lines in normalized (0..1) page coordinates.
class SearchablePage {
  final Uint8List jpg;
  final double widthPt;
  final double heightPt;
  final List<SearchableLine> lines;
  const SearchablePage({
    required this.jpg,
    required this.widthPt,
    required this.heightPt,
    required this.lines,
  });
}

class SearchableLine {
  final String text;
  final double nx, ny, nw, nh;
  const SearchableLine(this.text, this.nx, this.ny, this.nw, this.nh);
}

/// Builds a PDF where each page is an image with an INVISIBLE text layer
/// stretched over the recognized words — the page looks like the scan but
/// is searchable and copy-able in any viewer. Pure Dart, isolate-backed.
class SearchableService {
  SearchableService._();

  static Future<Uint8List> assemble(List<SearchablePage> pages) =>
      compute(_assemble, pages);
}

Future<Uint8List> _assemble(List<SearchablePage> pages) async {
  final doc = pw.Document();
  for (final page in pages) {
    final image = pw.MemoryImage(page.jpg);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(page.widthPt, page.heightPt),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.Image(image, fit: pw.BoxFit.fill),
            ),
            for (final line in page.lines)
              pw.Positioned(
                left: line.nx * page.widthPt,
                top: line.ny * page.heightPt,
                child: pw.SizedBox(
                  width: line.nw * page.widthPt,
                  height: line.nh * page.heightPt,
                  child: pw.FittedBox(
                    fit: pw.BoxFit.fill,
                    child: pw.Text(
                      line.text,
                      style: const pw.TextStyle(
                        renderingMode: PdfTextRenderingMode.invisible,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  return doc.save();
}
