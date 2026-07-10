import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'ocr_service.dart';
import 'scan_processor.dart';

/// A captured card side with known pixel dimensions (so the UI can show it
/// at its real aspect and the composer can pick the box orientation).
class SideImage {
  final Uint8List bytes;
  final int width, height;
  const SideImage(this.bytes, this.width, this.height);
  double get aspect => width / height;
  bool get isPortrait => height > width;
}

/// ID card composer: styles each captured side (scan filter + privacy
/// masks burned into the pixels) and lays front/back out on an A4 page at
/// the card's TRUE physical size (ISO ID-1, 85.6 × 54 mm) so a print is a
/// legally usable photocopy. Everything runs in isolates, fully offline.
class IdCardService {
  IdCardService._();

  /// ISO ID-1 (Aadhaar PVC, PAN, driving licence, credit cards).
  static const cardWidthMm = 85.6;
  static const cardHeightMm = 54.0;

  /// Bakes orientation and auto-rotates a portrait capture to landscape
  /// (ID-1 cards are landscape; phones are usually held upright). A wrong
  /// guess is one tap away from correct via [rotateSide].
  static Future<SideImage> normalizeSide(Uint8List jpeg) =>
      compute(_normalize, jpeg);

  /// Rotates a side 90° clockwise.
  static Future<SideImage> rotateSide(Uint8List jpeg) =>
      compute(_rotate, jpeg);

  /// Small copies of the capture at 0/90/180/270° — OCR each and the one
  /// that reads best is upright (works for landscape cards photographed
  /// sideways AND genuinely vertical cards like Voter IDs).
  static Future<List<SideImage>> orientationCandidates(Uint8List jpeg) =>
      compute(_candidates, jpeg);

  /// Applies the winning rotation to the full-resolution capture.
  static Future<SideImage> applyRotation(Uint8List jpeg, int angle) =>
      compute(_applyRotation, _RotateArgs(jpeg, angle));

  /// How much readable text a rotation produced: total length of plausible
  /// words (3+ alphanumeric chars). Garbage from sideways OCR scores low.
  static int textScore(List<String> lines) {
    var score = 0;
    for (final line in lines) {
      for (final word in line.split(RegExp(r'\s+'))) {
        final clean = word.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
        if (clean.length >= 3) score += clean.length;
      }
    }
    return score;
  }

  /// Finds Aadhaar numbers (XXXX XXXX XXXX) in OCR output and returns
  /// normalized mask rects covering the FIRST 8 digits — exactly what UIDAI
  /// recommends hiding. A 16-digit VID is recognized and left alone.
  static List<Rect> aadhaarMasks(
      List<OcrScanLine> lines, double imageW, double imageH) {
    if (imageW <= 0 || imageH <= 0) return const [];
    final group = RegExp(r'^\d{4}$');
    bool isGroup(OcrWord w) => group.hasMatch(w.text.trim());
    final out = <Rect>[];
    for (final line in lines) {
      final ws = line.words;
      for (var i = 0; i + 2 < ws.length; i++) {
        if (!isGroup(ws[i]) || !isGroup(ws[i + 1]) || !isGroup(ws[i + 2])) {
          continue;
        }
        // Part of a longer digit run (VID etc.) → not an Aadhaar number.
        if (i > 0 && isGroup(ws[i - 1])) continue;
        if (i + 3 < ws.length && isGroup(ws[i + 3])) continue;
        final box = ws[i].box.expandToInclude(ws[i + 1].box);
        final pad = box.height * 0.18;
        out.add(Rect.fromLTRB(
          ((box.left - pad) / imageW).clamp(0.0, 1.0),
          ((box.top - pad) / imageH).clamp(0.0, 1.0),
          ((box.right + pad) / imageW).clamp(0.0, 1.0),
          ((box.bottom + pad) / imageH).clamp(0.0, 1.0),
        ));
        i += 2;
      }
    }
    return out;
  }

  /// Applies [filter] and burns [masks] (normalized rects) into a side.
  /// Masks are burned into pixels — the covered data is unrecoverable.
  static Future<Uint8List> finalizeSide(
    Uint8List jpeg,
    ScanFilter filter,
    List<Rect> masks, {
    int maxDim = 0,
  }) =>
      compute(_finalize, _FinalizeArgs(jpeg, filter, masks, maxDim));

  /// Lays the finalized sides (1 or 2) onto a single A4 PDF page, each at
  /// true card size in whichever orientation the image actually is.
  static Future<Uint8List> compose(List<Uint8List> sides) =>
      compute(_compose, sides);
}

SideImage _normalize(Uint8List jpeg) {
  final decoded = img.decodeImage(jpeg);
  if (decoded == null) throw Exception('Unsupported image format');
  var image = img.bakeOrientation(decoded);
  if (image.height > image.width) {
    image = img.copyRotate(image, angle: 90);
  }
  return SideImage(Uint8List.fromList(img.encodeJpg(image, quality: 92)),
      image.width, image.height);
}

