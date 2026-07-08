import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/tool.dart';
import '../../core/services/file_service.dart';
import '../../core/services/pdf_service.dart';
import '../../core/services/render_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../../ui/theme.dart';
import '../merge/merge_screen.dart';
import '../result/result_screen.dart';
import '../shared/page_grid.dart';
import '../shared/unlock_helper.dart';

enum DrawTool { pen, line, arrow, rect, ellipse, eraser }

class _Stroke {
  final int pageIndex;
  final int colorIndex;
  final double width;
  final InkShape shape;
  final List<Offset> points;
  _Stroke(this.pageIndex, this.colorIndex, this.width, this.shape, this.points);
}

/// Freehand + shape markup — pen, line, arrow, rectangle, ellipse, eraser.
/// Vector output; the PDF stays crisp and content underneath is preserved.
class DrawScreen extends StatefulWidget {
  final PickedItem? initial;
  const DrawScreen({super.key, this.initial});

  @override
  State<DrawScreen> createState() => _DrawScreenState();
}

class _DrawScreenState extends State<DrawScreen> {
  static const List<Color> colors = [
    Color(0xFFE53935), // red
    Color(0xFF1E88E5), // blue
    Color(0xFF1A1A1A), // black
    Color(0xFF43A047), // green
  ];
  static const List<double> widths = [0.004, 0.007, 0.012];

  static const List<(DrawTool, IconData, String)> tools = [
    (DrawTool.pen, Icons.gesture_rounded, 'Pen'),
    (DrawTool.line, Icons.remove_rounded, 'Line'),
    (DrawTool.arrow, Icons.north_east_rounded, 'Arrow'),
    (DrawTool.rect, Icons.crop_square_rounded, 'Box'),
    (DrawTool.ellipse, Icons.circle_outlined, 'Ellipse'),
    (DrawTool.eraser, Icons.delete_sweep_rounded, 'Eraser'),
  ];

  PickedItem? _item;
  ThumbCache? _cache;
  int _pageIndex = 0;
  double _pageAspect = 0.71;
  final Map<int, Uint8List> _pageImages = {};
  final List<_Stroke> _strokes = [];
  final List<_Stroke> _redo = [];
  _Stroke? _active;
  DrawTool _tool = DrawTool.pen;
  int _colorIndex = 0;
  int _widthIndex = 1;
  final _zoomController = TransformationController();
  bool _zoomMode = false;

