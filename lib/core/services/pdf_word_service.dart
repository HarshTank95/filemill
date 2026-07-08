import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'docx.dart';

/// Serializable word/line/page data extracted from a PDF (safe to pass
/// across isolates — the Syncfusion objects themselves are not).
class WordData {
  final String text;
  final double x, y, w, h, size;
  final bool bold, italic, underline;
  const WordData(this.text, this.x, this.y, this.w, this.h, this.size,
      this.bold, this.italic, this.underline);
}

class LineData {
  final String text;
  final double x, y, w, h, size;
  final bool bold, italic, underline;
  final List<WordData> words;
  const LineData(this.text, this.x, this.y, this.w, this.h, this.size,
      this.bold, this.italic, this.underline, this.words);
}

class PageData {
  final double width, height;
  final List<LineData> lines;
  PageData(this.width, this.height, this.lines);
}

class PdfWordService {
  PdfWordService._();

  /// Extracts positioned text (pure Dart → runs in an isolate). Pages with
  /// no text layer come back empty so the caller can OCR them.
  static Future<List<PageData>> extractPages(Uint8List bytes) =>
      compute(_extract, bytes);

  /// Reconstructs structure and builds a .docx (pure Dart → isolate).
  static Future<Uint8List> buildDocx(List<PageData> pages) =>
      compute(_reconstruct, pages);
}

// ---------------------------------------------------------------------------
// Extraction
// ---------------------------------------------------------------------------

List<PageData> _extract(Uint8List bytes) {
  final doc = PdfDocument(inputBytes: bytes);
  final lines = PdfTextExtractor(doc).extractTextLines();
  final byPage = <int, List<LineData>>{};
  for (final line in lines) {
    final words = <WordData>[];
    for (final w in line.wordCollection) {
      final s = w.fontStyle;
      words.add(WordData(
        w.text,
        w.bounds.left,
        w.bounds.top,
        w.bounds.width,
        w.bounds.height,
        w.fontSize,
        s.contains(PdfFontStyle.bold),
        s.contains(PdfFontStyle.italic),
        s.contains(PdfFontStyle.underline),
      ));
    }
    final s = line.fontStyle;
    byPage.putIfAbsent(line.pageIndex, () => []).add(LineData(
          line.text,
          line.bounds.left,
          line.bounds.top,
          line.bounds.width,
          line.bounds.height,
          line.fontSize,
          s.contains(PdfFontStyle.bold),
          s.contains(PdfFontStyle.italic),
          s.contains(PdfFontStyle.underline),
          words,
        ));
  }
  final pages = <PageData>[];
  for (var i = 0; i < doc.pages.count; i++) {
    final size = doc.pages[i].size;
    // Growable so the OCR fallback can add lines for scanned pages.
    pages.add(PageData(size.width, size.height, byPage[i] ?? <LineData>[]));
  }
  doc.dispose();
  return pages;
}

// ---------------------------------------------------------------------------
// Reconstruction → DOCX
// ---------------------------------------------------------------------------

Uint8List _reconstruct(List<PageData> pages) {
  final paragraphs = <DocParagraph>[];
  for (final page in pages) {
    paragraphs.addAll(_reconstructPage(page));
  }
  if (paragraphs.isEmpty) {
    paragraphs.add(const DocParagraph([DocRun('(No extractable text found.)')]));
  }
  return DocxBuilder.build(paragraphs);
}

List<DocParagraph> _reconstructPage(PageData page) {
  final sorted = [...page.lines]..sort((a, b) => a.y.compareTo(b.y));
  if (sorted.isEmpty) return const [];
  final lines = _orderColumns(sorted, page.width);

  final bodySize = _median(lines.map((l) => l.size).where((s) => s > 0).toList());
  final result = <DocParagraph>[];

  // Group lines into paragraphs (merge soft-wrapped lines).
  var group = <LineData>[];
  void flush() {
    if (group.isNotEmpty) {
      result.add(_buildParagraph(group, bodySize, page.width));
      group = [];
    }
  }

  for (final line in lines) {
    if (line.text.trim().isEmpty) continue;
    if (group.isEmpty) {
      group.add(line);
      continue;
    }
    final prev = group.last;
    final gap = line.y - (prev.y + prev.h);
    final sameLeft = (line.x - prev.x).abs() < bodySize * 1.2;
    final sameSize = (line.size - prev.size).abs() < bodySize * 0.25;
    final heading = _headingLevel(line, bodySize) > 0 ||
        _headingLevel(prev, bodySize) > 0;
    final isList = _listMarker(line.text) || _listMarker(prev.text);
    if (gap >= 0 &&
        gap < bodySize * 0.8 &&
        sameLeft &&
        sameSize &&
        !heading &&
        !isList) {
      group.add(line); // soft wrap → same paragraph
    } else {
      flush();
      group.add(line);
    }
  }
  flush();
  return result;
}

