import 'dart:math' as math;

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
  final extractor = PdfTextExtractor(doc);
  final lines = extractor.extractTextLines();
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

  // Repair "glued" lines: some PDFs (notably LaTeX) encode word spacing as
  // glyph kerning, and extractTextLines returns the whole line as one
  // space-less word. The layout-text extraction DOES resolve those spaces,
  // so look the line up there and take the spaced version.
  for (var i = 0; i < pages.length; i++) {
    final glued = pages[i].lines.where((l) => _looksGlued(l.text)).toList();
    if (glued.isEmpty) continue;
    final spacedByKey = <String, String>{};
    final layout = extractor.extractText(
        startPageIndex: i, endPageIndex: i, layoutText: true);
    for (final raw in layout.split('\n')) {
      final spaced = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (spaced.isEmpty) continue;
      spacedByKey[spaced.replaceAll(' ', '')] = spaced;
    }
    for (final l in glued) {
      final spaced = spacedByKey[l.text.trim()];
      if (spaced == null || spaced == l.text.trim()) continue;
      final idx = pages[i].lines.indexOf(l);
      pages[i].lines[idx] = LineData(
          spaced, l.x, l.y, l.w, l.h, l.size, l.bold, l.italic, l.underline, [
        if (l.words.length == 1)
          WordData(spaced, l.words[0].x, l.words[0].y, l.words[0].w,
              l.words[0].h, l.words[0].size, l.words[0].bold,
              l.words[0].italic, l.words[0].underline)
        else
          ...l.words
      ]);
    }
  }
  doc.dispose();
  return pages;
}

/// A long, space-less, letter-heavy line — the glued-extraction signature.
bool _looksGlued(String text) {
  final s = text.trim();
  if (s.length < 20 || s.contains(' ')) return false;
  final letters = s.runes
      .where((c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A))
      .length;
  return letters / s.length > 0.6;
}

// ---------------------------------------------------------------------------
// Reconstruction → DOCX
// ---------------------------------------------------------------------------

Uint8List _reconstruct(List<PageData> pages) {
  pages = _repairCurrency(pages);
  final paragraphs = <DocParagraph>[];
  for (final page in pages) {
    final ps = _reconstructPage(page);
    if (ps.isEmpty) continue;
    if (paragraphs.isEmpty) {
      paragraphs.addAll(ps);
    } else {
      // Each PDF page starts on a fresh Word page.
      final f = ps.first;
      paragraphs.add(DocParagraph(f.runs,
          heading: f.heading,
          align: f.align,
          bullet: f.bullet,
          indent: f.indent,
          before: f.before,
          tabs: f.tabs,
          pageBreak: true));
      paragraphs.addAll(ps.skip(1));
    }
  }
  if (paragraphs.isEmpty) {
    paragraphs.add(const DocParagraph([DocRun('(No extractable text found.)')]));
  }
  final pw = pages.isEmpty ? 595.0 : pages.first.width;
  final ph = pages.isEmpty ? 842.0 : pages.first.height;
  return DocxBuilder.build(paragraphs,
      pageWidth: (pw * 20).round(), pageHeight: (ph * 20).round());
}

/// Some Indian bank PDFs map the rupee sign to Á (U+00C1) in their embedded
/// font, so extraction yields "Á45,223.82". Repair only on document-level
/// evidence: Á repeatedly precedes digits and NEVER precedes a letter in any
/// clean line (real words like "Álvarez" would block it).
List<PageData> _repairCurrency(List<PageData> pages) {
  var beforeDigit = 0, beforeLetter = 0;
  for (final p in pages) {
    for (final l in p.lines) {
      if (_isGarbage(l.text)) continue;
      final t = l.text;
      for (var i = 0; i < t.length; i++) {
        if (t.codeUnitAt(i) != 0x00C1) continue;
        var j = i + 1;
        if (j < t.length && t[j] == ' ') j++;
        if (j >= t.length) continue;
        if (RegExp(r'[0-9]').hasMatch(t[j])) {
          beforeDigit++;
        } else if (RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(t[j])) {
          beforeLetter++;
        }
      }
    }
  }
  if (beforeDigit < 3 || beforeLetter > 0) return pages;
  return [
    for (final p in pages)
      PageData(p.width, p.height, [
        for (final l in p.lines)
          LineData(l.text.replaceAll('Á', '₹'), l.x, l.y, l.w, l.h, l.size,
              l.bold, l.italic, l.underline, [
            for (final w in l.words)
              WordData(w.text.replaceAll('Á', '₹'), w.x, w.y, w.w, w.h,
                  w.size, w.bold, w.italic, w.underline)
          ])
      ])
  ];
}

