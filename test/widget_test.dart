import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('range parser handles lists, ranges and clamping', () {
    expect(SelectionBar.parseRanges('1-3, 7', 10), {0, 1, 2, 6});
    expect(SelectionBar.parseRanges('2', 10), {1});
    expect(SelectionBar.parseRanges('8-15', 10), {7, 8, 9});
    expect(SelectionBar.parseRanges('junk', 10), isEmpty);
    expect(SelectionBar.parseRanges('3-1', 10), isEmpty);
  });
}
