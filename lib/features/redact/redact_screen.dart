import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/tool.dart';
import '../../core/services/file_service.dart';
import '../../core/services/pdf_service.dart';
import '../../core/services/redact_burn.dart';
import '../../core/services/render_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../../ui/theme.dart';
import '../merge/merge_screen.dart';
import '../result/result_screen.dart';
import '../shared/page_grid.dart';
import '../shared/unlock_helper.dart';

/// One redaction box in normalized page coordinates.
class _Redaction {
  final int pageIndex;
  final bool pixelate;
  Rect nRect;
  String? label;
  _Redaction(this.pageIndex, this.nRect, this.pixelate);
}

enum _DragMode { none, draw, move, resize }

/// TRUE redaction: draw boxes over sensitive content; on save, affected
/// pages are flattened to images (destroying the content underneath) and
/// the boxes are burned in as solid black.
class RedactScreen extends StatefulWidget {
  final PickedItem? initial;
  const RedactScreen({super.key, this.initial});

  @override
  State<RedactScreen> createState() => _RedactScreenState();
}

class _RedactScreenState extends State<RedactScreen> {
  PickedItem? _item;
  ThumbCache? _cache;
  int _pageIndex = 0;
  double _pageAspect = 0.71;
  final Map<int, Uint8List> _pageImages = {};
  final List<_Redaction> _boxes = [];
  _Redaction? _selected;
  Offset? _dragStart;
  Rect? _draftRect;
  _DragMode _dragMode = _DragMode.none;
  bool _pixelateStyle = false;
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