/// A line placed in reading order, with the x origin ("base") its indent and
/// tab stops are measured from — the page's left text edge, or its column's.
class _Placed {
  final LineData line;
  final double base;
  _Placed(this.line, this.base);
}

List<DocParagraph> _reconstructPage(PageData page) {
  final raw = <LineData>[
    for (final l in page.lines)
      if (l.text.trim().isNotEmpty && !_isGarbage(l.text)) _ensureWords(l)
  ]..sort((a, b) => a.y.compareTo(b.y));
  if (raw.isEmpty) return const [];

  final placed = _layout(raw, page.width);
  final bodySize = _median(
      placed.map((p) => p.line.size).where((s) => s > 0).toList());
  final rightEdge =
      _percentile(placed.map((p) => p.line.x + p.line.w).toList(), 0.9);
  final result = <DocParagraph>[];

  // Group lines into paragraphs (merge soft-wrapped lines). Vertical spacing
  // in the output mirrors the PDF's y gaps.
  var group = <_Placed>[];
  var prevBottom = -1.0;
  void flush() {
    if (group.isEmpty) return;
    final f = group.first.line;
    // 36pt = the 720-twip top margin of the generated page.
    final beforePt = prevBottom < 0 ? f.y - 36 : f.y - prevBottom;
    final before = (beforePt * 20).round().clamp(0, 6000);
    result.add(_buildParagraph(
        group, bodySize, page.width, rightEdge, before));
    prevBottom = group.last.line.y + group.last.line.h;
    group = [];
  }

  for (final pl in placed) {
    final line = pl.line;
    if (group.isEmpty) {
      group.add(pl);
      continue;
    }
    final prev = group.last.line;
    final gap = line.y - (prev.y + prev.h);
    final sameLeft = (line.x - prev.x).abs() < bodySize * 1.2;
    final sameSize = (line.size - prev.size).abs() < bodySize * 0.25;
    final heading = _headingLevel(line, bodySize) > 0 ||
        _headingLevel(prev, bodySize) > 0;
    final isList = _listMarker(line.text) || _listMarker(prev.text);
    // Rows with internal columns (tabs) stay their own paragraph so the
    // tab stops of one row never bleed into the next.
    final tabby = _multiSegment(line) || _multiSegment(prev);
    // A line that stops well short of the text's right edge ends its
    // paragraph — only wrapped lines (which run to the edge) continue it.
    final prevEndsShort = rightEdge - (prev.x + prev.w) > bodySize * 8;
    if (gap >= 0 &&
        gap < bodySize * 0.8 &&
        sameLeft &&
        sameSize &&
        !heading &&
        !isList &&
        !tabby &&
        !prevEndsShort &&
        pl.base == group.first.base) {
      group.add(pl); // soft wrap → same paragraph
    } else {
      flush();
      group.add(pl);
    }
  }
  flush();
  return result;
}

