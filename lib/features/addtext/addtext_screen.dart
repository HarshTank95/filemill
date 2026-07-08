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

/// A placed text box: position/size normalized to the page.
class _TextItem {
  final int pageIndex;
  String text;
  int colorIndex;
  bool bold;
  bool italic;
  bool underline;
  PdfFontKind family;
  Rect nRect;
  _TextItem(
    this.pageIndex,
    this.text,
    this.nRect,
    this.colorIndex,
    this.bold,
    this.italic,
    this.underline,
    this.family,
  );
}

enum _DragMode { none, move, resize }

/// Type text onto a PDF — fill flat forms, add names/dates. Vector output.
class AddTextScreen extends StatefulWidget {
  final PickedItem? initial;
  const AddTextScreen({super.key, this.initial});

  @override
  State<AddTextScreen> createState() => _AddTextScreenState();
}

class _AddTextScreenState extends State<AddTextScreen> {
  static const List<Color> colors = [
    Color(0xFF1A1A1A), // black
    Color(0xFF1A3FBF), // blue
    Color(0xFFC81E1E), // red
  ];

  /// Font size as a fraction of box height — shared by preview and output
  /// so what you see matches what's stamped.
  static const double _fontFactor = 0.72;

  PickedItem? _item;
  ThumbCache? _cache;
  int _pageIndex = 0;
  double _pageAspect = 0.71;
  final Map<int, Uint8List> _pageImages = {};
  final List<_TextItem> _items = [];
  _TextItem? _selected;
  int _colorIndex = 0;
  bool _bold = false;
  bool _italic = false;
  bool _underline = false;
  PdfFontKind _family = PdfFontKind.sans;
  _DragMode _dragMode = _DragMode.none;

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
      _items.clear();
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

  Future<void> _addText() async {
    final text = await _editDialog('');
    if (text == null || text.trim().isEmpty) return;
    setState(() {
      final item = _TextItem(
        _pageIndex,
        text.trim(),
        const Rect.fromLTWH(0.12, 0.44, 0.5, 0.05),
        _colorIndex,
        _bold,
        _italic,
        _underline,
        _family,
      );
      _items.add(item);
      _selected = item;
    });
    HapticFeedback.mediumImpact();
  }