  /// Finds every occurrence of the query and marks each as a redaction box
  /// in the currently-selected style.
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
            'No matches. Scanned PDFs have no text layer — draw boxes by hand or make it searchable first.'),
      ));
      return;
    }
    setState(() {
      for (final m in matches) {
        _boxes.add(_Redaction(
          m.pageIndex,
          Rect.fromLTWH(m.nx, m.ny, m.nw, m.nh),
          _pixelateStyle,
        ));
      }
    });
    final firstPage = matches.first.pageIndex;
    if (firstPage != _pageIndex) await _showPage(firstPage);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          'Marked ${matches.length} match${matches.length == 1 ? '' : 'es'} — review, then redact.'),
    ));
    // Drop the keyboard so the whole page is visible for review, but keep
    // the query so another term is just a tap away. Select it so retyping
    // replaces it.
    _searchFocus.unfocus();
    _search.selection =
        TextSelection(baseOffset: 0, extentOffset: _search.text.length);
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
      _zoomController.value = Matrix4.identity(); // fresh page starts fit
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

  Future<void> _apply() async {
    final item = _item!;
    final cache = _cache!;
    final status = ValueNotifier<String?>(null);
    final out = await runBusy<OutFile>(
      context,
      label: 'Destroying hidden content…',
      status: status,
      task: () async {
        final byPage = <int, List<_Redaction>>{};
        for (final box in _boxes) {
          byPage.putIfAbsent(box.pageIndex, () => []).add(box);
        }
        final pages = <RedactPage>[];
        var done = 0;
        const scale = 2.5;
        for (final entry in byPage.entries) {
          status.value = 'Flattening page ${++done} of ${byPage.length}';
          final size = await cache.doc.pageSize(entry.key);
          final jpg = await cache.doc
              .renderPage(entry.key, scale: scale, png: false, jpgQuality: 88);
          // Burn the effects into the pixels: irreversible by construction.
          final imgW = size.width * scale;
          final imgH = size.height * scale;
          final burned = await RedactBurn.burn(jpg, [
            for (final b in entry.value)
              BurnBox(
                Rect.fromLTWH(
                  b.nRect.left * imgW,
                  b.nRect.top * imgH,
                  b.nRect.width * imgW,
                  b.nRect.height * imgH,
                ),
                b.pixelate,
              ),
          ]);
          pages.add(RedactPage(
            pageIndex: entry.key,
            jpg: burned,
            widthPt: size.width,
            heightPt: size.height,
            boxes: const [],
            labels: [
              for (final b in entry.value)
                if (b.label != null && b.label!.trim().isNotEmpty)
                  RedactLabel(
                    b.label!.trim(),
                    Rect.fromLTWH(
                      b.nRect.left * size.width,
                      b.nRect.top * size.height,
                      b.nRect.width * size.width,
                      b.nRect.height * size.height,
                    ),
                    b.pixelate,
                  ),
            ],
          ));
        }
        status.value = 'Rebuilding PDF';
        final bytes = await PdfService.redact(await item.readBytes(), pages);
        final base =
            item.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
        return OutFile(
          name: '${base}_redacted.pdf',
          bytes: bytes,
          mime: 'application/pdf',
        );
      },
    );
    if (out != null && mounted) {
      Navigator.of(context).push(Motion.fadeThrough(
          ResultScreen(tool: Tool.redact, files: [out])));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cache = _cache;
    final pageImage = _pageImages[_pageIndex];
    final pageBoxes =
        _boxes.where((b) => b.pageIndex == _pageIndex).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Redact'),
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
                // Zoom is kept when switching to draw mode — you can draw
                // and adjust while zoomed in. Double-tap resets it.
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
              icon: Tool.redact.style.icon,
              title: 'Black it out — for real',
              message:
                  'Search for text to auto-mark it, or drag boxes over anything private. FileMill destroys the content underneath, not just covers it.',
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
                            hintText: 'Find text to redact…',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(64, 50),
                          backgroundColor: Tool.redact.style.base,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _findAndMark,
                        child: const Text('Find'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                            value: false,
                            label: Text('Black out'),
                            icon: Icon(Icons.square_rounded)),
                        ButtonSegment(
                            value: true,
                            label: Text('Pixelate'),
                            icon: Icon(Icons.blur_on_rounded)),
                      ],
                      selected: {_pixelateStyle},
                      onSelectionChanged: (s) =>
                          setState(() => _pixelateStyle = s.first),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Text(
                    _zoomMode
                        ? 'Zoom mode: pinch to zoom, drag to pan, double-tap to reset · tap the pencil to draw'
                        : 'Drag to cover something · tap a box to move/resize · tap the magnifier to zoom in',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
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
                              // In zoom mode the handlers are removed so the
                              // InteractiveViewer receives pinch/pan instead.
                              onDoubleTap: _zoomMode
                                  ? () => setState(() => _zoomController
                                      .value = Matrix4.identity())
                                  : null,
                              onTapUp: _zoomMode
                                  ? null
                                  : (d) => _onTap(d.localPosition, w, h),
                              onPanStart: _zoomMode
                                  ? null
                                  : (d) => _onPanStart(d.localPosition, w, h),
                              onPanUpdate: _zoomMode
                                  ? null
                                  : (d) => _onPanUpdate(d, w, h),
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
                                          decoration: BoxDecoration(
                                            color: Colors.black
                                                .withValues(alpha: 0.55),
                                            border: Border.all(
                                                color: scheme.primary,
                                                width: 1.5),
                                          ),
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
                                      decoration: const BoxDecoration(
                                        color: Colors.black,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text('$count',
                                          style: AppTheme.manrope(800,
                                              size: 9,
                                              color: Colors.white)),
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
                if (_selected != null) ...[
                  IconButton.outlined(
                    tooltip: 'Label',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(56, 56),
                    ),
                    onPressed: () => _editLabel(_selected!),
                    icon: const Icon(Icons.text_fields_rounded),
                  ),
                  const SizedBox(width: 10),
                  IconButton.outlined(
                    tooltip: 'Remove box',
                    style: IconButton.styleFrom(
                      foregroundColor: scheme.error,
                      minimumSize: const Size(56, 56),
                    ),
                    onPressed: () => setState(() {
                      _boxes.remove(_selected);
                      _selected = null;
                    }),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ]
                else
                  IconButton.outlined(
                    tooltip: 'Undo last box',
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
                  flex: 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Tool.redact.style.base,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _boxes.isEmpty ? null : _apply,
                    icon: const Icon(Icons.visibility_off_rounded),
                    label: Text(
                        'Redact ${_boxes.length} area${_boxes.length == 1 ? '' : 's'}'),
                  ),
                ),
              ],
            ),
    );
  }

  Rect _rectPx(_Redaction box, double w, double h) => Rect.fromLTWH(
      box.nRect.left * w,
      box.nRect.top * h,
      box.nRect.width * w,
      box.nRect.height * h);

  void _onTap(Offset pos, double w, double h) {
    for (final box in _boxes.reversed) {
      if (box.pageIndex != _pageIndex) continue;
      if (_rectPx(box, w, h).inflate(8).contains(pos)) {
        HapticFeedback.selectionClick();
        setState(() => _selected = box);
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
        HapticFeedback.selectionClick();
        setState(() => _dragMode = _DragMode.resize);
        return;
      }
      if (rect.inflate(10).contains(pos)) {
        setState(() => _dragMode = _DragMode.move);
        return;
      }
    }
    // Grab any box under the finger to select-and-move it directly.
    for (final box in _boxes.reversed) {
      if (box.pageIndex != _pageIndex) continue;
      if (_rectPx(box, w, h).inflate(8).contains(pos)) {
        HapticFeedback.selectionClick();
        setState(() {
          _selected = box;
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
        setState(() =>
            _draftRect = Rect.fromPoints(start, d.localPosition));
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
        draft.width < 12 ||
        draft.height < 8) {
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _boxes.add(_Redaction(
        _pageIndex,
        Rect.fromLTWH(
          (draft.left / w).clamp(0.0, 1.0),
          (draft.top / h).clamp(0.0, 1.0),
          (draft.width / w).clamp(0.005, 1.0),
          (draft.height / h).clamp(0.005, 1.0),
        ),
        _pixelateStyle,
      ));
    });
  }

  Widget _buildBox(_Redaction box, double w, double h, ColorScheme scheme) {
    final selected = identical(box, _selected);
    // On-screen boxes are PENDING marks (translucent, so the content under
    // them stays visible for review) — the destructive black/mosaic is only
    // applied on "Redact". A red border signals "will be removed".
    final Widget fill;
    if (box.pixelate) {
      fill = ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(color: Colors.white.withValues(alpha: 0.2)),
        ),
      );
    } else {
      fill = Container(
        color: Colors.black.withValues(alpha: selected ? 0.5 : 0.42),
      );
    }
    return Positioned(
      left: box.nRect.left * w,
      top: box.nRect.top * h,
      width: box.nRect.width * w,
      height: box.nRect.height * h,
      child: IgnorePointer(
        child: Container(
          foregroundDecoration: BoxDecoration(
            border: Border.all(
              color: selected ? scheme.primary : const Color(0xFFE53935),
              width: selected ? 2.5 : 1.5,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              fill,
              if (box.label != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        box.label!,
                        style: TextStyle(
                          color: box.pixelate
                              ? const Color(0xFF282828)
                              : Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              _handleOverlay(selected, scheme),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editLabel(_Redaction box) async {
    final controller = TextEditingController(text: box.label ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Label this box'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration:
              const InputDecoration(hintText: 'e.g. REDACTED, HIDDEN'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (result == null) return;
    setState(() => box.label = result.trim().isEmpty ? null : result.trim());
  }

  Widget _handleOverlay(bool selected, ColorScheme scheme) {
    if (!selected) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        width: 22,
        height: 22,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: scheme.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: const Icon(Icons.open_in_full_rounded,
            size: 11, color: Colors.white),
      ),
    );
  }
}