DocParagraph _buildParagraph(
    List<LineData> lines, double bodySize, double pageWidth) {
  final first = lines.first;
  final heading = _headingLevel(first, bodySize);
  final bullet = _listMarker(first.text);
  final align = _align(first, pageWidth);

  // Rebuild text from word geometry: a space only when the gap between
  // glyphs is real, a tab for big column gaps, nothing for tight
  // intra-word gaps. This fixes both per-character PDFs ("T a x") and
  // letter-spaced titles ("H A R S H") without tuning to one file.
  final runs = <DocRun>[];
  final buf = StringBuffer();
  (bool, bool, bool, int)? curKey;

  void commit() {
    if (buf.isEmpty) return;
    final k = curKey!;
    // Collapse runs of spaces (some PDFs emit spaces as their own glyphs);
    // tabs are preserved.
    final text = buf.toString().replaceAll(RegExp(r' {2,}'), ' ');
    runs.add(DocRun(text,
        bold: k.$1, italic: k.$2, underline: k.$3, halfPt: k.$4 * 2));
    buf.clear();
  }

  void emit((bool, bool, bool, int) key, String sep, String text) {
    if (text.isEmpty) return;
    if (curKey == null || key != curKey) {
      commit();
      curKey = key;
    }
    buf
      ..write(sep)
      ..write(text);
  }

  for (var li = 0; li < lines.length; li++) {
    final line = lines[li];
    final words = line.words;
    if (words.isEmpty) {
      final size = line.size <= 0 ? bodySize : line.size;
      final key = (line.bold || heading > 0, line.italic, line.underline,
          size.round());
      final text =
          li == 0 ? _stripLeadingMarker(line.text, bullet) : line.text;
      emit(key, li > 0 ? ' ' : '', text);
      continue;
    }
    for (var wi = 0; wi < words.length; wi++) {
      final w = words[wi];
      final size = w.size <= 0 ? bodySize : w.size;
      var text = w.text;
      if (li == 0 && wi == 0) text = _stripLeadingMarker(text, bullet);
      if (text.isEmpty) continue;
      String sep;
      if (wi > 0) {
        final prev = words[wi - 1];
        final gap = w.x - (prev.x + prev.w);
        sep = gap > size * 2.5 ? '\t' : (gap > size * 0.25 ? ' ' : '');
      } else {
        sep = li > 0 ? ' ' : '';
      }
      emit((w.bold || heading > 0, w.italic, w.underline, size.round()), sep,
          text);
    }
  }
  commit();

  if (runs.isEmpty) {
    runs.add(DocRun(first.text.trim(),
        bold: heading > 0, halfPt: bodySize.round() * 2));
  }
  return DocParagraph(runs, heading: heading, align: align, bullet: bullet);
}

/// Reorders lines so a two-column page reads column-by-column instead of
/// interleaved top-to-bottom. Conservative: only activates on a clearly
/// bimodal layout, and keeps full-width lines (headers, table rows) in
/// place as band separators. Single-column pages are returned unchanged.
List<LineData> _orderColumns(List<LineData> lines, double pageWidth) {
  if (lines.length < 6 || pageWidth <= 0) return lines;
  final mid = pageWidth / 2;
  final fullWidth = pageWidth * 0.55;
  var left = 0, right = 0;
  for (final l in lines) {
    if (l.w > fullWidth) continue;
    if (l.x + l.w / 2 < mid) {
      left++;
    } else {
      right++;
    }
  }
  if (left < 3 || right < 3) return lines; // not a two-column page

  final out = <LineData>[];
  var band = <LineData>[];
  void flush() {
    if (band.isEmpty) return;
    final l = <LineData>[], r = <LineData>[];
    for (final line in band) {
      (line.x + line.w / 2 < mid ? l : r).add(line);
    }
    out
      ..addAll(l)
      ..addAll(r);
    band = [];
  }

  for (final line in lines) {
    if (line.w > fullWidth) {
      flush();
      out.add(line);
    } else {
      band.add(line);
    }
  }
  flush();
  return out;
}

int _headingLevel(LineData line, double bodySize) {
  if (bodySize <= 0) return 0;
  final ratio = line.size / bodySize;
  final short = line.text.trim().length < 90;
  if (!short) return 0;
  if (ratio >= 1.7) return 1;
  if (ratio >= 1.4) return 2;
  if (ratio >= 1.18) return 3;
  return 0;
}

bool _listMarker(String text) {
  final t = text.trimLeft();
  return RegExp(r'^([•▪●◦·‣\-\*]\s+|\d{1,3}[.)]\s+|[a-zA-Z][.)]\s+)').hasMatch(t);
}

String _stripLeadingMarker(String text, bool strip) {
  if (!strip) return text;
  return text.replaceFirst(
      RegExp(r'^([•▪●◦·‣\-\*]\s*|\d{1,3}[.)]\s*|[a-zA-Z][.)]\s*)'), '');
}

String _align(LineData line, double pageWidth) {
  if (pageWidth <= 0) return 'left';
  final left = line.x;
  final right = pageWidth - (line.x + line.w);
  if (left > pageWidth * 0.12 && (left - right).abs() < pageWidth * 0.06) {
    return 'center';
  }
  if (right < pageWidth * 0.08 && left > pageWidth * 0.22) return 'right';
  return 'left';
}

double _median(List<double> values) {
  if (values.isEmpty) return 11;
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}
