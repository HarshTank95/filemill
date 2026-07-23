import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// What a finding means for the user, in plain severity terms.
enum MetaSeverity { critical, moderate }

class MetaFinding {
  final MetaSeverity severity;
  final String label; // "Location", "Author", "Device", ...
  final String value; // human-readable value
  final String detail; // why it matters
  const MetaFinding(this.severity, this.label, this.value, this.detail);
}

class MetaReport {
  final String kind; // "JPEG photo", "PDF document", ...
  final List<MetaFinding> findings;
  final bool cleanable;
  final String? cleanNote; // format-specific consequence of cleaning
  const MetaReport(this.kind, this.findings, this.cleanable, this.cleanNote);

  int get critical =>
      findings.where((f) => f.severity == MetaSeverity.critical).length;
  int get moderate =>
      findings.where((f) => f.severity == MetaSeverity.moderate).length;
}

/// Inspects and scrubs hidden metadata — fully offline, and verified at the
/// raw-byte level: cleaning is rebuilding/stripping, never just blanking
/// API fields (which provably leaves the old strings in the file).
class MetadataService {
  MetadataService._();

  static Future<MetaReport> inspect(Uint8List bytes) =>
      compute(_inspect, bytes);

  static Future<Uint8List> clean(Uint8List bytes) => compute(_clean, bytes);
}

// ---------------------------------------------------------------------------
// Format detection
// ---------------------------------------------------------------------------

enum _Kind { jpeg, png, pdf, ooxml, unknown }

_Kind _detect(Uint8List b) {
  if (b.length < 8) return _Kind.unknown;
  if (b[0] == 0xFF && b[1] == 0xD8) return _Kind.jpeg;
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    return _Kind.png;
  }
  if (b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46) {
    return _Kind.pdf;
  }
  if (b[0] == 0x50 && b[1] == 0x4B) return _Kind.ooxml;
  return _Kind.unknown;
}

MetaReport _inspect(Uint8List bytes) {
  switch (_detect(bytes)) {
    case _Kind.jpeg:
      return _inspectJpeg(bytes);
    case _Kind.png:
      return _inspectPng(bytes);
    case _Kind.pdf:
      return _inspectPdf(bytes);
    case _Kind.ooxml:
      return _inspectOoxml(bytes);
    case _Kind.unknown:
      return const MetaReport('Unsupported file', [], false, null);
  }
}

Uint8List _clean(Uint8List bytes) {
  switch (_detect(bytes)) {
    case _Kind.jpeg:
      return _cleanJpeg(bytes);
    case _Kind.png:
      return _cleanPng(bytes);
    case _Kind.pdf:
      return _cleanPdf(bytes);
    case _Kind.ooxml:
      return _cleanOoxml(bytes);
    case _Kind.unknown:
      throw Exception('Unsupported file format');
  }
}

