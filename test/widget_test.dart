import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import 'package:pdf/widgets.dart' as pw;

import 'package:filemill/core/services/docx.dart';
import 'package:filemill/core/services/id_card_service.dart';
import 'package:filemill/core/services/image_convert_service.dart';
import 'package:filemill/core/services/ocr_service.dart';
import 'package:filemill/core/services/pdf_compare_service.dart';
import 'package:filemill/core/services/pdf_service.dart';
import 'package:filemill/core/services/scan_processor.dart';
import 'package:filemill/core/models/tool.dart';
import 'package:filemill/core/services/searchable_service.dart';
import 'package:filemill/features/home/home_screen.dart';
import 'package:filemill/features/shared/page_grid.dart';
import 'package:filemill/features/split_files/split_files_screen.dart';
import 'package:filemill/ui/theme.dart';

void main() {
  testWidgets('Home renders wordmark, search and the first tools',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const HomeScreen(),
    ));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('FileMill'), findsOneWidget);
    expect(find.text('Scan & create'), findsOneWidget);
    expect(find.textContaining('Search'), findsWidgets);
    // First-category tiles render into the initial viewport.
    expect(find.text('Scan → PDF'), findsOneWidget);
    expect(find.text('Images → PDF'), findsOneWidget);
  });

  test('every tool has a category and the toolset is complete', () {
    expect(Tool.values.length, 23);
    for (final t in Tool.values) {
      expect(ToolCategory.values.contains(t.category), isTrue);
    }
    // Categories cover all tools with none empty.
    for (final c in ToolCategory.values) {
      expect(Tool.inCategory(c), isNotEmpty);
    }
    expect(Tool.viewer.matches('read'), isTrue);
    expect(Tool.protect.matches('password'), isTrue);
    expect(Tool.merge.matches('zzz'), isFalse);
  });

  test('id card: masks burn to black and compose yields a true-size A4',
      () async {
    // A white card-shaped image.
    final card = img.Image(width: 320, height: 202);
    img.fill(card, color: img.ColorRgb8(240, 240, 240));
    final jpeg = Uint8List.fromList(img.encodeJpg(card));

    final masked = await IdCardService.finalizeSide(
      jpeg,
      ScanFilter.original,
      [const Rect.fromLTRB(0.25, 0.70, 0.75, 0.85)],
    );
    final out = img.decodeImage(masked)!;
    // Inside the mask: black. Outside: still light.
    final inside = out.getPixel((0.5 * out.width).round(),
        (0.77 * out.height).round());
    final outside = out.getPixel((0.5 * out.width).round(),
        (0.2 * out.height).round());
    expect(inside.r + inside.g + inside.b, lessThan(60));
    expect(outside.r + outside.g + outside.b, greaterThan(600));

    // Front + back on one A4 page.
    final pdf = await IdCardService.compose([masked, masked]);
    final doc = sf.PdfDocument(inputBytes: pdf);
    expect(doc.pages.count, 1);
    expect(doc.pages[0].size.width, closeTo(595, 2)); // A4 portrait, points
    expect(doc.pages[0].size.height, closeTo(842, 2));
    doc.dispose();

    // A portrait capture is auto-rotated to landscape at intake.
    final tall = img.Image(width: 202, height: 320);
    img.fill(tall, color: img.ColorRgb8(240, 240, 240));
    final normalized = await IdCardService.normalizeSide(
        Uint8List.fromList(img.encodeJpg(tall)));
    expect(normalized.width, greaterThan(normalized.height));
    // And a manual rotate turns it back to portrait.
    final rotated = await IdCardService.rotateSide(normalized.bytes);
    expect(rotated.height, greaterThan(rotated.width));
  });

  test('id card: aadhaar auto-mask finds the number, skips VID, scores text',
      () {
    OcrWord w(String t, double x) =>
        OcrWord(t, Rect.fromLTWH(x, 100, 50, 14));
    // A card face: name line, Aadhaar number line, 16-digit VID line.
    final lines = [
      OcrScanLine('Tank Harsh', const Rect.fromLTWH(20, 40, 120, 14),
          [w('Tank', 20), w('Harsh', 80)]),
      OcrScanLine('9081 3820 0368', const Rect.fromLTWH(60, 100, 170, 14),
          [w('9081', 60), w('3820', 120), w('0368', 180)]),
      OcrScanLine(
          'VID : 9134 5678 9012 3456',
          const Rect.fromLTWH(20, 130, 260, 14),
          [
            w('VID', 20),
            w(':', 45),
            w('9134', 60),
            w('5678', 120),
            w('9012', 180),
            w('3456', 240)
          ]),
    ];
    final masks = IdCardService.aadhaarMasks(lines, 320.0, 202.0);
    // Exactly one mask — over the FIRST 8 digits, not the VID, not the name.
    expect(masks.length, 1);
    final m = masks.first;
    expect(m.left, lessThan(60 / 320)); // starts at/before first group
    expect(m.right, greaterThan(170 / 320)); // covers second group
    expect(m.right, lessThan(180 / 320 + 0.02)); // stops before third group
    expect(m.top, closeTo(100 / 202, 0.03));

    // Orientation scoring: real words beat sideways-OCR garbage.
    expect(
        IdCardService.textScore(
            ['Government of India', 'Tank Harsh Pareshkumar']),
        greaterThan(IdCardService.textScore(['|l', 'i)', 'm', '..'])));
  });

  test('compare pdfs: finds the exact planted changes and nothing else',
      () async {
    Future<Uint8List> makePdf(List<String> paragraphs) async {
      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        build: (_) => [for (final p in paragraphs) pw.Paragraph(text: p)],
      ));
      return doc.save();
    }

    final filler = [
      for (var i = 0; i < 30; i++)
        'Clause $i of this agreement continues with standard boilerplate '
            'text that both versions share word for word, entry $i.'
    ];
    final original = await makePdf([
      'This agreement shall remain valid for thirty (30) days from signing.',
      ...filler.take(15),
      'Payment is due within seven days of the invoice date.',
      ...filler.skip(15),
    ]);
    final revised = await makePdf([
      'This agreement shall remain valid for sixty (60) days from signing.',
      'An entirely new arbitration clause applies to all disputes hereunder.',
      ...filler.take(15),
      // payment sentence deleted
      ...filler.skip(15),
    ]);

    final result = await PdfCompareService.compare(original, revised);
    expect(result.pagesA, greaterThan(1)); // insertion shifts across pages
    expect(result.blocks.length, 3,
        reason: result.blocks
            .map((b) => '${b.kind}: "${b.beforeText}" -> "${b.afterText}"')
            .join('\n'));

    final changed =
        result.blocks.firstWhere((b) => b.kind == ChangeKind.changed);
    expect(changed.beforeText, 'thirty (30)');
    expect(changed.afterText, 'sixty (60)');

    final added = result.blocks.firstWhere((b) => b.kind == ChangeKind.added);
    expect(added.afterText, contains('arbitration clause'));
    expect(added.beforeText, isEmpty);

    final removed =
        result.blocks.firstWhere((b) => b.kind == ChangeKind.removed);
    expect(removed.beforeText, contains('Payment is due within seven days'));
    expect(removed.afterText, isEmpty);

    // Identical documents -> zero changes.
    final same = await PdfCompareService.compare(original, original);
    expect(same.identicalText, isTrue);

    // Every changed token carries a real box for the highlight overlays.
    for (final b in result.blocks) {
      for (final t in [...b.before, ...b.after]) {
        expect(t.w, greaterThan(0));
        expect(t.h, greaterThan(0));
      }
    }
  });

  test('scan processor: identity warp keeps size, B&W output is binary',
      () async {
    final src = img.Image(width: 60, height: 40);
    img.fill(src, color: img.ColorRgb8(200, 200, 200));
    img.fillRect(src,
        x1: 10, y1: 10, x2: 30, y2: 25, color: img.ColorRgb8(20, 20, 20));
    final jpg = Uint8List.fromList(img.encodeJpg(src));
    const identity = [
      Offset(0, 0),
      Offset(1, 0),
      Offset(1, 1),
      Offset(0, 1),
    ];

    final out = await ScanProcessor.process(ScanJob(
        bytes: jpg, corners: identity, filter: ScanFilter.original));
    final decoded = img.decodeImage(out)!;
    expect((decoded.width - 60).abs() <= 1, isTrue);
    expect((decoded.height - 40).abs() <= 1, isTrue);

    final bw = await ScanProcessor.process(ScanJob(
        bytes: jpg, corners: identity, filter: ScanFilter.blackWhite));
    final bwDecoded = img.decodeImage(bw)!;
    final p = bwDecoded.getPixel(20, 17); // inside the dark rectangle
    expect(p.r < 64, isTrue);

    final detected = await ScanProcessor.detect(jpg);
    expect(detected.corners.length, 4);
    expect(detected.aspect, closeTo(1.5, 0.01));
  });

  test('protect/unlock round-trip with AES-256', () async {
    final doc = sf.PdfDocument();
    doc.pages.add().graphics.drawString(
        'FileMill', sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 12));
    final plain = Uint8List.fromList(await doc.save());
    doc.dispose();

    expect(await PdfService.isProtected(plain), isFalse);

    final locked = await PdfService.protect(plain, 'secret123');
    expect(await PdfService.isProtected(locked), isTrue);

    await expectLater(
        PdfService.unlock(locked, 'wrong-password'), throwsException);

    final unlocked = await PdfService.unlock(locked, 'secret123');
    expect(await PdfService.isProtected(unlocked), isFalse);
    expect(await PdfService.pageCount(unlocked), 1);
  });

  test('searchable assemble builds a valid PDF with invisible text layer',
      () async {
    final src = img.Image(width: 100, height: 140);
    img.fill(src, color: img.ColorRgb8(255, 255, 255));
    final jpg = Uint8List.fromList(img.encodeJpg(src));
    final bytes = await SearchableService.assemble([
      SearchablePage(
        jpg: jpg,
        widthPt: 100,
        heightPt: 140,
        lines: const [SearchableLine('FileMill test', 0.1, 0.1, 0.6, 0.05)],
      ),
    ]);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(await PdfService.pageCount(bytes), 1);
  });

  test('watermark stamps every page and keeps the document valid', () async {
    final doc = sf.PdfDocument();
    doc.pages.add();
    doc.pages.add();
    final plain = Uint8List.fromList(await doc.save());
    doc.dispose();

    final stamped = await PdfService.watermark(
      plain,
      const WatermarkOptions(
        text: 'CONFIDENTIAL',
        pageNumbers: true,
        numberFormat: PageNumberFormat.pageOfTotal,
      ),
    );
    expect(String.fromCharCodes(stamped.take(5)), '%PDF-');
    expect(await PdfService.pageCount(stamped), 2);
    expect(stamped.length, greaterThan(plain.length));
  });

  test('image convert: png to jpg with downscale', () async {
    final src = img.Image(width: 3000, height: 1500);
    img.fill(src, color: img.ColorRgb8(120, 40, 200));
    final png = Uint8List.fromList(img.encodePng(src));

    final jpg = await ImageConvertService.convert(
      png,
      format: ImageOutFormat.jpg,
      jpgQuality: 80,
      maxDim: 2048,
    );
    final decoded = img.decodeJpg(jpg)!;
    expect(decoded.width, 2048);
    expect(decoded.height, 1024);
  });

  test('redact truly destroys text on flattened pages', () async {
    final doc = sf.PdfDocument();
    doc.pages.add().graphics.drawString(
        'SECRET-9876', sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 14),
        bounds: const Rect.fromLTWH(50, 50, 200, 30));
    doc.pages.add().graphics.drawString(
        'public text', sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 14),
        bounds: const Rect.fromLTWH(50, 50, 200, 30));
    final plain = Uint8List.fromList(await doc.save());
    doc.dispose();

    final white = img.Image(width: 200, height: 280);
    img.fill(white, color: img.ColorRgb8(255, 255, 255));
    final pageJpg = Uint8List.fromList(img.encodeJpg(white));

    final redacted = await PdfService.redact(plain, [
      RedactPage(
        pageIndex: 0,
        jpg: pageJpg,
        widthPt: 595,
        heightPt: 842,
        boxes: const [Rect.fromLTWH(40, 40, 220, 50)],
        labels: const [
          RedactLabel('HIDDEN', Rect.fromLTWH(40, 40, 220, 50), false),
        ],
      ),
    ]);

    final result = sf.PdfDocument(inputBytes: redacted);
    final text = sf.PdfTextExtractor(result).extractText();
    expect(result.pages.count, 2);
    result.dispose();
    // The secret must be GONE from the document, not merely covered.
    expect(text.contains('SECRET-9876'), isFalse);
    expect(text.contains('public text'), isTrue);
    // The label is real vector text drawn on top of the destroyed area.
    expect(text.contains('HIDDEN'), isTrue);
  });

  test('find text locates a term and returns its page + box', () async {
    final doc = sf.PdfDocument();
    doc.pages.add().graphics.drawString(
        'Account 12345 secret',
        sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 14),
        bounds: const Rect.fromLTWH(50, 100, 300, 30));
    final bytes = Uint8List.fromList(await doc.save());
    doc.dispose();

    final matches = await PdfService.findText(bytes, '12345');
    expect(matches, isNotEmpty);
    expect(matches.first.pageIndex, 0);
    expect(matches.first.nx, greaterThan(0));
    expect(matches.first.ny, greaterThan(0));
    expect(matches.first.nw, greaterThan(0));

    expect(await PdfService.findText(bytes, 'notpresent'), isEmpty);
  });

  test('highlight keeps text selectable (no flatten)', () async {
    final doc = sf.PdfDocument();
    doc.pages.add().graphics.drawString(
        'highlight me',
        sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 14),
        bounds: const Rect.fromLTWH(50, 100, 200, 30));
    final plain = Uint8List.fromList(await doc.save());
    doc.dispose();

    final marked = await PdfService.highlight(plain, const [
      HighlightBox(0, Rect.fromLTWH(48, 98, 120, 24), 255, 241, 118),
    ]);
    final result = sf.PdfDocument(inputBytes: marked);
    final text = sf.PdfTextExtractor(result).extractText();
    result.dispose();
    // Non-destructive: the underlying text survives.
    expect(text.contains('highlight me'), isTrue);
  });

  test('add text writes vector text into the page', () async {
    final doc = sf.PdfDocument();
    doc.pages.add();
    final plain = Uint8List.fromList(await doc.save());
    doc.dispose();

    final filled = await PdfService.addText(plain, const [
      TextStamp(
        pageIndex: 0,
        text: 'John Doe',
        x: 60,
        y: 120,
        width: 200,
        fontSize: 14,
        r: 20,
        g: 20,
        b: 20,
      ),
    ]);
    final result = sf.PdfDocument(inputBytes: filled);
    final text = sf.PdfTextExtractor(result).extractText();
    result.dispose();
    expect(text.contains('John Doe'), isTrue);
  });

  test('crop resizes the page to the requested region', () async {
    final doc = sf.PdfDocument();
    doc.pages.add(); // default A4 595x842
    final plain = Uint8List.fromList(await doc.save());
    doc.dispose();

    final cropped = await PdfService.crop(plain, const [
      CropPage(0, 0.25, 0.25, 0.5, 0.5),
    ]);
    final result = sf.PdfDocument(inputBytes: cropped);
    final size = result.pages[0].size;
    result.dispose();
    // Half width/height of the original A4.
    expect((size.width - 595 * 0.5).abs(), lessThan(2));
    expect((size.height - 842 * 0.5).abs(), lessThan(2));
  });

  test('drawInk writes ink onto the page and keeps it valid', () async {
    final doc = sf.PdfDocument();
    doc.pages.add();
    final plain = Uint8List.fromList(await doc.save());
    doc.dispose();

    final inked = await PdfService.drawInk(plain, const [
      InkStroke(0, 229, 57, 53, 0.007, InkShape.pen, [
        Offset(0.2, 0.2),
        Offset(0.5, 0.4),
        Offset(0.7, 0.3),
      ]),
      InkStroke(0, 30, 136, 229, 0.007, InkShape.arrow, [
        Offset(0.3, 0.6),
        Offset(0.7, 0.7),
      ]),
    ]);
    expect(String.fromCharCodes(inked.take(5)), '%PDF-');
    expect(await PdfService.pageCount(inked), 1);
    expect(inked.length, greaterThan(plain.length));
  });

  test('split-to-files groups pages by ranges', () {
    // "1-3, 5, 8-10" over a 10-page doc -> 3 groups of 0-based indices.
    final groups = SplitFilesScreen.parseRangeGroups('1-3, 5, 8-10', 10);
    expect(groups.length, 3);
    expect(groups[0], [0, 1, 2]);
    expect(groups[1], [4]);
    expect(groups[2], [7, 8, 9]);
    // Out-of-range and reversed tokens are dropped.
    expect(SplitFilesScreen.parseRangeGroups('9-8, 20-25', 10), isEmpty);
  });

  test('docx builder produces a valid, readable Word file', () {
    final bytes = DocxBuilder.build(const [
      DocParagraph([DocRun('Resume', bold: true, halfPt: 32)], heading: 1),
      DocParagraph([
        DocRun('Harsh ', bold: true),
        DocRun('Tank', italic: true),
      ]),
      DocParagraph([DocRun('Backend developer')], bullet: true),
      DocParagraph([DocRun('Col A\tCol B')]),
    ]);
    // Valid zip container.
    expect(String.fromCharCodes(bytes.take(2)), 'PK');
    // The OOXML parts and content survive a round-trip through the zip.
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((f) => f.name).toSet();
    expect(names.contains('word/document.xml'), isTrue);
    expect(names.contains('[Content_Types].xml'), isTrue);
    final doc = utf8.decode(
        archive.files.firstWhere((f) => f.name == 'word/document.xml').content
            as List<int>);
    expect(doc.contains('Resume'), isTrue);
    expect(doc.contains('Backend developer'), isTrue);
    expect(doc.contains('<w:tab/>'), isTrue); // tab-aligned columns
    expect(doc.contains('Heading1'), isTrue);
  });

  test('range parser handles lists, ranges and clamping', () {
    expect(SelectionBar.parseRanges('1-3, 7', 10), {0, 1, 2, 6});
    expect(SelectionBar.parseRanges('2', 10), {1});
    expect(SelectionBar.parseRanges('8-15', 10), {7, 8, 9});
    expect(SelectionBar.parseRanges('junk', 10), isEmpty);
    expect(SelectionBar.parseRanges('3-1', 10), isEmpty);
  });
}
