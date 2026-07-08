import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// One page in a rebuilt document: which source page, plus extra clockwise
/// quarter turns the user applied on top of the page's existing rotation.
class PageEdit {
  final int sourceIndex;
  final int quarterTurns;
  const PageEdit(this.sourceIndex, [this.quarterTurns = 0]);
}

/// Existing-PDF operations (merge / extract / reorganize), all Syncfusion,
/// all executed in background isolates — these are pure-Dart and CPU-bound.
class PdfService {
  PdfService._();

  static Future<int> pageCount(Uint8List bytes) => compute(_pageCount, bytes);

  static Future<Uint8List> merge(List<Uint8List> docs) =>
      compute(_merge, docs);

  /// Builds a new PDF from [edits] applied to a single source document.
  /// Handles extract (subset), reorder (permutation) and rotate in one pass.
  static Future<Uint8List> rebuild(Uint8List source, List<PageEdit> edits) {
    return compute(
      _rebuild,
      _RebuildArgs(source, [
        for (final e in edits) [e.sourceIndex, e.quarterTurns],
      ]),
    );
  }

  /// Crops the listed pages to a normalized (0..1) region; pages not listed
  /// are copied at full size. Rebuilds via template redraw (vector-safe).
  static Future<Uint8List> crop(Uint8List bytes, List<CropPage> pages) =>
      compute(_crop, _CropArgs(bytes, pages));

  /// True if the document requires a password to open.
  static Future<bool> isProtected(Uint8List bytes) =>
      compute(_isProtected, bytes);

  /// Encrypts with AES-256; the same password opens and owns the file.
  static Future<Uint8List> protect(Uint8List bytes, String password) =>
      compute(_protect, _PasswordArgs(bytes, password));

  /// Removes encryption from a protected document. Throws with a friendly
  /// message when the password is wrong.
  static Future<Uint8List> unlock(Uint8List bytes, String password) =>
      compute(_unlock, _PasswordArgs(bytes, password));

  /// Draws image stamps (signatures) onto existing pages. Coordinates are
  /// in PDF points with a top-left origin.
  static Future<Uint8List> stamp(Uint8List bytes, List<Stamp> stamps) =>
      compute(_stamp, _StampArgs(bytes, stamps));

  /// Draws typed text onto existing pages (form filling). Vector text,
  /// non-destructive to the rest of the page.
  static Future<Uint8List> addText(Uint8List bytes, List<TextStamp> stamps) =>
      compute(_addText, _TextStampArgs(bytes, stamps));

  /// Stamps a diagonal text watermark and/or page numbers onto every page.
  static Future<Uint8List> watermark(
          Uint8List bytes, WatermarkOptions options) =>
      compute(_watermark, _WatermarkArgs(bytes, options));

  /// True redaction: pages listed in [pages] are REPLACED by their
  /// pre-rendered raster image (destroying the underlying content) and the
  /// black boxes are drawn on top. Untouched pages are template-copied at
  /// original quality.
  static Future<Uint8List> redact(Uint8List bytes, List<RedactPage> pages) =>
      compute(_redact, _RedactArgs(bytes, pages));

  /// Finds every occurrence of [query] (case-insensitive) in the document's
  /// text layer and returns its location as a normalized (0..1) box per
  /// page. Scanned PDFs with no text layer return nothing.
  static Future<List<TextMatch>> findText(Uint8List bytes, String query) =>
      compute(_findText, _FindArgs(bytes, query));

  /// Draws translucent highlighter rectangles over the page WITHOUT
  /// flattening — text stays selectable and quality is untouched.
  static Future<Uint8List> highlight(
          Uint8List bytes, List<HighlightBox> boxes) =>
      compute(_highlight, _HighlightArgs(bytes, boxes));

  /// Draws freehand ink strokes onto pages as vector polylines.
  static Future<Uint8List> drawInk(Uint8List bytes, List<InkStroke> strokes) =>
      compute(_drawInk, _InkArgs(bytes, strokes));
}

enum InkShape { pen, line, arrow, rect, ellipse }