bool _rawContains(Uint8List bytes, String needle) {
  final n = needle.codeUnits;
  outer:
  for (var i = 0; i <= bytes.length - n.length; i++) {
    for (var j = 0; j < n.length; j++) {
      if (bytes[i + j] != n[j]) continue outer;
    }
    return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// JPEG — lossless segment strip (compressed pixels copied byte-identical)
// ---------------------------------------------------------------------------

List<(int marker, int start, int length)> _jpegSegments(Uint8List b) {
  final out = <(int, int, int)>[];
  var i = 2;
  while (i + 4 <= b.length) {
    if (b[i] != 0xFF) break;
    final marker = b[i + 1];
    if (marker == 0xD9) break;
    if (marker == 0xDA) {
      out.add((marker, i, b.length - i)); // scan data to EOF
      break;
    }
    final len = (b[i + 2] << 8) | b[i + 3];
    out.add((marker, i, len + 2));
    i += len + 2;
  }
  return out;
}

/// Reads the EXIF Orientation tag (0x0112) straight from the APP1 TIFF —
/// independent of any library's tag-name mapping.
int? _jpegOrientation(Uint8List b) {
  for (final (marker, start, length) in _jpegSegments(b)) {
    if (marker != 0xE1 || length < 20) continue;
    // APP1 payload begins after FF E1 LL LL
    final p = start + 4;
    if (b[p] != 0x45 || b[p + 1] != 0x78 || b[p + 2] != 0x69 ||
        b[p + 3] != 0x66) {
      continue; // not "Exif"
    }
    final tiff = p + 6;
    final little = b[tiff] == 0x49;
    int r16(int o) =>
        little ? b[o] | (b[o + 1] << 8) : (b[o] << 8) | b[o + 1];
    int r32(int o) => little
        ? b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)
        : (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
    final ifd = tiff + r32(tiff + 4);
    if (ifd + 2 > b.length) return null;
    final count = r16(ifd);
    for (var e = 0; e < count; e++) {
      final entry = ifd + 2 + e * 12;
      if (entry + 12 > b.length) return null;
      if (r16(entry) == 0x0112) return r16(entry + 8);
    }
    return null;
  }
  return null;
}

/// Minimal APP1 holding ONLY the orientation tag — keeps rotated photos
/// displaying correctly with zero personal data and zero re-encoding.
Uint8List _orientationApp1(int orientation) {
  final tiff = <int>[
    0x49, 0x49, 0x2A, 0x00, 8, 0, 0, 0, // II, 42, IFD0 @ 8
    1, 0, // one entry
    0x12, 0x01, 3, 0, 1, 0, 0, 0, orientation, 0, 0, 0,
    0, 0, 0, 0, // no next IFD
  ];
  final payload = [...'Exif'.codeUnits, 0, 0, ...tiff];
  final len = payload.length + 2;
  return Uint8List.fromList([0xFF, 0xE1, len >> 8, len & 0xFF, ...payload]);
}

MetaReport _inspectJpeg(Uint8List bytes) {
  final findings = <MetaFinding>[];
  img.Image? decoded;
  try {
    decoded = img.decodeJpg(bytes);
  } catch (_) {}
  final exif = decoded?.exif;

  String? s(dynamic v) {
    final t = v?.toString().trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  if (exif != null) {
    // Location — the big one.
    if (exif.gpsIfd.keys.where((k) => k != 0).isNotEmpty) {
      var where = 'GPS coordinates are embedded';
      try {
        final lat = exif.gpsIfd.data[2], lon = exif.gpsIfd.data[4];
        final latR = exif.gpsIfd.data[1], lonR = exif.gpsIfd.data[3];
        if (lat != null && lon != null) {
          double deg(dynamic v) {
            final parts = v.toString().split(RegExp(r'[,\[\]]'))
              ..removeWhere((x) => x.trim().isEmpty);
            double rat(String x) {
              final f = x.split('/');
              return f.length == 2
                  ? double.parse(f[0]) / double.parse(f[1])
                  : double.parse(x);
            }
            return rat(parts[0]) + rat(parts[1]) / 60 + rat(parts[2]) / 3600;
          }
          where =
              '${deg(lat).toStringAsFixed(5)}° ${s(latR) ?? ''}, '
              '${deg(lon).toStringAsFixed(5)}° ${s(lonR) ?? ''}';
        }
      } catch (_) {}
      findings.add(MetaFinding(MetaSeverity.critical, 'Location', where,
          'This photo reveals where it was taken.'));
    }
    final artist = s(exif.imageIfd.data[315]);
    if (artist != null) {
      findings.add(MetaFinding(MetaSeverity.critical, 'Artist', artist,
          'A name is embedded in the photo.'));
    }
    final copyright = s(exif.imageIfd.data[33432]);
    if (copyright != null) {
      findings.add(MetaFinding(MetaSeverity.critical, 'Copyright', copyright,
          'A name/owner is embedded in the photo.'));
    }
    final make = s(exif.imageIfd['Make']), model = s(exif.imageIfd['Model']);
    if (make != null || model != null) {
      findings.add(MetaFinding(
          MetaSeverity.moderate,
          'Device',
          [make, model].whereType<String>().join(' '),
          'Identifies the exact camera or phone used.'));
    }
    final software = s(exif.imageIfd.data[305]);
    if (software != null) {
      findings.add(MetaFinding(MetaSeverity.moderate, 'Software', software,
          'Identifies the editing software used.'));
    }
    final lens = s(exif.exifIfd['LensModel']);
    if (lens != null) {
      findings.add(MetaFinding(MetaSeverity.moderate, 'Lens', lens,
          'Identifies the lens used.'));
    }
    final shot = s(exif.exifIfd['DateTimeOriginal']) ??
        s(exif.imageIfd['DateTime']);
    if (shot != null) {
      findings.add(MetaFinding(MetaSeverity.moderate, 'Capture time', shot,
          'The exact moment the photo was taken, to the second.'));
    }
  }

  // Segment-level extras the decoder does not surface.
  for (final (marker, start, length) in _jpegSegments(bytes)) {
    if (marker == 0xE1 && length > 10) {
      final head = String.fromCharCodes(
          bytes.sublist(start + 4, (start + 40).clamp(0, bytes.length)));
      if (head.contains('http://ns.adobe.com/xap')) {
        findings.add(const MetaFinding(MetaSeverity.moderate, 'XMP data',
            'Editing metadata block', 'Can contain tool and history info.'));
      }
    } else if (marker == 0xED) {
      findings.add(const MetaFinding(MetaSeverity.moderate, 'IPTC data',
          'Photoshop metadata block', 'Can contain captions and credits.'));
    } else if (marker == 0xFE) {
      findings.add(const MetaFinding(MetaSeverity.moderate, 'Comment',
          'Embedded text comment', 'Free-text left inside the file.'));
    }
  }

  final oriented = (_jpegOrientation(bytes) ?? 1) != 1;
  return MetaReport(
    'JPEG photo',
    findings,
    true,
    'Cleaning is lossless — the picture data is copied byte-for-byte.'
    '${oriented ? ' The rotation flag is preserved (it contains no personal data).' : ''}',
  );
}

Uint8List _cleanJpeg(Uint8List bytes) {
  final orientation = _jpegOrientation(bytes);
  final keep = BytesBuilder();
  keep.add(const [0xFF, 0xD8]);
  if (orientation != null && orientation != 1) {
    keep.add(_orientationApp1(orientation));
  }
  for (final (marker, start, length) in _jpegSegments(bytes)) {
    // Drop APP1 (EXIF/XMP incl. embedded thumbnail), APP13 (IPTC), COM.
    if (marker == 0xE1 || marker == 0xED || marker == 0xFE) continue;
    keep.add(Uint8List.sublistView(bytes, start, start + length));
  }
  return keep.toBytes();
}

// ---------------------------------------------------------------------------
// PNG — chunk filter
// ---------------------------------------------------------------------------

MetaReport _inspectPng(Uint8List bytes) {
  final findings = <MetaFinding>[];
  try {
    final decoded = img.decodePng(bytes);
    final text = decoded?.textData;
    if (text != null) {
      for (final e in text.entries) {
        final identity = ['author', 'artist', 'copyright']
            .contains(e.key.toLowerCase());
        findings.add(MetaFinding(
            identity ? MetaSeverity.critical : MetaSeverity.moderate,
            e.key,
            e.value,
            identity
                ? 'A name is embedded in the image.'
                : 'Text metadata embedded in the image.'));
      }
    }
  } catch (_) {}
  // Chunk-level scan for time and EXIF chunks.
  var i = 8;
  while (i + 12 <= bytes.length) {
    final len = (bytes[i] << 24) |
        (bytes[i + 1] << 16) |
        (bytes[i + 2] << 8) |
        bytes[i + 3];
    final type = String.fromCharCodes(bytes.sublist(i + 4, i + 8));
    if (type == 'tIME') {
      findings.add(const MetaFinding(MetaSeverity.moderate, 'Modified time',
          'Last-modified timestamp chunk', 'When the image was last edited.'));
    } else if (type == 'eXIf') {
      findings.add(const MetaFinding(MetaSeverity.critical, 'EXIF block',
          'Camera metadata chunk', 'Can contain location and device data.'));
    }
    i += len + 12;
  }
  return MetaReport('PNG image', findings, true,
      'Cleaning is lossless — pixel data chunks are untouched.');
}

Uint8List _cleanPng(Uint8List bytes) {
  final out = BytesBuilder()..add(bytes.sublist(0, 8));
  var i = 8;
  while (i + 12 <= bytes.length) {
    final len = (bytes[i] << 24) |
        (bytes[i + 1] << 16) |
        (bytes[i + 2] << 8) |
        bytes[i + 3];
    final type = String.fromCharCodes(bytes.sublist(i + 4, i + 8));
    if (!const ['tEXt', 'iTXt', 'zTXt', 'tIME', 'eXIf'].contains(type)) {
      out.add(bytes.sublist(i, i + len + 12));
    }
    i += len + 12;
  }
  return out.toBytes();
}

// ---------------------------------------------------------------------------
// PDF — full template rebuild (verified: blanking fields leaves the old
// strings recoverable in the raw bytes; a rebuild does not)
// ---------------------------------------------------------------------------

MetaReport _inspectPdf(Uint8List bytes) {
  final findings = <MetaFinding>[];
  try {
    final doc = PdfDocument(inputBytes: bytes);
    final i = doc.documentInformation;
    void f(String label, String value, MetaSeverity sev, String detail) {
      if (value.trim().isNotEmpty) {
        findings.add(MetaFinding(sev, label, value.trim(), detail));
      }
    }

    f('Author', i.author, MetaSeverity.critical,
        'A name is embedded in the document.');
    f('Title', i.title, MetaSeverity.moderate,
        'Internal title, often the original filename.');
    f('Subject', i.subject, MetaSeverity.moderate,
        'Describes the document\'s purpose.');
    f('Keywords', i.keywords, MetaSeverity.moderate,
        'Tags left by the creating tool.');
    f('Made with', i.creator, MetaSeverity.moderate,
        'Identifies the software that created the document.');
    f('Processed by', i.producer, MetaSeverity.moderate,
        'Identifies the software pipeline that produced the file.');
    // Date keys: check raw presence — the getters fabricate "now" if absent.
    if (_rawContains(bytes, '/CreationDate')) {
      findings.add(MetaFinding(MetaSeverity.moderate, 'Created',
          i.creationDate.toString().split('.').first,
          'When the document was created.'));
    }
    if (_rawContains(bytes, '/ModDate')) {
      findings.add(MetaFinding(MetaSeverity.moderate, 'Modified',
          i.modificationDate.toString().split('.').first,
          'When the document was last changed.'));
    }
    if (_rawContains(bytes, 'xpacket')) {
      findings.add(const MetaFinding(MetaSeverity.moderate, 'XMP data',
          'Extended metadata stream',
          'Can duplicate identity and history info.'));
    }
    if (doc.attachments.count > 0) {
      findings.add(MetaFinding(MetaSeverity.critical, 'Attachments',
          '${doc.attachments.count} embedded file(s)',
          'Whole files are embedded inside this PDF.'));
    }
    var annotations = 0;
    for (var p = 0; p < doc.pages.count; p++) {
      annotations += doc.pages[p].annotations.count;
    }
    if (annotations > 0) {
      findings.add(MetaFinding(MetaSeverity.moderate, 'Annotations',
          '$annotations comment/markup object(s)',
          'Comments can carry reviewer names and notes.'));
    }
    doc.dispose();
  } catch (_) {
    return const MetaReport(
        'PDF document (locked)', [], false,
        'Unlock the PDF first to inspect it.');
  }
  return MetaReport(
      'PDF document',
      findings,
      true,
      'Cleaning fully rebuilds the file: metadata, hidden history and '
      'attachments are gone; interactive form fields become flat content.');
}

Uint8List _cleanPdf(Uint8List bytes) {
  final src = PdfDocument(inputBytes: bytes);
  final dst = PdfDocument();
  dst.pageSettings.margins.all = 0;
  for (var i = 0; i < src.pages.count; i++) {
    final page = src.pages[i];
    dst.pageSettings.size = page.size;
    dst.pages.add().graphics.drawPdfTemplate(page.createTemplate(), Offset.zero);
  }
  final out = Uint8List.fromList(dst.saveSync());
  src.dispose();
  dst.dispose();
  return out;
}

// ---------------------------------------------------------------------------
// OOXML (docx / xlsx / pptx) — docProps surgery, content untouched
// ---------------------------------------------------------------------------

String? _xmlTag(String xml, String tag) {
  final m = RegExp('<$tag[^>]*>(.*?)</$tag>', dotAll: true).firstMatch(xml);
  final v = m?.group(1).toString().trim();
  return (v == null || v.isEmpty)
      ? null
      : v
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&amp;', '&');
}

MetaReport _inspectOoxml(Uint8List bytes) {
  Archive arch;
  try {
    arch = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return const MetaReport('Unsupported file', [], false, null);
  }
  final names = arch.files.map((f) => f.name).toSet();
  final String kind;
  if (names.contains('word/document.xml')) {
    kind = 'Word document';
  } else if (names.contains('xl/workbook.xml')) {
    kind = 'Excel workbook';
  } else if (names.contains('ppt/presentation.xml')) {
    kind = 'PowerPoint presentation';
  } else {
    return const MetaReport('Unsupported file', [], false, null);
  }

  final findings = <MetaFinding>[];
  String part(String name) {
    final f = arch.files.where((f) => f.name == name);
    return f.isEmpty ? '' : String.fromCharCodes(f.first.content as List<int>);
  }

  final core = part('docProps/core.xml');
  void f(String tag, String label, MetaSeverity sev, String detail) {
    final v = _xmlTag(core, tag);
    if (v != null) findings.add(MetaFinding(sev, label, v, detail));
  }

  f('dc:creator', 'Author', MetaSeverity.critical,
      'The document creator\'s name.');
  f('cp:lastModifiedBy', 'Last modified by', MetaSeverity.critical,
      'The name of the last editor.');
  f('dc:title', 'Title', MetaSeverity.moderate, 'Internal document title.');
  f('dc:subject', 'Subject', MetaSeverity.moderate, 'Internal subject.');
  f('cp:revision', 'Revisions', MetaSeverity.moderate,
      'How many times the document was saved.');
  f('dcterms:created', 'Created', MetaSeverity.moderate,
      'When the document was created.');
  f('dcterms:modified', 'Modified', MetaSeverity.moderate,
      'When the document was last changed.');

  final app = part('docProps/app.xml');
  final company = _xmlTag(app, 'Company');
  if (company != null) {
    findings.add(MetaFinding(MetaSeverity.critical, 'Company', company,
        'The organisation name is embedded.'));
  }
  final application = _xmlTag(app, 'Application');
  if (application != null) {
    findings.add(MetaFinding(MetaSeverity.moderate, 'Made with', application,
        'Identifies the software used.'));
  }
  final totalTime = _xmlTag(app, 'TotalTime');
  if (totalTime != null) {
    findings.add(MetaFinding(MetaSeverity.moderate, 'Editing time',
        '$totalTime minute(s)', 'Total time spent editing.'));
  }
  if (names.contains('docProps/custom.xml')) {
    findings.add(const MetaFinding(MetaSeverity.moderate, 'Custom properties',
        'Extra property block', 'Tool- or company-specific fields.'));
  }
  return MetaReport(kind, findings, true,
      'Cleaning replaces the property parts only — the content is untouched.');
}

const _emptyCoreXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<cp:coreProperties '
    'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
    'xmlns:dc="http://purl.org/dc/elements/1.1/" '
    'xmlns:dcterms="http://purl.org/dc/terms/" '
    'xmlns:dcmitype="http://purl.org/dc/dcmitype/" '
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"/>';

Uint8List _cleanOoxml(Uint8List bytes) {
  final arch = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in arch.files) {
    if (!f.isFile) continue;
    if (f.name == 'docProps/custom.xml') continue; // dropped entirely
    if (f.name == 'docProps/core.xml') {
      final data = _emptyCoreXml.codeUnits;
      out.addFile(ArchiveFile('docProps/core.xml', data.length, data));
      continue;
    }
    if (f.name == 'docProps/app.xml') {
      var app = String.fromCharCodes(f.content as List<int>);
      for (final tag in ['Company', 'Manager', 'Application', 'TotalTime']) {
        app = app.replaceAll(
            RegExp('<$tag[^>]*>.*?</$tag>', dotAll: true), '<$tag></$tag>');
      }
      final data = app.codeUnits;
      out.addFile(ArchiveFile('docProps/app.xml', data.length, data));
      continue;
    }
    out.addFile(ArchiveFile(f.name, f.size, f.content));
  }
  return Uint8List.fromList(ZipEncoder().encode(out));
}