  Future<String?> _editDialog(String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Type text'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(hintText: 'Name, date, note…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final item = _item!;
    final cache = _cache!;
    final out = await runBusy<OutFile>(
      context,
      label: 'Adding text…',
      task: () async {
        final stamps = <TextStamp>[];
        for (final t in _items) {
          final size = await cache.doc.pageSize(t.pageIndex);
          final c = colors[t.colorIndex];
          stamps.add(TextStamp(
            pageIndex: t.pageIndex,
            text: t.text,
            x: t.nRect.left * size.width,
            y: t.nRect.top * size.height,
            width: t.nRect.width * size.width,
            fontSize: t.nRect.height * size.height * _fontFactor,
            r: (c.r * 255).round(),
            g: (c.g * 255).round(),
            b: (c.b * 255).round(),
            bold: t.bold,
            italic: t.italic,
            underline: t.underline,
            family: t.family,
          ));
        }
        final bytes = await PdfService.addText(await item.readBytes(), stamps);
        final base =
            item.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
        return OutFile(
          name: '${base}_filled.pdf',
          bytes: bytes,
          mime: 'application/pdf',
        );
      },
    );
    if (out != null && mounted) {
      Navigator.of(context).push(Motion.fadeThrough(
          ResultScreen(tool: Tool.addText, files: [out])));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cache = _cache;
    final pageImage = _pageImages[_pageIndex];
    final pageItems = _items.where((t) => t.pageIndex == _pageIndex).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Text'),
        actions: [
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
              icon: Tool.addText.style.icon,
              title: 'Type onto any PDF',
              message:
                  'Fill flat forms, add your name or a date, drop a note — placed as crisp text, all on this phone.',
              action: FilledButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Open PDF'),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
                  child: Row(
                    children: [
                      for (var i = 0; i < colors.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _colorIndex = i;
                              _selected?.colorIndex = i;
                            }),
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: colors[i],
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _colorIndex == i
                                      ? scheme.primary
                                      : Colors.transparent,
                                  width: 3,
                                ),
                              ),
                            ),
                          ),
                        ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Bold',
                        visualDensity: VisualDensity.compact,
                        isSelected: _bold,
                        onPressed: () => setState(() {
                          _bold = !_bold;
                          _selected?.bold = _bold;
                        }),
                        icon: const Icon(Icons.format_bold_rounded),
                      ),
                      IconButton(
                        tooltip: 'Italic',
                        visualDensity: VisualDensity.compact,
                        isSelected: _italic,
                        onPressed: () => setState(() {
                          _italic = !_italic;
                          _selected?.italic = _italic;
                        }),
                        icon: const Icon(Icons.format_italic_rounded),
                      ),
                      IconButton(
                        tooltip: 'Underline',
                        visualDensity: VisualDensity.compact,
                        isSelected: _underline,
                        onPressed: () => setState(() {
                          _underline = !_underline;
                          _selected?.underline = _underline;
                        }),
                        icon: const Icon(Icons.format_underlined_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<PdfFontKind>(
                      segments: const [
                        ButtonSegment(
                            value: PdfFontKind.sans, label: Text('Sans')),
                        ButtonSegment(
                            value: PdfFontKind.serif, label: Text('Serif')),
                        ButtonSegment(
                            value: PdfFontKind.mono, label: Text('Mono')),
                      ],
                      selected: {_family},
                      onSelectionChanged: (s) => setState(() {
                        _family = s.first;
                        _selected?.family = _family;
                      }),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Text(
                    'Tap “Add text” to place · drag to move · corner to resize · double-tap to edit',
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
                            return GestureDetector(
                              onTap: () => setState(() => _selected = null),
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
                                    for (final t in pageItems)
                                      _buildText(t, w, h, scheme),
                                  ],
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
                            _items.where((t) => t.pageIndex == i).length;
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
                                        color: Tool.addText.style.base,
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
                    tooltip: 'Delete',
                    style: IconButton.styleFrom(
                      foregroundColor: scheme.error,
                      minimumSize: const Size(56, 56),
                    ),
                    onPressed: () => setState(() {
                      _items.remove(_selected);
                      _selected = null;
                    }),
                    icon: const Icon(Icons.delete_outline_rounded),
                  )
                else
                  IconButton.outlined(
                    tooltip: 'Undo',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(56, 56),
                    ),
                    onPressed: _items.isEmpty
                        ? null
                        : () => setState(() {
                              _items.removeLast();
                              _selected = null;
                            }),
                    icon: const Icon(Icons.undo_rounded),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addText,
                    icon: const Icon(Icons.text_fields_rounded),
                    label: const Text('Add text'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Tool.addText.style.base,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _items.isEmpty ? null : _save,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Save'),
                  ),
                ),
              ],
            ),
    );
  }

  void _syncToolbar(_TextItem t) {
    _colorIndex = t.colorIndex;
    _bold = t.bold;
    _italic = t.italic;
    _underline = t.underline;
    _family = t.family;
  }

  String? _previewFont(PdfFontKind family) {
    switch (family) {
      case PdfFontKind.sans:
        return null; // theme default sans
      case PdfFontKind.serif:
        return 'serif';
      case PdfFontKind.mono:
        return 'monospace';
    }
  }

  Widget _buildText(_TextItem t, double w, double h, ColorScheme scheme) {
    final selected = identical(t, _selected);
    final boxH = t.nRect.height * h;
    return Positioned(
      left: t.nRect.left * w,
      top: t.nRect.top * h,
      width: t.nRect.width * w,
      height: boxH,
      child: GestureDetector(
        onTap: () => setState(() {
          _selected = t;
          _syncToolbar(t);
        }),
        onDoubleTap: () async {
          final edited = await _editDialog(t.text);
          if (edited != null && edited.trim().isNotEmpty) {
            setState(() => t.text = edited.trim());
          }
        },
        onPanStart: (d) {
          final localRight = t.nRect.width * w;
          final localBottom = boxH;
          final handleHit =
              (d.localPosition - Offset(localRight, localBottom)).distance <
                  30;
          setState(() {
            _selected = t;
            _syncToolbar(t);
            _dragMode = handleHit ? _DragMode.resize : _DragMode.move;
          });
        },
        onPanUpdate: (d) => setState(() {
          if (_dragMode == _DragMode.move) {
            final r = t.nRect;
            t.nRect = Rect.fromLTWH(
              (r.left + d.delta.dx / w).clamp(0.0, 1.0 - r.width),
              (r.top + d.delta.dy / h).clamp(0.0, 1.0 - r.height),
              r.width,
              r.height,
            );
          } else if (_dragMode == _DragMode.resize) {
            final r = t.nRect;
            t.nRect = Rect.fromLTWH(
              r.left,
              r.top,
              (r.width + d.delta.dx / w).clamp(0.06, 1.0 - r.left),
              (r.height + d.delta.dy / h).clamp(0.02, 0.3),
            );
          }
        }),
        onPanEnd: (_) => _dragMode = _DragMode.none,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  t.text,
                  softWrap: true,
                  style: TextStyle(
                    color: colors[t.colorIndex],
                    fontSize: boxH * _fontFactor,
                    fontWeight: t.bold ? FontWeight.w700 : FontWeight.w400,
                    fontStyle:
                        t.italic ? FontStyle.italic : FontStyle.normal,
                    decoration:
                        t.underline ? TextDecoration.underline : null,
                    fontFamily: _previewFont(t.family),
                    height: 1.0,
                  ),
                ),
              ),
              if (selected)
                Positioned(
                  right: -8,
                  bottom: -8,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.open_in_full_rounded,
                        size: 10, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