/// A drawn mark: normalized (0..1) points, RGB color, width as a fraction of
/// the page width, and a shape kind.
class InkStroke {
  final int pageIndex;
  final int r, g, b;
  final double width;
  final InkShape shape;
  final List<Offset> points;
  const InkStroke(
      this.pageIndex, this.r, this.g, this.b, this.width, this.shape, this.points);
}

class _InkArgs {
  final Uint8List bytes;
  final List<InkStroke> strokes;
  const _InkArgs(this.bytes, this.strokes);
}

Future<Uint8List> _drawInk(_InkArgs args) async {
  final doc = PdfDocument(inputBytes: args.bytes);
  final sizes = <int, Size>{};
  for (final s in args.strokes) {
    if (s.points.length < 2) continue;
    final page = doc.pages[s.pageIndex];
    final size = sizes.putIfAbsent(s.pageIndex, () => page.size);
    final pen = PdfPen(PdfColor(s.r, s.g, s.b), width: s.width * size.width)
      ..lineCap = PdfLineCap.round
      ..lineJoin = PdfLineJoin.round;
    final g = page.graphics;
    Offset pt(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
    final a = pt(s.points.first), b = pt(s.points.last);
    switch (s.shape) {
      case InkShape.pen:
        for (var i = 0; i < s.points.length - 1; i++) {
          g.drawLine(pen, pt(s.points[i]), pt(s.points[i + 1]));
        }
      case InkShape.line:
        g.drawLine(pen, a, b);
      case InkShape.arrow:
        g.drawLine(pen, a, b);
        final ang = math.atan2(b.dy - a.dy, b.dx - a.dx);
        final len = size.width * 0.022;
        for (final off in [0.5, -0.5]) {
          g.drawLine(
            pen,
            b,
            Offset(b.dx + len * math.cos(ang + math.pi + off),
                b.dy + len * math.sin(ang + math.pi + off)),
          );
        }
      case InkShape.rect:
        g.drawRectangle(pen: pen, bounds: Rect.fromPoints(a, b));
      case InkShape.ellipse:
        g.drawEllipse(Rect.fromPoints(a, b), pen: pen);
    }
  }
  final out = Uint8List.fromList(await doc.save());
  doc.dispose();
  return out;
}

/// A highlighter mark: rect in PDF points (top-left) + RGB color.
class HighlightBox {
  final int pageIndex;
  final Rect rect;
  final int r, g, b;
  const HighlightBox(this.pageIndex, this.rect, this.r, this.g, this.b);
}

class _HighlightArgs {
  final Uint8List bytes;
  final List<HighlightBox> boxes;
  const _HighlightArgs(this.bytes, this.boxes);
}

Future<Uint8List> _highlight(_HighlightArgs args) async {
  final doc = PdfDocument(inputBytes: args.bytes);
  for (final box in args.boxes) {
    final graphics = doc.pages[box.pageIndex].graphics;
    final state = graphics.save();
    // Translucent so the text underneath shows through — a highlighter look.
    graphics.setTransparency(0.4);
    graphics.drawRectangle(
      brush: PdfSolidBrush(PdfColor(box.r, box.g, box.b)),
      bounds: box.rect,
    );
    graphics.restore(state);
  }
  final out = Uint8List.fromList(await doc.save());
  doc.dispose();
  return out;
}

/// A located text hit: normalized (0..1) box with a top-left origin.
class TextMatch {
  final int pageIndex;
  final double nx, ny, nw, nh;
  const TextMatch(this.pageIndex, this.nx, this.ny, this.nw, this.nh);
}

class _FindArgs {
  final Uint8List bytes;
  final String query;
  const _FindArgs(this.bytes, this.query);
}

List<TextMatch> _findText(_FindArgs args) {
  final query = args.query.trim().toLowerCase();
  if (query.isEmpty) return const [];
  final tokens = query.split(RegExp(r'\s+'));
  final doc = PdfDocument(inputBytes: args.bytes);
  final lines = PdfTextExtractor(doc).extractTextLines();
  final sizes = <int, Size>{};
  final matches = <TextMatch>[];

  TextMatch toMatch(int page, Rect r) {
    final size = sizes.putIfAbsent(page, () => doc.pages[page].size);
    // Pad slightly so the box fully covers the glyphs.
    final left = ((r.left - 1) / size.width).clamp(0.0, 1.0);
    final top = ((r.top - 1) / size.height).clamp(0.0, 1.0);
    final w = ((r.width + 2) / size.width).clamp(0.0, 1.0 - left);
    final h = ((r.height + 2) / size.height).clamp(0.0, 1.0 - top);
    return TextMatch(page, left, top, w, h);
  }

  for (final line in lines) {
    final words = line.wordCollection;
    if (tokens.length == 1) {
      for (final word in words) {
        if (word.text.toLowerCase().contains(query)) {
          matches.add(toMatch(line.pageIndex, word.bounds));
        }
      }
    } else {
      // A phrase: find consecutive words matching the token sequence.
      for (var i = 0; i + tokens.length <= words.length; i++) {
        var ok = true;
        for (var j = 0; j < tokens.length; j++) {
          if (!words[i + j].text.toLowerCase().contains(tokens[j])) {
            ok = false;
            break;
          }
        }
        if (!ok) continue;
        var r = words[i].bounds;
        for (var j = 1; j < tokens.length; j++) {
          r = r.expandToInclude(words[i + j].bounds);
        }
        matches.add(toMatch(line.pageIndex, r));
      }
    }
  }
  doc.dispose();
  return matches;
}

/// One page to flatten + black out. [boxes] are Rects in PDF points using
/// the *display* orientation (matching the rendered [jpg]), as are
/// [widthPt]/[heightPt]. [labels] are drawn as vector text AFTER the
/// flattened image, centered on their (already-destroyed) boxes.
class RedactPage {
  final int pageIndex;
  final Uint8List jpg;
  final double widthPt;
  final double heightPt;
  final List<Rect> boxes;
  final List<RedactLabel> labels;
  const RedactPage({
    required this.pageIndex,
    required this.jpg,
    required this.widthPt,
    required this.heightPt,
    required this.boxes,
    this.labels = const [],
  });
}

class RedactLabel {
  final String text;
  final Rect rect; // PDF points
  final bool dark; // dark text (pixelated bg) vs white (black bg)
  const RedactLabel(this.text, this.rect, this.dark);
}

class _RedactArgs {
  final Uint8List bytes;
  final List<RedactPage> pages;
  const _RedactArgs(this.bytes, this.pages);
}

Future<Uint8List> _redact(_RedactArgs args) async {
  final src = PdfDocument(inputBytes: args.bytes);
  final out = PdfDocument();
  out.pageSettings.margins.all = 0;
  final replaced = {for (final p in args.pages) p.pageIndex: p};
  final black = PdfSolidBrush(PdfColor(0, 0, 0));
  for (var i = 0; i < src.pages.count; i++) {
    final redaction = replaced[i];
    if (redaction == null) {
      _appendPage(out, src.pages[i], 0);
      continue;
    }
    final size = Size(redaction.widthPt, redaction.heightPt);
    out.pageSettings.orientation = size.width > size.height
        ? PdfPageOrientation.landscape
        : PdfPageOrientation.portrait;
    out.pageSettings.size = size;
    out.pageSettings.rotate = PdfPageRotateAngle.rotateAngle0;
    final page = out.pages.add();
    page.graphics.drawImage(
      PdfBitmap(redaction.jpg),
      Rect.fromLTWH(0, 0, size.width, size.height),
    );
    for (final box in redaction.boxes) {
      page.graphics.drawRectangle(brush: black, bounds: box);
    }
    for (final label in redaction.labels) {
      _drawRedactLabel(page.graphics, label);
    }
  }
  src.dispose();
  final result = Uint8List.fromList(await out.save());
  out.dispose();
  return result;
}

/// Vector label centered on a redaction box, font sized to fit.
void _drawRedactLabel(PdfGraphics graphics, RedactLabel label) {
  var fontSize = (label.rect.height * 0.55).clamp(6.0, 48.0);
  var font = PdfStandardFont(PdfFontFamily.helvetica, fontSize,
      style: PdfFontStyle.bold);
  var measured = font.measureString(label.text);
  if (measured.width > label.rect.width * 0.92) {
    fontSize = fontSize * label.rect.width * 0.92 / measured.width;
    font = PdfStandardFont(PdfFontFamily.helvetica, fontSize,
        style: PdfFontStyle.bold);
    measured = font.measureString(label.text);
  }
  graphics.drawString(
    label.text,
    font,
    brush: PdfSolidBrush(
        label.dark ? PdfColor(40, 40, 40) : PdfColor(255, 255, 255)),
    bounds: Rect.fromLTWH(
      label.rect.left + (label.rect.width - measured.width) / 2,
      label.rect.top + (label.rect.height - measured.height) / 2,
      measured.width + 4,
      measured.height + 4,
    ),
  );
}

enum PageNumberFormat { simple, ofTotal, pageOfTotal }

enum PageNumberAlign { left, center, right }

class WatermarkOptions {
  final String? text; // null = no watermark
  final double opacity;
  final bool red; // red ink instead of gray
  final bool pageNumbers;
  final PageNumberFormat numberFormat;
  final PageNumberAlign numberAlign;
  const WatermarkOptions({
    this.text,
    this.opacity = 0.18,
    this.red = false,
    this.pageNumbers = false,
    this.numberFormat = PageNumberFormat.pageOfTotal,
    this.numberAlign = PageNumberAlign.center,
  });

  String numberLabel(int page, int total) {
    switch (numberFormat) {
      case PageNumberFormat.simple:
        return '$page';
      case PageNumberFormat.ofTotal:
        return '$page of $total';
      case PageNumberFormat.pageOfTotal:
        return 'Page $page of $total';
    }
  }
}

class _WatermarkArgs {
  final Uint8List bytes;
  final WatermarkOptions options;
  const _WatermarkArgs(this.bytes, this.options);
}

Future<Uint8List> _watermark(_WatermarkArgs args) async {
  final doc = PdfDocument(inputBytes: args.bytes);
  final options = args.options;
  final total = doc.pages.count;
  for (var i = 0; i < total; i++) {
    final page = doc.pages[i];
    final graphics = page.graphics;
    final size = page.getClientSize();

    final text = options.text;
    if (text != null && text.trim().isNotEmpty) {
      // Scale the font so the diagonal text spans ~70% of the page width.
      var fontSize = 72.0;
      var font = PdfStandardFont(PdfFontFamily.helvetica, fontSize,
          style: PdfFontStyle.bold);
      final measured = font.measureString(text);
      final diagonal =
          0.7 * math.sqrt(size.width * size.width + size.height * size.height);
      fontSize = (fontSize * diagonal / measured.width).clamp(18.0, 160.0);
      font = PdfStandardFont(PdfFontFamily.helvetica, fontSize,
          style: PdfFontStyle.bold);
      final textSize = font.measureString(text);

      final state = graphics.save();
      graphics.setTransparency(options.opacity);
      graphics.translateTransform(size.width / 2, size.height / 2);
      graphics.rotateTransform(
          -math.atan2(size.height, size.width) * 180 / math.pi);
      graphics.drawString(
        text,
        font,
        brush: PdfSolidBrush(options.red
            ? PdfColor(200, 30, 30)
            : PdfColor(90, 90, 90)),
        bounds: Rect.fromLTWH(-textSize.width / 2, -textSize.height / 2,
            textSize.width + 4, textSize.height + 4),
      );
      graphics.restore(state);
    }

    if (options.pageNumbers) {
      final label = options.numberLabel(i + 1, total);
      final font = PdfStandardFont(PdfFontFamily.helvetica, 10);
      final labelSize = font.measureString(label);
      final double x;
      switch (options.numberAlign) {
        case PageNumberAlign.left:
          x = 28;
        case PageNumberAlign.center:
          x = (size.width - labelSize.width) / 2;
        case PageNumberAlign.right:
          x = size.width - labelSize.width - 28;
      }
      graphics.drawString(
        label,
        font,
        brush: PdfSolidBrush(PdfColor(110, 110, 110)),
        bounds: Rect.fromLTWH(
            x, size.height - 24, labelSize.width + 4, labelSize.height + 4),
      );
    }
  }
  final out = Uint8List.fromList(await doc.save());
  doc.dispose();
  return out;
}

class Stamp {
  final int pageIndex;
  final Uint8List png;
  final double x, y, width, height;
  const Stamp({
    required this.pageIndex,
    required this.png,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

class _StampArgs {
  final Uint8List bytes;
  final List<Stamp> stamps;
  const _StampArgs(this.bytes, this.stamps);
}

Future<Uint8List> _stamp(_StampArgs args) async {
  final doc = PdfDocument(inputBytes: args.bytes);
  for (final s in args.stamps) {
    doc.pages[s.pageIndex].graphics.drawImage(
      PdfBitmap(s.png),
      Rect.fromLTWH(s.x, s.y, s.width, s.height),
    );
  }
  final out = Uint8List.fromList(await doc.save());
  doc.dispose();
  return out;
}

enum PdfFontKind { sans, serif, mono }

class TextStamp {
  final int pageIndex;
  final String text;
  final double x, y, width, fontSize;
  final int r, g, b;
  final bool bold, italic, underline;
  final PdfFontKind family;
  const TextStamp({
    required this.pageIndex,
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.fontSize,
    required this.r,
    required this.g,
    required this.b,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.family = PdfFontKind.sans,
  });
}

class _TextStampArgs {
  final Uint8List bytes;
  final List<TextStamp> stamps;
  const _TextStampArgs(this.bytes, this.stamps);
}

Future<Uint8List> _addText(_TextStampArgs args) async {
  final doc = PdfDocument(inputBytes: args.bytes);
  for (final t in args.stamps) {
    final page = doc.pages[t.pageIndex];
    final size = page.getClientSize();
    final PdfFontFamily family;
    switch (t.family) {
      case PdfFontKind.sans:
        family = PdfFontFamily.helvetica;
      case PdfFontKind.serif:
        family = PdfFontFamily.timesRoman;
      case PdfFontKind.mono:
        family = PdfFontFamily.courier;
    }
    final styles = <PdfFontStyle>[
      if (t.bold) PdfFontStyle.bold,
      if (t.italic) PdfFontStyle.italic,
      if (t.underline) PdfFontStyle.underline,
    ];
    final font = styles.isEmpty
        ? PdfStandardFont(family, t.fontSize)
        : PdfStandardFont(family, t.fontSize, multiStyle: styles);
    page.graphics.drawString(
      t.text,
      font,
      brush: PdfSolidBrush(PdfColor(t.r, t.g, t.b)),
      bounds: Rect.fromLTWH(t.x, t.y, t.width, size.height - t.y),
    );
  }
  final out = Uint8List.fromList(await doc.save());
  doc.dispose();
  return out;
}

class _PasswordArgs {
  final Uint8List bytes;
  final String password;
  const _PasswordArgs(this.bytes, this.password);
}

bool _isProtected(Uint8List bytes) {
  try {
    PdfDocument(inputBytes: bytes).dispose();
    return false;
  } catch (e) {
    final message = e.toString().toLowerCase();
    if (message.contains('password') || message.contains('encrypt')) {
      return true;
    }
    rethrow;
  }
}

Future<Uint8List> _protect(_PasswordArgs args) async {
  final doc = PdfDocument(inputBytes: args.bytes);
  doc.security
    ..userPassword = args.password
    ..ownerPassword = args.password
    ..algorithm = PdfEncryptionAlgorithm.aesx256Bit;
  final out = Uint8List.fromList(await doc.save());
  doc.dispose();
  return out;
}

Future<Uint8List> _unlock(_PasswordArgs args) async {
  final PdfDocument doc;
  try {
    doc = PdfDocument(inputBytes: args.bytes, password: args.password);
  } catch (_) {
    throw Exception('Incorrect password — try again.');
  }
  doc.security
    ..userPassword = ''
    ..ownerPassword = '';
  final out = Uint8List.fromList(await doc.save());
  doc.dispose();
  return out;
}

class _RebuildArgs {
  final Uint8List source;
  final List<List<int>> edits;
  const _RebuildArgs(this.source, this.edits);
}

class CropPage {
  final int pageIndex;
  final double nx, ny, nw, nh;
  const CropPage(this.pageIndex, this.nx, this.ny, this.nw, this.nh);
}

class _CropArgs {
  final Uint8List bytes;
  final List<CropPage> pages;
  const _CropArgs(this.bytes, this.pages);
}

Future<Uint8List> _crop(_CropArgs args) async {
  final src = PdfDocument(inputBytes: args.bytes);
  final out = PdfDocument();
  out.pageSettings.margins.all = 0;
  final map = {for (final p in args.pages) p.pageIndex: p};
  for (var i = 0; i < src.pages.count; i++) {
    final crop = map[i];
    if (crop == null) {
      _appendPage(out, src.pages[i], 0);
      continue;
    }
    final size = src.pages[i].size;
    final cw = crop.nw * size.width;
    final ch = crop.nh * size.height;
    final cx = crop.nx * size.width;
    final cy = crop.ny * size.height;
    out.pageSettings.orientation =
        cw > ch ? PdfPageOrientation.landscape : PdfPageOrientation.portrait;
    out.pageSettings.size = Size(cw, ch);
    out.pageSettings.rotate = PdfPageRotateAngle.rotateAngle0;
    final page = out.pages.add();
    // Shift the full-page template up-left so the crop region lands at the
    // origin; content outside the smaller page is clipped away.
    page.graphics
        .drawPdfTemplate(src.pages[i].createTemplate(), Offset(-cx, -cy), size);
  }
  src.dispose();
  final result = Uint8List.fromList(await out.save());
  out.dispose();
  return result;
}

int _pageCount(Uint8List bytes) {
  final doc = PdfDocument(inputBytes: bytes);
  final count = doc.pages.count;
  doc.dispose();
  return count;
}

Future<Uint8List> _merge(List<Uint8List> inputs) async {
  final out = PdfDocument();
  out.pageSettings.margins.all = 0;
  for (final bytes in inputs) {
    final src = PdfDocument(inputBytes: bytes);
    for (int i = 0; i < src.pages.count; i++) {
      _appendPage(out, src.pages[i], 0);
    }
    src.dispose();
  }
  final result = Uint8List.fromList(await out.save());
  out.dispose();
  return result;
}

Future<Uint8List> _rebuild(_RebuildArgs args) async {
  final src = PdfDocument(inputBytes: args.source);
  final out = PdfDocument();
  out.pageSettings.margins.all = 0;
  for (final e in args.edits) {
    _appendPage(out, src.pages[e[0]], e[1]);
  }
  src.dispose();
  final result = Uint8List.fromList(await out.save());
  out.dispose();
  return result;
}

/// Copies [src] onto a new page of [out] as a template, carrying over the
/// source page's own /Rotate plus [extraTurns] user rotation.
void _appendPage(PdfDocument out, PdfPage src, int extraTurns) {
  final size = src.size;
  out.pageSettings.orientation = size.width > size.height
      ? PdfPageOrientation.landscape
      : PdfPageOrientation.portrait;
  out.pageSettings.size = size;
  final turns = (_turnsOf(src.rotation) + extraTurns) % 4;
  out.pageSettings.rotate = _angleOf(turns);
  final page = out.pages.add();
  page.graphics.drawPdfTemplate(src.createTemplate(), Offset.zero, size);
}

int _turnsOf(PdfPageRotateAngle angle) {
  switch (angle) {
    case PdfPageRotateAngle.rotateAngle0:
      return 0;
    case PdfPageRotateAngle.rotateAngle90:
      return 1;
    case PdfPageRotateAngle.rotateAngle180:
      return 2;
    case PdfPageRotateAngle.rotateAngle270:
      return 3;
  }
}

PdfPageRotateAngle _angleOf(int turns) {
  switch (turns % 4) {
    case 1:
      return PdfPageRotateAngle.rotateAngle90;
    case 2:
      return PdfPageRotateAngle.rotateAngle180;
    case 3:
      return PdfPageRotateAngle.rotateAngle270;
    default:
      return PdfPageRotateAngle.rotateAngle0;
  }
}
