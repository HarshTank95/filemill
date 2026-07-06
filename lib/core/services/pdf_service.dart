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