/// Decides the page's reading order and the x base of every line.
///
/// - A true newspaper layout → read column by column (each column is its
///   own x base). The test is strict, because misfiring on a label/value
///   table scrambles it: BOTH columns must dominate the page, have tightly
///   clustered x starts (text blocks share a left edge; table cells don't)
///   and be mostly full lines of text (cells are short).
/// - Everything else (single flow, forms, tables) → lines that share a row
///   (y overlap) are merged into one row so "label  value" and table rows
///   come out side by side instead of stacked.
List<_Placed> _layout(List<LineData> lines, double pageWidth) {
  if (lines.length >= 12 && pageWidth > 0) {
    final mid = pageWidth / 2;
    final fullWidth = pageWidth * 0.55;
    final left = <LineData>[], right = <LineData>[];
    for (final l in lines) {
      if (l.w > fullWidth) continue;
      (l.x + l.w / 2 < mid ? left : right).add(l);
    }
    bool clustered(List<LineData> col) {
      final xs = col.map((l) => l.x).toList()..sort();
      final modal = xs[xs.length ~/ 2];
      final near =
          xs.where((x) => (x - modal).abs() < pageWidth * 0.015).length;
      return near >= col.length * 0.7;
    }

    bool filled(List<LineData> col, double colEnd) {
      final start = _percentile(col.map((l) => l.x).toList(), 0.1);
      final colWidth = colEnd - start;
      if (colWidth <= 0) return false;
      final full = col.where((l) => l.w >= colWidth * 0.6).length;
      return full >= col.length * 0.6;
    }

    if (left.length >= 6 &&
        right.length >= 6 &&
        left.length + right.length >= lines.length * 0.6 &&
        clustered(left) &&
        clustered(right) &&
        filled(left, mid) &&
        filled(right, pageWidth * 0.96)) {
      return _newspaper(lines, fullWidth, mid, left, right);
    }
  }
  final rows = _mergeRows(lines);
  final base = _percentile(rows.map((r) => r.x).toList(), 0.1);
  return [for (final r in rows) _Placed(r, base)];
}

List<_Placed> _newspaper(List<LineData> lines, double fullWidth, double mid,
    List<LineData> allLeft, List<LineData> allRight) {
  final leftBase = _percentile(allLeft.map((l) => l.x).toList(), 0.1);
  final rightBase = _percentile(allRight.map((l) => l.x).toList(), 0.1);
  final out = <_Placed>[];
  var band = <LineData>[];
  void flushBand() {
    if (band.isEmpty) return;
    final l = <LineData>[], r = <LineData>[];
    for (final line in band) {
      (line.x + line.w / 2 < mid ? l : r).add(line);
    }
    out
      ..addAll([for (final x in l) _Placed(x, leftBase)])
      ..addAll([for (final x in r) _Placed(x, rightBase)]);
    band = [];
  }

  for (final line in lines) {
    if (line.w > fullWidth) {
      flushBand();
      out.add(_Placed(line, leftBase));
    } else {
      band.add(line);
    }
  }
  flushBand();
  return out;
}

/// Merges lines that overlap vertically into a single left-to-right row, so
/// cells of the same visual row stay together ("Date … 2000.00 … DR").
/// Membership is judged against the row's FIRST line only — never against a
/// growing band — so stacked lines can't chain distinct rows together.
/// A line whose font size is wildly different from the anchor's (diagonal
/// watermarks, decorations) never joins a row — it becomes its own.
List<LineData> _mergeRows(List<LineData> lines) {
  final used = List<bool>.filled(lines.length, false);
  final out = <LineData>[];
  for (var i = 0; i < lines.length; i++) {
    if (used[i]) continue;
    final anchor = lines[i];
    final row = <LineData>[anchor];
    for (var j = i + 1; j < lines.length; j++) {
      if (used[j]) continue;
      final l = lines[j];
      if (l.y >= anchor.y + anchor.h) break; // y-sorted: nothing overlaps now
      final overlap =
          math.min(anchor.y + anchor.h, l.y + l.h) - math.max(anchor.y, l.y);
      if (overlap <= 0.5 * math.min(l.h, anchor.h)) continue;
      final ratio =
          anchor.size > 0 && l.size > 0 ? l.size / anchor.size : 1.0;
      if (ratio < 0.55 || ratio > 1.8) continue;
      row.add(l);
      used[j] = true;
    }
    out.add(row.length == 1 ? row.first : _mergeRow(row));
  }
  return out;
}