SideImage _rotate(Uint8List jpeg) {
  final decoded = img.decodeImage(jpeg);
  if (decoded == null) throw Exception('Unsupported image format');
  final image = img.copyRotate(img.bakeOrientation(decoded), angle: 90);
  return SideImage(Uint8List.fromList(img.encodeJpg(image, quality: 92)),
      image.width, image.height);
}

class _RotateArgs {
  final Uint8List bytes;
  final int angle;
  const _RotateArgs(this.bytes, this.angle);
}

SideImage _applyRotation(_RotateArgs args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) throw Exception('Unsupported image format');
  var image = img.bakeOrientation(decoded);
  if (args.angle % 360 != 0) {
    image = img.copyRotate(image, angle: args.angle);
  }
  return SideImage(Uint8List.fromList(img.encodeJpg(image, quality: 92)),
      image.width, image.height);
}

List<SideImage> _candidates(Uint8List jpeg) {
  final decoded = img.decodeImage(jpeg);
  if (decoded == null) throw Exception('Unsupported image format');
  var base = img.bakeOrientation(decoded);
  const maxDim = 900;
  if (base.width > maxDim || base.height > maxDim) {
    base = base.width >= base.height
        ? img.copyResize(base, width: maxDim)
        : img.copyResize(base, height: maxDim);
  }
  final out = <SideImage>[];
  for (final angle in const [0, 90, 180, 270]) {
    final r = angle == 0 ? base : img.copyRotate(base, angle: angle);
    out.add(SideImage(Uint8List.fromList(img.encodeJpg(r, quality: 85)),
        r.width, r.height));
  }
  return out;
}

class _FinalizeArgs {
  final Uint8List bytes;
  final ScanFilter filter;
  final List<Rect> masks;
  final int maxDim;
  const _FinalizeArgs(this.bytes, this.filter, this.masks, this.maxDim);
}

Uint8List _finalize(_FinalizeArgs args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) throw Exception('Unsupported image format');
  var image = img.bakeOrientation(decoded);
  if (args.maxDim > 0 &&
      (image.width > args.maxDim || image.height > args.maxDim)) {
    image = image.width >= image.height
        ? img.copyResize(image, width: args.maxDim)
        : img.copyResize(image, height: args.maxDim);
  }
  final w = image.width, h = image.height;
  final rgb = image.getBytes(order: img.ChannelOrder.rgb);
  applyScanFilter(rgb, w, h, args.filter);

  // Burn the privacy masks — solid black, straight into the pixels.
  for (final m in args.masks) {
    final x0 = (m.left * w).round().clamp(0, w);
    final x1 = (m.right * w).round().clamp(0, w);
    final y0 = (m.top * h).round().clamp(0, h);
    final y1 = (m.bottom * h).round().clamp(0, h);
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final i = (y * w + x) * 3;
        rgb[i] = 0;
        rgb[i + 1] = 0;
        rgb[i + 2] = 0;
      }
    }
  }

  final out = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: rgb.buffer,
    order: img.ChannelOrder.rgb,
  );
  return Uint8List.fromList(img.encodeJpg(out, quality: 92));
}

Future<Uint8List> _compose(List<Uint8List> sides) async {
  final doc = pw.Document();
  const mm = PdfPageFormat.mm;

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.only(top: 30 * mm),
      build: (_) => pw.Align(
        alignment: pw.Alignment.topCenter,
        child: pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            for (var i = 0; i < sides.length; i++) ...[
              if (i > 0) pw.SizedBox(height: 12 * mm),
              _card(sides[i]),
            ],
          ],
        ),
      ),
    ),
  );
  return doc.save();
}

/// One card at true ID-1 size; the 85.6 × 54 mm box follows the image's
/// own orientation so nothing is ever stretched sideways.
pw.Widget _card(Uint8List jpeg) {
  const mm = PdfPageFormat.mm;
  final image = pw.MemoryImage(jpeg);
  final portrait = (image.height ?? 0) > (image.width ?? 1);
  final w = (portrait ? IdCardService.cardHeightMm : IdCardService.cardWidthMm) * mm;
  final h = (portrait ? IdCardService.cardWidthMm : IdCardService.cardHeightMm) * mm;
  return pw.Container(
    width: w,
    height: h,
    decoration: pw.BoxDecoration(
      borderRadius: pw.BorderRadius.circular(2.5 * mm),
      border: pw.Border.all(
        color: const PdfColor.fromInt(0xFFBDBDBD),
        width: 0.4,
      ),
    ),
    child: pw.ClipRRect(
      horizontalRadius: 2.5 * mm,
      verticalRadius: 2.5 * mm,
      child: pw.Image(image, fit: pw.BoxFit.fill),
    ),
  );
}
