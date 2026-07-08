import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import 'package:filemill/core/services/image_convert_service.dart';
import 'package:filemill/core/services/pdf_service.dart';
import 'package:filemill/core/services/scan_processor.dart';
import 'package:filemill/core/services/searchable_service.dart';
import 'package:filemill/features/home/home_screen.dart';
import 'package:filemill/features/shared/page_grid.dart';
import 'package:filemill/ui/theme.dart';

void main() {
  testWidgets('Home renders wordmark, privacy claim and all tools',
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
    expect(find.textContaining('Zero uploads'), findsOneWidget);
    expect(find.text('Read PDF'), findsOneWidget);
    expect(find.text('Merge PDF'), findsOneWidget);
    expect(find.text('Split PDF'), findsOneWidget);
    expect(find.text('Organize'), findsOneWidget);
    expect(find.text('Protect PDF'), findsOneWidget);
    expect(find.text('Sign PDF'), findsOneWidget);
    expect(find.text('Add Text'), findsOneWidget);
    expect(find.text('Compress PDF'), findsOneWidget);
    expect(find.text('Watermark'), findsOneWidget);
    expect(find.text('Highlight'), findsOneWidget);
    expect(find.text('Redact'), findsOneWidget);
    expect(find.text('PDF → Images'), findsOneWidget);
    expect(find.text('Images → PDF'), findsOneWidget);
    expect(find.text('Scan → PDF'), findsOneWidget);
    expect(find.text('Extract Text'), findsOneWidget);
    expect(find.text('Searchable PDF'), findsOneWidget);
    expect(find.text('Convert Images'), findsOneWidget);
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

  test('range parser handles lists, ranges and clamping', () {
    expect(SelectionBar.parseRanges('1-3, 7', 10), {0, 1, 2, 6});
    expect(SelectionBar.parseRanges('2', 10), {1});
    expect(SelectionBar.parseRanges('8-15', 10), {7, 8, 9});
    expect(SelectionBar.parseRanges('junk', 10), isEmpty);
    expect(SelectionBar.parseRanges('3-1', 10), isEmpty);
  });
}