LineData _mergeRow(List<LineData> row) {
  row.sort((a, b) => a.x.compareTo(b.x));
  final words = <WordData>[for (final l in row) ...l.words]
    ..sort((a, b) => a.x.compareTo(b.x));
  final x = row.map((l) => l.x).reduce(math.min);
  final y = row.map((l) => l.y).reduce(math.min);
  final right = row.map((l) => l.x + l.w).reduce(math.max);
  final bottom = row.map((l) => l.y + l.h).reduce(math.max);
  final lead = row.first;
  return LineData(row.map((l) => l.text).join(' '), x, y, right - x,
      bottom - y, lead.size, lead.bold, lead.italic, lead.underline, words);
}

/// Guarantees a line carries word geometry (OCR lines come without words)
/// and that words are in visual left-to-right order — some PDFs emit them
/// in draw order, which can scramble label/value pairs.
LineData _ensureWords(LineData l) {
  if (l.words.isEmpty) {
    return LineData(l.text, l.x, l.y, l.w, l.h, l.size, l.bold, l.italic,
        l.underline, [
      WordData(l.text, l.x, l.y, l.w, l.h, l.size, l.bold, l.italic,
          l.underline)
    ]);
  }
  final ws = [...l.words]..sort((a, b) => a.x.compareTo(b.x));
  return LineData(
      l.text, l.x, l.y, l.w, l.h, l.size, l.bold, l.italic, l.underline, ws);
}

/// True when a line contains column-sized internal gaps (i.e. would emit tabs).
bool _multiSegment(LineData l) {
  final ws = l.words;
  for (var i = 1; i < ws.length; i++) {
    final size = ws[i].size > 0 ? ws[i].size : l.size;
    if (ws[i].x - (ws[i - 1].x + ws[i - 1].w) > size * 2.5) return true;
  }
  return false;
}

DocParagraph _buildParagraph(List<_Placed> group, double bodySize,
    double pageWidth, double rightEdge, int before) {
  final lines = [for (final p in group) p.line];
  final base = group.first.base;
  final first = lines.first;
  final heading = _headingLevel(first, bodySize);
  final bullet = _symbolMarker(first.text);
  final align = _align(first, pageWidth);
  final indent = align == 'left'
      ? ((first.x - base) * 20).round().clamp(0, (pageWidth * 15).round())
      : 0;

  // Rebuild text. A line is either "real words" (join every word with a
  // space) or "per character" (some PDFs emit one glyph per word — decide
  // spaces from the gaps). Big gaps become tabs at the exact PDF column
  // position; a hyphen at a soft line-break is joined. This handles
  // narrow-spaced resumes, per-character invoices, letter-spaced titles
  // and label/value rows with one code path.
  final runs = <DocRun>[];
  final tabs = <DocTab>[];
  var buf = '';
  (bool, bool, bool, int)? curKey;

  void commit() {
    if (buf.isEmpty) return;
    final k = curKey!;
    runs.add(DocRun(buf.replaceAll(RegExp(r' {2,}'), ' '),
        bold: k.$1, italic: k.$2, underline: k.$3, halfPt: k.$4 * 2));
    buf = '';
  }

  void put((bool, bool, bool, int) key, String sep, String text) {
    if (text.isEmpty) return;
    if (curKey == null || key != curKey) {
      commit();
      curKey = key;
    }
    buf = '$buf$sep$text';
  }

  for (var li = 0; li < lines.length; li++) {
    final line = lines[li];
    final words = line.words;
    final perChar = _isPerChar(words);

    // Separator that starts this line — drop a soft hyphen at a line break.
    var startSep = li > 0 ? ' ' : '';
    if (li > 0) {
      final firstText = words.isNotEmpty ? words.first.text : line.text;
      if (RegExp(r'[A-Za-z]-$').hasMatch(buf) &&
          RegExp(r'^[a-z]').hasMatch(firstText)) {
        buf = buf.substring(0, buf.length - 1);
        startSep = '';
      }
    }

    for (var wi = 0; wi < words.length; wi++) {
      final w = words[wi];
      final size = w.size <= 0 ? bodySize : w.size;
      var text = w.text;
      if (li == 0 && wi == 0) text = _stripLeadingMarker(text, bullet);
      if (text.isEmpty) continue;
      String sep;
      if (wi == 0) {
        sep = startSep;
      } else {
        final prev = words[wi - 1];
        final gap = w.x - (prev.x + prev.w);
        if (gap > size * 2.5) {
          sep = '\t';
          tabs.add(_tabStop(words, wi, base, bodySize, rightEdge, pageWidth));
        } else if (perChar) {
          sep = gap > size * 0.25 ? ' ' : '';
        } else {
          sep = ' '; // real words are always space-separated
        }
      }
      put((w.bold || heading > 0, w.italic, w.underline, size.round()), sep,
          text);
    }
  }
  commit();

  if (runs.isEmpty) {
    runs.add(DocRun(first.text.trim(),
        bold: heading > 0, halfPt: bodySize.round() * 2));
  }
  return DocParagraph(runs,
      heading: heading,
      align: align,
      bullet: bullet,
      indent: indent,
      before: before,
      tabs: _dedupeTabs(tabs, indent));
}

