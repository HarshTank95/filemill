import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/tool.dart';
import '../../core/services/file_service.dart';
import '../../core/services/pdf_service.dart';
import '../../core/services/render_service.dart';
import '../../core/services/signature_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../../ui/theme.dart';
import '../merge/merge_screen.dart';
import '../result/result_screen.dart';
import '../shared/page_grid.dart';
import '../shared/unlock_helper.dart';
import 'signature_pad.dart';

/// One placed signature: position stored in normalized page coordinates
/// (nx/ny/nw in 0..1 of page width/height; height follows the PNG aspect).
class _Placed {
  final int pageIndex;
  final Uint8List png;
  final double aspect; // png height / width
  double nx = 0.30, ny = 0.40, nw = 0.40;
  _Placed({
    required this.pageIndex,
    required this.png,
    required this.aspect,
  });
}

class SignScreen extends StatefulWidget {
  final PickedItem? initial;
  const SignScreen({super.key, this.initial});

  @override
  State<SignScreen> createState() => _SignScreenState();
}

class _SignScreenState extends State<SignScreen> {
  PickedItem? _item;
  ThumbCache? _cache;
  int _pageIndex = 0;
  double _pageAspect = 0.71;
  final Map<int, Uint8List> _pageImages = {};
  final List<_Placed> _stamps = [];
  _Placed? _selected;

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
      _stamps.clear();
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

  Future<void> _addSignature() async {
    final saved = await SignatureService.list();
    if (!mounted) return;
    final png = await showModalBottomSheet<Uint8List>(
      context: context,
      builder: (sheetContext) => _SignatureSheet(saved: saved),
    );
    if (png == null || !mounted) return;
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    final aspect = frame.image.height / frame.image.width;
    frame.image.dispose();
    codec.dispose();
    if (!mounted) return;
    setState(() {
      final placed =
          _Placed(pageIndex: _pageIndex, png: png, aspect: aspect);
      _stamps.add(placed);
      _selected = placed;
    });
    HapticFeedback.mediumImpact();
  }

  Future<void> _save() async {
    final item = _item!;
    final cache = _cache!;
    final out = await runBusy<OutFile>(
      context,
      label: 'Signing PDF…',
      task: () async {
        final stamps = <Stamp>[];
        for (final s in _stamps) {
          final page = await cache.doc.pageSize(s.pageIndex);
          final w = s.nw * page.width;
          stamps.add(Stamp(
            pageIndex: s.pageIndex,
            png: s.png,
            x: s.nx * page.width,
            y: s.ny * page.height,
            width: w,
            height: w * s.aspect,
          ));
        }
        final bytes = await PdfService.stamp(await item.readBytes(), stamps);
        final base =
            item.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
        return OutFile(
          name: '${base}_signed.pdf',
          bytes: bytes,
          mime: 'application/pdf',
        );
      },
    );
    if (out != null && mounted) {
      Navigator.of(context).push(
          Motion.fadeThrough(ResultScreen(tool: Tool.sign, files: [out])));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cache = _cache;
    final pageImage = _pageImages[_pageIndex];
    final pageStamps =
        _stamps.where((s) => s.pageIndex == _pageIndex).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign PDF'),
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
              icon: Tool.sign.style.icon,
              title: 'Sign it — without uploading it',
              message:
                  'Draw your signature once, place it on any page, and save a signed copy. The document never leaves this phone.',
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
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                                  children: [
                                    if (pageImage != null)
                                      Positioned.fill(
                                        child: Image.memory(pageImage,
                                            fit: BoxFit.fill,
                                            gaplessPlayback: true),
                                      )
                                    else
                                      const Center(
                                          child:
                                              CircularProgressIndicator()),
                                    for (final s in pageStamps)
                                      _buildStamp(s, w, h, scheme),
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
                    height: 86,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: cache.doc.pageCount,
                      itemBuilder: (context, i) {
                        final count = _stamps
                            .where((s) => s.pageIndex == i)
                            .length;
                        return GestureDetector(
                          onTap: () => _showPage(i),
                          child: Container(
                            width: 56,
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
                                  future: _cache!.thumb(i),
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
                                        color: Tool.sign.style.base,
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
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addSignature,
                    icon: const Icon(Icons.draw_rounded),
                    label: const Text('Add signature'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Tool.sign.style.base,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _stamps.isEmpty ? null : _save,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(_stamps.isEmpty
                        ? 'Place a signature'
                        : 'Save signed PDF'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStamp(_Placed s, double w, double h, ColorScheme scheme) {
    // The touch box is inflated by [pad] so the corner handles sit INSIDE
    // the hit-test bounds — Flutter ignores touches outside a widget's box
    // even when the visuals overflow it.
    const pad = 24.0;
    final left = s.nx * w;
    final top = s.ny * h;
    final width = s.nw * w;
    final height = width * s.aspect;
    final selected = identical(s, _selected);
    return Positioned(
      left: left - pad,
      top: top - pad,
      width: width + pad * 2,
      height: height + pad * 2,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: () => setState(() => _selected = s),
        onPanStart: (_) => setState(() => _selected = s),
        onPanUpdate: (d) => setState(() {
          s.nx = (s.nx + d.delta.dx / w).clamp(0.0, 1.0 - s.nw);
          s.ny = (s.ny + d.delta.dy / h)
              .clamp(0.0, 1.0 - (width * s.aspect) / h);
        }),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(pad),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    border: Border.all(
                      color:
                          selected ? scheme.primary : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Image.memory(s.png, fit: BoxFit.fill),
                ),
              ),
            ),
            if (selected) ...[
              Positioned(
                right: 0,
                top: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() {
                    _stamps.remove(s);
                    _selected = null;
                  }),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: scheme.error,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.close_rounded,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => HapticFeedback.selectionClick(),
                  onPanUpdate: (d) => setState(() {
                    s.nw = (s.nw + d.delta.dx / w).clamp(0.08, 0.92 - s.nx);
                  }),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.open_in_full_rounded,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet: reuse a saved signature or draw a new one.
class _SignatureSheet extends StatefulWidget {
  final List<File> saved;
  const _SignatureSheet({required this.saved});

  @override
  State<_SignatureSheet> createState() => _SignatureSheetState();
}

class _SignatureSheetState extends State<_SignatureSheet> {
  late final List<File> _saved = [...widget.saved];

  Future<void> _drawNew() async {
    final png = await Navigator.of(context).push<Uint8List>(
      Motion.fadeThrough(const SignaturePadScreen()),
    );
    if (png == null || !mounted) return;
    await SignatureService.save(png);
    if (mounted) Navigator.of(context).pop(png);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your signature',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            if (_saved.isNotEmpty) ...[
              SizedBox(
                height: 84,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _saved.length,
                  itemBuilder: (context, i) {
                    final file = _saved[i];
                    return GestureDetector(
                      onTap: () async {
                        final bytes = await file.readAsBytes();
                        if (context.mounted) {
                          Navigator.of(context).pop(bytes);
                        }
                      },
                      onLongPress: () async {
                        HapticFeedback.mediumImpact();
                        await SignatureService.delete(file);
                        setState(() => _saved.removeAt(i));
                      },
                      child: Container(
                        width: 140,
                        margin: const EdgeInsets.only(right: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: scheme.outlineVariant),
                        ),
                        child: Image.file(file, fit: BoxFit.contain),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              Text('Tap to use · long-press to delete',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 14),
            ],
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
              onPressed: _drawNew,
              icon: const Icon(Icons.draw_rounded),
              label: const Text('Draw new signature'),
            ),
          ],
        ),
      ),
    );
  }
}
