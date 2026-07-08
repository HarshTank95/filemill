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

class _HL {
  final int pageIndex;
  Rect nRect;
  int colorIndex;
  _HL(this.pageIndex, this.nRect, this.colorIndex);
}

enum _DragMode { none, draw, move, resize }

/// Non-destructive highlighter: translucent colored marks over the text.
/// Search-to-highlight reuses the same text locator as Redact.
class HighlightScreen extends StatefulWidget {
  final PickedItem? initial;
  const HighlightScreen({super.key, this.initial});

  @override
  State<HighlightScreen> createState() => _HighlightScreenState();
}

class _HighlightScreenState extends State<HighlightScreen> {
  static const List<Color> colors = [
    Color(0xFFFFF176), // yellow
    Color(0xFFAED581), // green
    Color(0xFFF48FB1), // pink
    Color(0xFF81D4FA), // blue
  ];

  PickedItem? _item;
  ThumbCache? _cache;
  int _pageIndex = 0;
  double _pageAspect = 0.71;
  final Map<int, Uint8List> _pageImages = {};
  final List<_HL> _boxes = [];
  _HL? _selected;
  int _colorIndex = 0;
  Offset? _dragStart;
  Rect? _draftRect;
  _DragMode _dragMode = _DragMode.none;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _zoomController = TransformationController();
  bool _zoomMode = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _open(widget.initial!);
  }

  @override
  void dispose() {
    _cache?.doc.close();
    _search.dispose();
    _searchFocus.dispose();
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
      _boxes.clear();
      _selected = null;
    });
    await _showPage(0);
  }

  Future<void> _showPage(int index) async {
    final cache = _cache;
    if (cache == null) return;
    setState(() {
      _pageIndex = index;
      _selected = null;
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

  Future<void> _findAndMark() async {
    final query = _search.text.trim();
    final item = _item;
    if (query.isEmpty || item == null) return;
    final matches = await runBusy<List<TextMatch>>(
      context,
      label: 'Searching for "$query"…',
      task: () async => PdfService.findText(await item.readBytes(), query),
    );
    if (matches == null || !mounted) return;
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'No matches. Scanned PDFs have no text layer to search.'),
      ));
      return;
    }
    setState(() {
      for (final m in matches) {
        _boxes.add(
            _HL(m.pageIndex, Rect.fromLTWH(m.nx, m.ny, m.nw, m.nh), _colorIndex));
      }
    });
    final firstPage = matches.first.pageIndex;
    if (firstPage != _pageIndex) await _showPage(firstPage);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          'Highlighted ${matches.length} match${matches.length == 1 ? '' : 'es'}.'),
    ));
    _searchFocus.unfocus();
    _search.selection =
        TextSelection(baseOffset: 0, extentOffset: _search.text.length);
  }

  Future<void> _save() async {
    final item = _item!;
    final cache = _cache!;
    final out = await runBusy<OutFile>(
      context,
      label: 'Applying highlights…',
      task: () async {
        final boxes = <HighlightBox>[];
        for (final b in _boxes) {
          final size = await cache.doc.pageSize(b.pageIndex);
          final c = colors[b.colorIndex];
          boxes.add(HighlightBox(
            b.pageIndex,
            Rect.fromLTWH(
              b.nRect.left * size.width,
              b.nRect.top * size.height,
              b.nRect.width * size.width,
              b.nRect.height * size.height,
            ),
            (c.r * 255).round(),
            (c.g * 255).round(),
            (c.b * 255).round(),
          ));
        }
        final bytes = await PdfService.highlight(await item.readBytes(), boxes);
        final base =
            item.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
        return OutFile(
          name: '${base}_highlighted.pdf',
          bytes: bytes,
          mime: 'application/pdf',
        );
      },
    );
    if (out != null && mounted) {
      Navigator.of(context).push(Motion.fadeThrough(
          ResultScreen(tool: Tool.highlight, files: [out])));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cache = _cache;
    final pageImage = _pageImages[_pageIndex];
    final pageBoxes = _boxes.where((b) => b.pageIndex == _pageIndex).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Highlight'),
        actions: [
          if (cache != null)
            IconButton(
              tooltip: _zoomMode ? 'Back to drawing' : 'Zoom to review',
              isSelected: _zoomMode,
              icon: Icon(
                  _zoomMode ? Icons.edit_rounded : Icons.zoom_in_rounded),
              onPressed: () => setState(() {
                _zoomMode = !_zoomMode;
                _selected = null;
              }),
            ),
          if (cache != null)
            IconButton(
              tooltip: 'Open another PDF',
              icon: const Icon(Icons.folder_open_rounded),
              onPressed: _pick,
            ),
        ],
      ),
      body: cache == null
          ? EmptyState(
              icon: Tool.highlight.style.icon,
              title: 'Highlight what matters',
              message:
                  'Search a word to highlight every match, or drag over text by hand. The PDF stays selectable — nothing is flattened.',
              action: FilledButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Open PDF'),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _search,
                          focusNode: _searchFocus,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _findAndMark(),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Find text to highlight…',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(64, 50),
                          backgroundColor: Tool.highlight.style.base,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _findAndMark,
                        child: const Text('Find'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                  child: Row(
                    children: [
                      for (var i = 0; i < colors.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _colorIndex = i;
                                // Recolor the selected mark if any.
                                _selected?.colorIndex = i;
                              });
                            },
                            child: Container(
                              width: 34,
                              height: 34,
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
                      Text(
                        _zoomMode ? 'Zoom mode' : '${_boxes.length} marks',
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
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
                                onDoubleTap: _zoomMode
                                    ? () => setState(() => _zoomController
                                        .value = Matrix4.identity())
                                    : null,
                                onTapUp: _zoomMode
                                    ? null
                                    : (d) => _onTap(d.localPosition, w, h),
                                onPanStart: _zoomMode
                                    ? null
                                    : (d) =>
                                        _onPanStart(d.localPosition, w, h),
                                onPanUpdate:
                                    _zoomMode ? null : (d) => _onPanUpdate(d, w, h),
                                onPanEnd:
                                    _zoomMode ? null : (_) => _onPanEnd(w, h),
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
                                      for (final box in pageBoxes)
                                        _buildBox(box, w, h, scheme),
                                      if (_draftRect != null)
                                        Positioned.fromRect(
                                          rect: _draftRect!,
                                          child: Container(
                                            color: colors[_colorIndex]
                                                .withValues(alpha: 0.45),
                                          ),
                                        ),
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
                if (cache.doc.pageCount > 1)
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: cache.doc.pageCount,
                      itemBuilder: (context, i) {
                        final count =
                            _boxes.where((b) => b.pageIndex == i).length;
                        return GestureDetector(
                          onTap: () => _showPage(i),
                          child: Container(
                            width: 52,
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
                                      ? Image.memory(snap.data!,
                                          fit: BoxFit.cover)
                                      : const SizedBox.shrink(),
                                ),
                                if (count > 0)
                                  Positioned(
                                    right: 3,
                                    top: 3,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Tool.highlight.style.base,
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
                  ),
              ],
            ),
      bottomNavigationBar: cache == null
          ? null
          : BottomBar(
              children: [
                if (_selected != null)
                  IconButton.outlined(
                    tooltip: 'Remove highlight',
                    style: IconButton.styleFrom(
                      foregroundColor: scheme.error,
                      minimumSize: const Size(56, 56),
                    ),
                    onPressed: () => setState(() {
                      _boxes.remove(_selected);
                      _selected = null;
                    }),
                    icon: const Icon(Icons.delete_outline_rounded),
                  )
                else
                  IconButton.outlined(
                    tooltip: 'Undo last',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(56, 56),
                    ),
                    onPressed: _boxes.isEmpty
                        ? null
                        : () => setState(() {
                              _boxes.removeLast();
                              _selected = null;
                            }),
                    icon: const Icon(Icons.undo_rounded),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Tool.highlight.style.base,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _boxes.isEmpty ? null : _save,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(
                        'Save ${_boxes.length} highlight${_boxes.length == 1 ? '' : 's'}'),
                  ),
                ),
              ],
            ),
    );
  }

  Rect _rectPx(_HL box, double w, double h) => Rect.fromLTWH(box.nRect.left * w,
      box.nRect.top * h, box.nRect.width * w, box.nRect.height * h);

  void _onTap(Offset pos, double w, double h) {
    for (final box in _boxes.reversed) {
      if (box.pageIndex != _pageIndex) continue;
      if (_rectPx(box, w, h).inflate(8).contains(pos)) {
        HapticFeedback.selectionClick();
        setState(() {
          _selected = box;
          _colorIndex = box.colorIndex;
        });
        return;
      }
    }
    setState(() => _selected = null);
  }

  void _onPanStart(Offset pos, double w, double h) {
    final selected = _selected;
    if (selected != null && selected.pageIndex == _pageIndex) {
      final rect = _rectPx(selected, w, h);
      if ((pos - rect.bottomRight).distance < 30) {
        setState(() => _dragMode = _DragMode.resize);
        return;
      }
      if (rect.inflate(10).contains(pos)) {
        setState(() => _dragMode = _DragMode.move);
        return;
      }
    }
    for (final box in _boxes.reversed) {
      if (box.pageIndex != _pageIndex) continue;
      if (_rectPx(box, w, h).inflate(8).contains(pos)) {
        HapticFeedback.selectionClick();
        setState(() {
          _selected = box;
          _colorIndex = box.colorIndex;
          _dragMode = _DragMode.move;
        });
        return;
      }
    }
    setState(() {
      _dragMode = _DragMode.draw;
      _dragStart = pos;
      _draftRect = null;
      _selected = null;
    });
  }

  void _onPanUpdate(DragUpdateDetails d, double w, double h) {
    final selected = _selected;
    switch (_dragMode) {
      case _DragMode.draw:
        final start = _dragStart;
        if (start == null) return;
        setState(() => _draftRect = Rect.fromPoints(start, d.localPosition));
      case _DragMode.move:
        if (selected == null) return;
        setState(() {
          final r = selected.nRect;
          selected.nRect = Rect.fromLTWH(
            (r.left + d.delta.dx / w).clamp(0.0, 1.0 - r.width),
            (r.top + d.delta.dy / h).clamp(0.0, 1.0 - r.height),
            r.width,
            r.height,
          );
        });
      case _DragMode.resize:
        if (selected == null) return;
        setState(() {
          final r = selected.nRect;
          selected.nRect = Rect.fromLTWH(
            r.left,
            r.top,
            (r.width + d.delta.dx / w).clamp(0.01, 1.0 - r.left),
            (r.height + d.delta.dy / h).clamp(0.01, 1.0 - r.top),
          );
        });
      case _DragMode.none:
        break;
    }
  }

  void _onPanEnd(double w, double h) {
    final mode = _dragMode;
    final draft = _draftRect;
    setState(() {
      _dragMode = _DragMode.none;
      _dragStart = null;
      _draftRect = null;
    });
    if (mode != _DragMode.draw ||
        draft == null ||
        draft.width < 10 ||
        draft.height < 6) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _boxes.add(_HL(
        _pageIndex,
        Rect.fromLTWH(
          (draft.left / w).clamp(0.0, 1.0),
          (draft.top / h).clamp(0.0, 1.0),
          (draft.width / w).clamp(0.005, 1.0),
          (draft.height / h).clamp(0.005, 1.0),
        ),
        _colorIndex,
      ));
    });
  }

  Widget _buildBox(_HL box, double w, double h, ColorScheme scheme) {
    final selected = identical(box, _selected);
    return Positioned(
      left: box.nRect.left * w,
      top: box.nRect.top * h,
      width: box.nRect.width * w,
      height: box.nRect.height * h,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: colors[box.colorIndex].withValues(alpha: 0.45),
            border: selected
                ? Border.all(color: scheme.onSurface, width: 1.5)
                : null,
          ),
          alignment: Alignment.bottomRight,
          child: selected
              ? Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.open_in_full_rounded,
                      size: 10, color: Colors.white),
                )
              : null,
        ),
      ),
    );
  }
}