/// Tab stop for the segment starting at [wi] — placed at the segment's exact
/// PDF x. A final segment that touches the right text edge becomes a
/// right-aligned stop (ragged dates/page numbers line up like the original).
DocTab _tabStop(List<WordData> words, int wi, double base, double bodySize,
    double rightEdge, double pageWidth) {
  var end = wi;
  var lastRight = words[wi].x + words[wi].w;
  for (var k = wi + 1; k < words.length; k++) {
    final size = words[k].size > 0 ? words[k].size : bodySize;
    if (words[k].x - lastRight > size * 2.5) break;
    lastRight = words[k].x + words[k].w;
    end = k;
  }
  if (end == words.length - 1 && lastRight >= rightEdge - pageWidth * 0.03) {
    return DocTab(((rightEdge - base) * 20).round(), right: true);
  }
  return DocTab(((words[wi].x - base) * 20).round());
}

List<DocTab> _dedupeTabs(List<DocTab> tabs, int indent) {
  if (tabs.isEmpty) return const [];
  final sorted = [...tabs]..sort((a, b) => a.pos.compareTo(b.pos));
  final out = <DocTab>[];
  for (final t in sorted) {
    if (t.pos <= indent + 40) continue; // before the text even starts
    if (out.isNotEmpty && (t.pos - out.last.pos) < 80) continue;
    out.add(t);
  }
  return out;
}

/// Drops lines that are mostly non-text glyphs — QR codes, barcodes and
/// logos rendered with private-use / broken-encoding fonts come through as
/// gibberish. Real text (incl. ₹, ±, accents) stays well under the bar.
bool _isGarbage(String text) {
  final t = text.trim();
  if (t.length < 8) return false;
  const keep = {0x20B9, 0x20AC, 0x00B1, 0x2014, 0x2013, 0x2018, 0x2019,
    0x201C, 0x201D, 0x2026, 0x00B0};
  var weird = 0;
  for (final c in t.runes) {
    if (c > 0x7F && !keep.contains(c)) weird++;
  }
  return weird / t.length > 0.4;
}

/// True when a line's words look like individual glyphs (some PDFs return
/// one "word" per character) rather than real words.
bool _isPerChar(List<WordData> words) {
  if (words.length < 3) return false;
  final singles = words.where((w) => w.text.trim().length <= 1).length;
  return singles > words.length * 0.55;
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
  // En/em dashes and bullets may sit flush against their text; a plain
  // hyphen needs a following space (so "-107.43" isn't a list item).
  // Asterisks are footnote markers, not bullets — leave them alone.
  return RegExp(r'^([•▪●◦·‣–—]\s*\S|-\s+|\d{1,3}[.)]\s+|[a-zA-Z][.)]\s+)')
      .hasMatch(t);
}

/// Only symbol bullets are replaced with Word's bullet — numbered/lettered
/// markers ("1.", "a)"), dashes and asterisks keep their literal text.
bool _symbolMarker(String text) =>
    RegExp(r'^[•▪●◦·‣]\s*\S').hasMatch(text.trimLeft());

String _stripLeadingMarker(String text, bool strip) {
  if (!strip) return text;
  return text.replaceFirst(RegExp(r'^\s*[•▪●◦·‣]\s*'), '');
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

double _percentile(List<double> values, double p) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  return sorted[((sorted.length - 1) * p).round()];
}
