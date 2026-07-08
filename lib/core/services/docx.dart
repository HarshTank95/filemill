import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A styled run of text inside a paragraph.
class DocRun {
  final String text; // may contain '\t' for tab stops
  final bool bold, italic, underline;
  final int halfPt; // font size in half-points (Word unit): 11pt -> 22
  const DocRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.halfPt = 22,
  });
}

/// One reconstructed paragraph.
class DocParagraph {
  final List<DocRun> runs;
  final int heading; // 0 = body, 1..3 = heading level
  final String align; // left | center | right | both
  final bool bullet;
  const DocParagraph(
    this.runs, {
    this.heading = 0,
    this.align = 'left',
    this.bullet = false,
  });
}

/// Generates a minimal-but-valid Word .docx (OOXML) from paragraphs. Pure
/// Dart — the file is a ZIP of a few XML parts, built with `archive`.
class DocxBuilder {
  DocxBuilder._();

  static Uint8List build(List<DocParagraph> paragraphs) {
    final body = StringBuffer();
    for (final p in paragraphs) {
      body.write(_paragraph(p));
    }
    body.write(_sectPr);

    final document =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>$body</w:body></w:document>';

    final archive = Archive();
    void add(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    add('[Content_Types].xml', _contentTypes);
    add('_rels/.rels', _rootRels);
    add('word/_rels/document.xml.rels', _docRels);
    add('word/styles.xml', _stylesXml);
    add('word/document.xml', document);
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static String _paragraph(DocParagraph p) {
    final pPr = StringBuffer('<w:pPr>');
    if (p.heading > 0) {
      pPr.write('<w:pStyle w:val="Heading${p.heading.clamp(1, 3)}"/>');
    }
    if (p.align != 'left') pPr.write('<w:jc w:val="${p.align}"/>');
    if (p.bullet) pPr.write('<w:ind w:left="360" w:hanging="360"/>');
    pPr.write('</w:pPr>');

    final runs = StringBuffer();
    if (p.bullet) {
      runs.write('<w:r><w:t xml:space="preserve">•  </w:t></w:r>');
    }
    for (final r in p.runs) {
      runs.write(_run(r));
    }
    return '<w:p>$pPr$runs</w:p>';
  }

  static String _run(DocRun r) {
    final rPr = StringBuffer('<w:rPr>');
    if (r.bold) rPr.write('<w:b/>');
    if (r.italic) rPr.write('<w:i/>');
    if (r.underline) rPr.write('<w:u w:val="single"/>');
    rPr.write('<w:sz w:val="${r.halfPt}"/><w:szCs w:val="${r.halfPt}"/></w:rPr>');

    // Tabs become real Word tab stops.
    final parts = r.text.split('\t');
    final content = StringBuffer();
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) content.write('<w:tab/>');
      content.write('<w:t xml:space="preserve">${_esc(parts[i])}</w:t>');
    }
    return '<w:r>$rPr$content</w:r>';
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

  static const _contentTypes =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '</Types>';

  static const _rootRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>';

  static const _docRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '</Relationships>';

  static const _stylesXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/>'
      '<w:pPr><w:spacing w:after="120"/></w:pPr>'
      '<w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/></w:rPr></w:style>'
      '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/>'
      '<w:pPr><w:spacing w:before="240" w:after="120"/><w:outlineLvl w:val="0"/></w:pPr>'
      '<w:rPr><w:b/><w:sz w:val="32"/></w:rPr></w:style>'
      '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/>'
      '<w:pPr><w:spacing w:before="200" w:after="100"/><w:outlineLvl w:val="1"/></w:pPr>'
      '<w:rPr><w:b/><w:sz w:val="28"/></w:rPr></w:style>'
      '<w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/>'
      '<w:pPr><w:spacing w:before="160" w:after="80"/><w:outlineLvl w:val="2"/></w:pPr>'
      '<w:rPr><w:b/><w:sz w:val="24"/></w:rPr></w:style>'
      '</w:styles>';

  static const _sectPr =
      '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
      '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/></w:sectPr>';
}
