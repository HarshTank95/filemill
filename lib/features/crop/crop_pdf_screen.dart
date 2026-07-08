import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/tool.dart';
import '../../core/services/crop_service.dart';
import '../../core/services/file_service.dart';
import '../../core/services/pdf_service.dart';
import '../../core/services/render_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../merge/merge_screen.dart';
import '../result/result_screen.dart';
import '../shared/page_grid.dart';
import '../shared/unlock_helper.dart';

enum _Grab { none, move, topLeft, bottomRight }

/// Crop / trim PDF pages. One crop rect, applied to the current page or all
/// pages; Auto-trim detects and removes white margins.
class CropPdfScreen extends StatefulWidget {
  final PickedItem? initial;
  const CropPdfScreen({super.key, this.initial});

  @override
  State<CropPdfScreen> createState() => _CropPdfScreenState();
}

class _CropPdfScreenState extends State<CropPdfScreen> {
  PickedItem? _item;
  ThumbCache? _cache;
  int _pageIndex = 0;
  double _pageAspect = 0.71;
  final Map<int, Uint8List> _pageImages = {};
  Rect _crop = const Rect.fromLTRB(0.06, 0.06, 0.94, 0.94);
  bool _applyAll = true;
  _Grab _grab = _Grab.none;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _open(widget.initial!);
  }

  @override
  void dispose() {
    _cache?.doc.close();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await FileService.pickPdfs(multiple: false);
    if (picked.isEmpty) return;
    await _open(picked.first);
  }

  Future<void> _open(PickedItem item) async {
    if (!await ensureUnlocked(context, item)) return;
    if (!mounted) return;
    final doc = await runBusy<RenderedDoc>(
      context,
      label: 'Opening ${item.name}…',
      task: () async => item.unlockedBytes != null
          ? RenderedDoc.openData(item.unlockedBytes!)
          : RenderedDoc.openFile(item.path),
    );
    if (doc == null) return;
    _cache?.doc.close();
    setState(() {
      _item = item;
      _cache = ThumbCache(doc);
      _pageIndex = 0;
      _pageImages.clear();
      _crop = const Rect.fromLTRB(0.06, 0.06, 0.94, 0.94);
    });
    await _showPage(0);
  }

  Future<void> _showPage(int index) async {
    final cache = _cache;
    if (cache == null) return;
    setState(() => _pageIndex = index);
    final size = await cache.doc.pageSize(index);
    if (!mounted) return;
    setState(() => _pageAspect = size.width / size.height);
    if (!_pageImages.containsKey(index)) {
      final bytes = await cache.doc.renderPage(index, scale: 2, png: false);
      if (!mounted) return;
      setState(() => _pageImages[index] = bytes);
    }
  }

  Future<void> _autoTrim() async {
    final image = _pageImages[_pageIndex];
    if (image == null) return;
    final rect = await CropService.autoTrim(image);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => _crop = rect);
  }

  Future<void> _apply() async {
    final item = _item!;
    final cache = _cache!;
    final out = await runBusy<OutFile>(
      context,
      label: 'Cropping…',
      task: () async {
        final pages = <CropPage>[];
        if (_applyAll) {
          for (var i = 0; i < cache.doc.pageCount; i++) {
            pages.add(CropPage(
                i, _crop.left, _crop.top, _crop.width, _crop.height));
          }
        } else {
          pages.add(CropPage(_pageIndex, _crop.left, _crop.top, _crop.width,
              _crop.height));
        }
        final bytes = await PdfService.crop(await item.readBytes(), pages);
        final base =
            item.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
        return OutFile(
          name: '${base}_cropped.pdf',
          bytes: bytes,
          mime: 'application/pdf',
        );
      },
    );
    if (out != null && mounted) {
      Navigator.of(context).push(
          Motion.fadeThrough(ResultScreen(tool: Tool.crop, files: [out])));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cache = _cache;
    final pageImage = _pageImages[_pageIndex];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crop PDF'),
        actions: [
          if (cache != null) ...[
            IconButton(
              tooltip: 'Auto-trim margins',
              icon: const Icon(Icons.crop_free_rounded),
              onPressed: _autoTrim,
            ),
            IconButton(
              tooltip: 'Open another PDF',
              icon: const Icon(Icons.folder_open_rounded),
              onPressed: _pick,
            ),
          ],
        ],
      ),
      body: cache == null
          ? EmptyState(
              icon: Tool.crop.style.icon,
              title: 'Trim to what matters',
              message:
                  'Cut away margins or crop to a region. Auto-trim removes white borders in one tap.',
              action: FilledButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Open PDF'),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _pageAspect,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final w = constraints.maxWidth;
                            final h = constraints.maxHeight;
                            return GestureDetector(
                              onPanStart: (d) => _onStart(d.localPosition, w, h),
                              onPanUpdate: (d) => _onUpdate(d, w, h),
                              onPanEnd: (_) => _grab = _Grab.none,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (pageImage != null)
                                    Image.memory(pageImage,
                                        fit: BoxFit.fill,
                                        gaplessPlayback: true)
                                  else
                                    const Center(
                                        child: CircularProgressIndicator()),
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _CropPainter(
                                          _crop, scheme.primary),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Icon(Icons.layers_rounded, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Apply to all ${cache.doc.pageCount} pages',
                            style: Theme.of(context).textTheme.bodyMedium),
                      ),
                      Switch(
                        value: _applyAll,
                        onChanged: (v) => setState(() => _applyAll = v),
                      ),
                    ],
                  ),
                ),
                if (cache.doc.pageCount > 1)
                  SizedBox(
                    height: 78,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      itemCount: cache.doc.pageCount,
                      itemBuilder: (context, i) => GestureDetector(
                        onTap: () => _showPage(i),
                        child: Container(
                          width: 50,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: i == _pageIndex
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                              width: i == _pageIndex ? 2.5 : 1,
                            ),
                            color: Colors.white,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: FutureBuilder<Uint8List>(
                            future: cache.thumb(i),
                            builder: (context, snap) => snap.hasData
                                ? Image.memory(snap.data!, fit: BoxFit.cover)
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: cache == null
          ? null
          : BottomBar(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _autoTrim,
                    icon: const Icon(Icons.crop_free_rounded),
                    label: const Text('Auto-trim'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Tool.crop.style.base,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _apply,
                    icon: const Icon(Icons.crop_rounded),
                    label: Text(_applyAll ? 'Crop all pages' : 'Crop this page'),
                  ),
                ),
              ],
            ),
    );
  }

  void _onStart(Offset pos, double w, double h) {
    final rect =
        Rect.fromLTRB(_crop.left * w, _crop.top * h, _crop.right * w, _crop.bottom * h);
    if ((pos - rect.topLeft).distance < 34) {
      _grab = _Grab.topLeft;
    } else if ((pos - rect.bottomRight).distance < 34) {
      _grab = _Grab.bottomRight;
    } else if (rect.contains(pos)) {
      _grab = _Grab.move;
    } else {
      _grab = _Grab.none;
    }
  }

  void _onUpdate(DragUpdateDetails d, double w, double h) {
    if (_grab == _Grab.none) return;
    final dx = d.delta.dx / w;
    final dy = d.delta.dy / h;
    setState(() {
      switch (_grab) {
        case _Grab.move:
          var l = _crop.left + dx;
          var t = _crop.top + dy;
          l = l.clamp(0.0, 1.0 - _crop.width);
          t = t.clamp(0.0, 1.0 - _crop.height);
          _crop = Rect.fromLTWH(l, t, _crop.width, _crop.height);
        case _Grab.topLeft:
          final l = (_crop.left + dx).clamp(0.0, _crop.right - 0.05);
          final t = (_crop.top + dy).clamp(0.0, _crop.bottom - 0.05);
          _crop = Rect.fromLTRB(l, t, _crop.right, _crop.bottom);
        case _Grab.bottomRight:
          final r = (_crop.right + dx).clamp(_crop.left + 0.05, 1.0);
          final b = (_crop.bottom + dy).clamp(_crop.top + 0.05, 1.0);
          _crop = Rect.fromLTRB(_crop.left, _crop.top, r, b);
        case _Grab.none:
          break;
      }
    });
  }
}

class _CropPainter extends CustomPainter {
  final Rect crop; // normalized
  final Color accent;
  _CropPainter(this.crop, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(crop.left * size.width, crop.top * size.height,
        crop.right * size.width, crop.bottom * size.height);

    // Dim everything outside the crop.
    final outside = Path()
      ..addRect(Offset.zero & size)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
        outside, Paint()..color = Colors.black.withValues(alpha: 0.5));

    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = accent,
    );

    // Rule-of-thirds guides.
    final guide = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = rect.left + rect.width * i / 3;
      final y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), guide);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), guide);
    }

    for (final corner in [rect.topLeft, rect.bottomRight]) {
      canvas.drawCircle(corner, 11, Paint()..color = Colors.white);
      canvas.drawCircle(corner, 7, Paint()..color = accent);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.crop != crop || old.accent != accent;
}