  InkShape get _activeShape => switch (_tool) {
        DrawTool.line => InkShape.line,
        DrawTool.arrow => InkShape.arrow,
        DrawTool.rect => InkShape.rect,
        DrawTool.ellipse => InkShape.ellipse,
        _ => InkShape.pen,
      };

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _open(widget.initial!);
  }

  @override
  void dispose() {
    _cache?.doc.close();
    _zoomController.dispose();
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
      _strokes.clear();
      _redo.clear();
    });
    await _showPage(0);
  }

  Future<void> _showPage(int index) async {
    final cache = _cache;
    if (cache == null) return;
    setState(() {
      _pageIndex = index;
      _zoomController.value = Matrix4.identity();
    });
    final size = await cache.doc.pageSize(index);
    if (!mounted) return;
    setState(() => _pageAspect = size.width / size.height);
    if (!_pageImages.containsKey(index)) {
      final bytes = await cache.doc.renderPage(index, scale: 2, png: false);
      if (!mounted) return;
      setState(() => _pageImages[index] = bytes);
    }
  }

  Future<void> _save() async {
    final item = _item!;
    final out = await runBusy<OutFile>(
      context,
      label: 'Applying drawing…',
      task: () async {
        final ink = <InkStroke>[];
        for (final s in _strokes) {
          final c = colors[s.colorIndex];
          ink.add(InkStroke(
            s.pageIndex,
            (c.r * 255).round(),
            (c.g * 255).round(),
            (c.b * 255).round(),
            s.width,
            s.shape,
            s.points,
          ));
        }
        final bytes = await PdfService.drawInk(await item.readBytes(), ink);
        final base =
            item.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
        return OutFile(
          name: '${base}_annotated.pdf',
          bytes: bytes,
          mime: 'application/pdf',
        );
      },
    );
    if (out != null && mounted) {
      Navigator.of(context).push(
          Motion.fadeThrough(ResultScreen(tool: Tool.draw, files: [out])));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cache = _cache;
    final pageImage = _pageImages[_pageIndex];
    final pageStrokes =
        _strokes.where((s) => s.pageIndex == _pageIndex).toList();
    final isEraser = _tool == DrawTool.eraser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Draw'),
        actions: [
          if (cache != null) ...[
            IconButton(
              tooltip: _zoomMode ? 'Back to drawing' : 'Zoom to review',
              isSelected: _zoomMode,
              icon: Icon(
                  _zoomMode ? Icons.edit_rounded : Icons.zoom_in_rounded),
              onPressed: () => setState(() => _zoomMode = !_zoomMode),
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
              icon: Tool.draw.style.icon,
              title: 'Mark it up by hand',
              message:
                  'Draw freehand, add arrows, boxes or circles, or erase — all inked straight onto the page.',
              action: FilledButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Open PDF'),
              ),
            )
          : Column(
              children: [
                _toolBar(scheme, isEraser),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _pageAspect,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final w = constraints.maxWidth;
                            final h = constraints.maxHeight;
                            return InteractiveViewer(
                              transformationController: _zoomController,
                              panEnabled: _zoomMode,
                              scaleEnabled: _zoomMode,
                              minScale: 1,
                              maxScale: 6,
                              child: GestureDetector(
                                onPanStart: _zoomMode
                                    ? null
                                    : (d) => _onStart(d.localPosition, w, h),
                                onPanUpdate: _zoomMode
                                    ? null
                                    : (d) => _onUpdate(d.localPosition, w, h),
                                onPanEnd: _zoomMode ? null : (_) => _onEnd(),
                                onDoubleTap: _zoomMode
                                    ? () => setState(() => _zoomController
                                        .value = Matrix4.identity())
                                    : null,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.18),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      if (pageImage != null)
                                        Image.memory(pageImage,
                                            fit: BoxFit.fill,
                                            gaplessPlayback: true)
                                      else
                                        const Center(
                                            child:
                                                CircularProgressIndicator()),
                                      CustomPaint(
                                          painter: _InkPainter(pageStrokes)),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                if (cache.doc.pageCount > 1) _pageStrip(cache, scheme),
              ],
            ),
      bottomNavigationBar: cache == null
          ? null
          : BottomBar(
              children: [
                IconButton.outlined(
                  tooltip: 'Undo',
                  style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
                  onPressed: _strokes.isEmpty ? null : _undo,
                  icon: const Icon(Icons.undo_rounded),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Redo',
                  style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
                  onPressed: _redo.isEmpty ? null : _redoAction,
                  icon: const Icon(Icons.redo_rounded),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Tool.draw.style.base,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _strokes.isEmpty ? null : _save,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Save'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _toolBar(ColorScheme scheme, bool isEraser) {
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final t in tools)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: IconButton(
                    tooltip: t.$3,
                    isSelected: _tool == t.$1,
                    style: IconButton.styleFrom(
                      backgroundColor: _tool == t.$1
                          ? Tool.draw.style.base.withValues(alpha: 0.15)
                          : null,
                      foregroundColor: _tool == t.$1
                          ? Tool.draw.style.base
                          : scheme.onSurfaceVariant,
                    ),
                    onPressed: () => setState(() => _tool = t.$1),
                    icon: Icon(t.$2),
                  ),
                ),
            ],
          ),
        ),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: isEraser ? 0.35 : 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 12, 4),
            child: Row(
              children: [
                for (var i = 0; i < colors.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GestureDetector(
                      onTap: isEraser
                          ? null
                          : () => setState(() => _colorIndex = i),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: colors[i],
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _colorIndex == i
                                ? scheme.onSurface
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                for (var i = 0; i < widths.length; i++)
                  GestureDetector(
                    onTap: isEraser
                        ? null
                        : () => setState(() => _widthIndex = i),
                    child: Container(
                      width: 34,
                      height: 34,
                      margin: const EdgeInsets.only(left: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _widthIndex == i
                            ? scheme.primary.withValues(alpha: 0.15)
                            : Colors.transparent,
                      ),
                      child: Center(
                        child: Container(
                          width: 6.0 + i * 6,
                          height: 6.0 + i * 6,
                          decoration: BoxDecoration(
                            color: scheme.onSurface,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _pageStrip(ThumbCache cache, ColorScheme scheme) {
    return SizedBox(
      height: 78,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        itemCount: cache.doc.pageCount,
        itemBuilder: (context, i) {
          final count = _strokes.where((s) => s.pageIndex == i).length;
          return GestureDetector(
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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FutureBuilder<Uint8List>(
                    future: cache.thumb(i),
                    builder: (context, snap) => snap.hasData
                        ? Image.memory(snap.data!, fit: BoxFit.cover)
                        : const SizedBox.shrink(),
                  ),
                  if (count > 0)
                    Positioned(
                      right: 3,
                      top: 3,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Tool.draw.style.base,
                          shape: BoxShape.circle,
                        ),
                        child: Text('$count',
                            style: AppTheme.manrope(800,
                                size: 9, color: Colors.white)),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Offset _norm(Offset pos, double w, double h) =>
      Offset((pos.dx / w).clamp(0.0, 1.0), (pos.dy / h).clamp(0.0, 1.0));

  void _onStart(Offset pos, double w, double h) {
    final p = _norm(pos, w, h);
    if (_tool == DrawTool.eraser) {
      _eraseAt(p);
      return;
    }
    HapticFeedback.selectionClick();
    final stroke = _tool == DrawTool.pen
        ? _Stroke(_pageIndex, _colorIndex, widths[_widthIndex], InkShape.pen, [p])
        : _Stroke(_pageIndex, _colorIndex, widths[_widthIndex], _activeShape,
            [p, p]);
    setState(() {
      _strokes.add(stroke);
      _active = stroke;
      _redo.clear();
    });
  }

  void _onUpdate(Offset pos, double w, double h) {
    final p = _norm(pos, w, h);
    if (_tool == DrawTool.eraser) {
      _eraseAt(p);
      return;
    }
    final active = _active;
    if (active == null) return;
    setState(() {
      if (active.shape == InkShape.pen) {
        active.points.add(p);
      } else {
        active.points[1] = p; // 2-point shapes track the drag end
      }
    });
  }

  void _onEnd() {
    final active = _active;
    if (active != null) {
      final degenerate = active.shape == InkShape.pen
          ? active.points.length < 2
          : (active.points.first - active.points.last).distance < 0.01;
      if (degenerate) setState(() => _strokes.remove(active));
    }
    _active = null;
  }

  void _eraseAt(Offset p) {
    for (var i = _strokes.length - 1; i >= 0; i--) {
      final s = _strokes[i];
      if (s.pageIndex != _pageIndex) continue;
      if (_hits(s, p)) {
        HapticFeedback.selectionClick();
        setState(() => _strokes.removeAt(i));
        return;
      }
    }
  }

  bool _hits(_Stroke s, Offset p) {
    const tol = 0.022;
    if (s.shape == InkShape.pen || s.shape == InkShape.line ||
        s.shape == InkShape.arrow) {
      for (final q in s.points) {
        if ((q - p).distance < tol) return true;
      }
      // also sample along a straight segment
      if (s.points.length == 2) {
        for (var t = 0.0; t <= 1.0; t += 0.1) {
          final q = Offset.lerp(s.points.first, s.points.last, t)!;
          if ((q - p).distance < tol) return true;
        }
      }
      return false;
    }
    // rect / ellipse: near the bounding box perimeter
    final r = Rect.fromPoints(s.points.first, s.points.last);
    return r.inflate(tol).contains(p) && !r.deflate(tol).contains(p);
  }

  void _undo() {
    setState(() => _redo.add(_strokes.removeLast()));
  }

  void _redoAction() {
    final s = _redo.removeLast();
    setState(() {
      _strokes.add(s);
      if (s.pageIndex != _pageIndex) _showPage(s.pageIndex);
    });
  }
}

class _InkPainter extends CustomPainter {
  final List<_Stroke> strokes;
  _InkPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = _DrawScreenState.colors[stroke.colorIndex]
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.width * size.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final pts = [
        for (final p in stroke.points)
          Offset(p.dx * size.width, p.dy * size.height)
      ];
      switch (stroke.shape) {
        case InkShape.pen:
          _paintPen(canvas, pts, paint);
        case InkShape.line:
          canvas.drawLine(pts.first, pts.last, paint);
        case InkShape.arrow:
          _paintArrow(canvas, pts.first, pts.last, size, paint);
        case InkShape.rect:
          canvas.drawRect(Rect.fromPoints(pts.first, pts.last), paint);
        case InkShape.ellipse:
          canvas.drawOval(Rect.fromPoints(pts.first, pts.last), paint);
      }
    }
  }

  void _paintPen(Canvas canvas, List<Offset> pts, Paint paint) {
    if (pts.length == 1) {
      canvas.drawCircle(pts.first, paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
      paint.style = PaintingStyle.stroke;
      return;
    }
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length - 1; i++) {
      final mid = (pts[i] + pts[i + 1]) / 2;
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    canvas.drawPath(path, paint);
  }

  void _paintArrow(Canvas canvas, Offset a, Offset b, Size size, Paint paint) {
    canvas.drawLine(a, b, paint);
    final ang = (b - a).direction;
    final len = size.width * 0.022;
    for (final off in [0.5, -0.5]) {
      canvas.drawLine(
        b,
        b + Offset.fromDirection(ang + 3.14159 + off, len),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_InkPainter old) => true;
}
