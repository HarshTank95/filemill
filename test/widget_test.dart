import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:filemill/core/services/scan_processor.dart';
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
    expect(find.text('PDF → Images'), findsOneWidget);
    expect(find.text('Images → PDF'), findsOneWidget);
    expect(find.text('Scan → PDF'), findsOneWidget);
    expect(find.text('Extract Text'), findsOneWidget);
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

  test('range parser handles lists, ranges and clamping', () {
    expect(SelectionBar.parseRanges('1-3, 7', 10), {0, 1, 2, 6});
    expect(SelectionBar.parseRanges('2', 10), {1});
    expect(SelectionBar.parseRanges('8-15', 10), {7, 8, 9});
    expect(SelectionBar.parseRanges('junk', 10), isEmpty);
    expect(SelectionBar.parseRanges('3-1', 10), isEmpty);
  });
}
