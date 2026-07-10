import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/tool.dart';
import '../../core/services/pdf_compare_service.dart';
import '../../core/services/render_service.dart';
import '../../ui/common.dart';
import '../../ui/theme.dart';

const _removedColor = Color(0xFFE53935);
const _addedColor = Color(0xFF2E7D32);

/// Diff results: a change list (tap to jump) and a side-by-side page view
/// with word-accurate highlights, plus an onion-skin overlay for scans.
class CompareResultScreen extends StatefulWidget {
  final CompareResult result;
  final Uint8List originalBytes, revisedBytes;
  final String originalName, revisedName;
  const CompareResultScreen({
    super.key,
    required this.result,
    required this.originalBytes,
    required this.revisedBytes,
    required this.originalName,
    required this.revisedName,
  });

  @override
  State<CompareResultScreen> createState() => _CompareResultScreenState();
}

class _CompareResultScreenState extends State<CompareResultScreen> {
  RenderedDoc? _docA, _docB;
  // Memoized render futures: repeated builds and rapid stepping reuse the
  // SAME future instead of enqueueing duplicate renders (which serialized
  // into a backlog and froze the pages view).
  final _pageFutures = <String, Future<Uint8List>>{};
  int _tab = 0;
  int _current = 0;
  bool _overlay = false;
  double _onion = 0.5;
  int _overlayPage = 0;
  // Overlay images are held in state so slider drags never re-trigger loads.
  Uint8List? _ovA, _ovB;

  CompareResult get r => widget.result;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final a = await RenderedDoc.openData(widget.originalBytes);
    final b = await RenderedDoc.openData(widget.revisedBytes);
    if (!mounted) {
      await a.close();
      await b.close();
      return;
    }
    setState(() {
      _docA = a;
      _docB = b;
    });
  }

  @override
  void dispose() {
    _docA?.close();
    _docB?.close();
    super.dispose();
  }

  Future<Uint8List?> _page(bool original, int index) {
    final doc = original ? _docA : _docB;
    if (doc == null) return Future.value(null);
    final key = '${original ? 'a' : 'b'}$index';
    var f = _pageFutures[key];
    if (f == null) {
      // Scale 1.6 (~115 dpi) renders ~2.4x faster than 2.5 — heavy vector
      // pages were freezing the UI for the whole render otherwise.
      f = doc.renderPage(index, scale: 1.6, png: false, jpgQuality: 85);
      if (_pageFutures.length > 12) {
        _pageFutures.remove(_pageFutures.keys.first);
      }
      _pageFutures[key] = f;
    }
    return f;
  }

  /// Warms the pages of block [i], strictly AFTER the currently shown pages
  /// have finished — prefetching must never delay what's on screen.
  void _prefetchBlockAfterCurrent(int i) {
    if (i < 0 || i >= r.blocks.length) return;
    final cur = r.blocks[_current];
    Future.wait([_page(true, cur.pageA), _page(false, cur.pageB)])
        .whenComplete(() {
      if (!mounted) return;
      final b = r.blocks[i];
      _page(true, b.pageA);
      _page(false, b.pageB);
    });
  }

  void _openBlock(int i) {
    HapticFeedback.selectionClick();
    setState(() {
      _current = i;
      _tab = 1;
      _overlay = false;
    });
    _prefetchBlockAfterCurrent(i + 1);
  }

  void _step(int delta) {
    if (r.blocks.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(
        () => _current = (_current + delta).clamp(0, r.blocks.length - 1));
    // Warm the next stop in the same direction once this one is visible.
    _prefetchBlockAfterCurrent(_current + delta);
  }

  int get _maxOverlayPage =>
      (r.pagesA > r.pagesB ? r.pagesA : r.pagesB) - 1;

  void _setOverlayPage(int page) {
    setState(() {
      _overlayPage = page.clamp(0, _maxOverlayPage);
      _ovA = null;
      _ovB = null;
    });
    _loadOverlay();
  }

  Future<void> _loadOverlay() async {
    final p = _overlayPage;
    final a = p < r.pagesA ? await _page(true, p) : null;
    final b = p < r.pagesB ? await _page(false, p) : null;
    if (!mounted || p != _overlayPage) return;
    setState(() {
      _ovA = a;
      _ovB = b;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Differences'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                    value: 0,
                    label: Text('Changes'),
                    icon: Icon(Icons.list_alt_rounded)),
                ButtonSegment(
                    value: 1,
                    label: Text('Pages'),
                    icon: Icon(Icons.auto_stories_rounded)),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
          ),
        ),
      ),
      body: _tab == 0 ? _changesTab() : _pagesTab(),
    );
  }

  // ---------------------------------------------------------------- changes

  Widget _changesTab() {
    final scheme = Theme.of(context).colorScheme;
    if (r.identicalText) {
      return EmptyState(
        icon: Icons.verified_rounded,
        title: 'No text differences',
        message: r.scannedPagesA.isEmpty && r.scannedPagesB.isEmpty
            ? 'Every word of both documents matches exactly.'
            : 'The text layers match. Some pages are scans — check them '
                'with the overlay view on the Pages tab.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: r.blocks.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _statsCard();
        final b = r.blocks[i - 1];
        final (chipColor, chipText) = switch (b.kind) {
          ChangeKind.added => (_addedColor, 'ADDED'),
          ChangeKind.removed => (_removedColor, 'REMOVED'),
          ChangeKind.changed => (const Color(0xFFEF9A00), 'EDITED'),
        };
        return Card(
          margin: const EdgeInsets.only(top: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => _openBlock(i - 1),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: chipColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(chipText,
                            style: AppTheme.manrope(800,
                                size: 10.5, color: chipColor)),
                      ),
                      const Spacer(),
                      Text(
                        // Same page in both versions reads as just "p1";
                        // drifted content shows "p2 → p3".
                        b.kind == ChangeKind.added
                            ? 'p${b.pageB + 1}'
                            : b.kind == ChangeKind.removed
                                ? 'p${b.pageA + 1}'
                                : b.pageA == b.pageB
                                    ? 'p${b.pageA + 1}'
                                    : 'p${b.pageA + 1} → p${b.pageB + 1}',
                        style: AppTheme.manrope(650,
                            size: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  RichText(
                    text: TextSpan(
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(height: 1.45),
                      children: [
                        if (b.contextBefore.isNotEmpty)
                          TextSpan(
                              text: '…${b.contextBefore} ',
                              style:
                                  TextStyle(color: scheme.onSurfaceVariant)),
                        if (b.before.isNotEmpty)
                          TextSpan(
                            text: b.beforeText,
                            style: const TextStyle(
                              color: _removedColor,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        if (b.before.isNotEmpty && b.after.isNotEmpty)
                          const TextSpan(text: '  '),
                        if (b.after.isNotEmpty)
                          TextSpan(
                            text: b.afterText,
                            style: const TextStyle(
                                color: _addedColor,
                                fontWeight: FontWeight.w600),
                          ),
                        if (b.contextAfter.isNotEmpty)
                          TextSpan(
                              text: ' ${b.contextAfter}…',
                              style:
                                  TextStyle(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _statsCard() {
    final scheme = Theme.of(context).colorScheme;
    Widget stat(Color c, String label, int n) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text('$n $label', style: AppTheme.manrope(700, size: 12.5)),
          ],
        );
    return Card(
      color: Tool.comparePdf.style.base.withValues(alpha: 0.07),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${r.blocks.length} difference${r.blocks.length == 1 ? '' : 's'} found',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                stat(const Color(0xFFEF9A00), 'edited', r.edited),
                stat(_addedColor, 'added', r.added),
                stat(_removedColor, 'removed', r.removed),
              ],
            ),
            if (r.scannedPagesA.isNotEmpty || r.scannedPagesB.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Some pages are scans without a text layer — compare those '
                'visually on the Pages tab (Overlay mode).',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ pages

  Widget _pagesTab() {
    final hasBlocks = r.blocks.isNotEmpty;
    final block = hasBlocks ? r.blocks[_current] : null;
    final pageA = _overlay ? _overlayPage : (block?.pageA ?? 0);
    final pageB = _overlay ? _overlayPage : (block?.pageB ?? 0);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('Side by side'),
                selected: !_overlay,
                onSelected: (_) => setState(() => _overlay = false),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Overlay'),
                selected: _overlay,
                onSelected: (_) {
                  setState(() => _overlay = true);
                  _setOverlayPage(pageA);
                },
              ),
              const Spacer(),
              if (_overlay) ...[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _overlayPage > 0
                      ? () => _setOverlayPage(_overlayPage - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Text('Page ${_overlayPage + 1}/${_maxOverlayPage + 1}',
                    style: AppTheme.manrope(700, size: 13)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _overlayPage < _maxOverlayPage
                      ? () => _setOverlayPage(_overlayPage + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ] else if (hasBlocks) ...[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _current > 0 ? () => _step(-1) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                // Steps through CHANGES — each pane follows the change to
                // its own page, so the two sides can show different pages.
                Text('Change ${_current + 1}/${r.blocks.length}',
                    style: AppTheme.manrope(700, size: 13)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed:
                      _current < r.blocks.length - 1 ? () => _step(1) : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: _overlay ? _overlayView() : _sideBySide(pageA, pageB),
        ),
        if (_overlay)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Text('Original', style: AppTheme.manrope(650, size: 11.5)),
                  Expanded(
                    child: Slider(
                      value: _onion,
                      onChanged: (v) => setState(() => _onion = v),
                    ),
                  ),
                  Text('Revised', style: AppTheme.manrope(650, size: 11.5)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _sideBySide(int pageA, int pageB) {
    return Column(
      children: [
        Expanded(
          child: _PagePane(
            role: 'ORIGINAL',
            name: widget.originalName,
            page: pageA,
            image: _page(true, pageA),
            pageWidth: r.pageWidthsA[pageA],
            pageHeight: r.pageHeightsA[pageA],
            highlights: _highlightsFor(pageA, original: true),
            scanned: r.scannedPagesA.contains(pageA),
          ),
        ),
        Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
        Expanded(
          child: _PagePane(
            role: 'REVISED',
            name: widget.revisedName,
            page: pageB,
            image: _page(false, pageB),
            pageWidth: r.pageWidthsB[pageB],
            pageHeight: r.pageHeightsB[pageB],
            highlights: _highlightsFor(pageB, original: false),
            scanned: r.scannedPagesB.contains(pageB),
          ),
        ),
      ],
    );
  }

  Widget _overlayView() {
    final scheme = Theme.of(context).colorScheme;
    final a = _ovA, b = _ovB;
    final missingA = _overlayPage >= r.pagesA;
    final missingB = _overlayPage >= r.pagesB;
    if (a == null && b == null && !missingA && !missingB) {
      return const Center(child: CircularProgressIndicator());
    }
    Widget missing(String which) => Container(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(24),
          child: Text(
            '$which has no page ${_overlayPage + 1}',
            style: AppTheme.manrope(650,
                size: 13, color: scheme.onSurfaceVariant),
          ),
        );
    return InteractiveViewer(
      maxScale: 6,
      child: Center(
        child: Stack(
          children: [
            if (a != null)
              Image.memory(a, gaplessPlayback: true)
            else if (missingA && b != null)
              // Keep the revised page visible against a placeholder base.
              Opacity(opacity: 0, child: Image.memory(b)),
            Positioned.fill(
              child: missingB
                  ? Opacity(opacity: _onion, child: missing('Revised'))
                  : b == null
                      ? const SizedBox.shrink()
                      : Opacity(
                          opacity: _onion,
                          child: Image.memory(b,
                              fit: BoxFit.fill, gaplessPlayback: true),
                        ),
            ),
            if (missingA && b != null)
              Positioned.fill(
                child: Opacity(opacity: 1 - _onion, child: missing('Original')),
              ),
          ],
        ),
      ),
    );
  }

  List<_Highlight> _highlightsFor(int page, {required bool original}) {
    final out = <_Highlight>[];
    for (var i = 0; i < r.blocks.length; i++) {
      final b = r.blocks[i];
      final tokens = original ? b.before : b.after;
      final color = original ? _removedColor : _addedColor;
      for (final t in tokens) {
        if (t.page != page) continue;
        out.add(_Highlight(
          Rect.fromLTWH(t.x, t.y, t.w, t.h),
          color,
          strong: i == _current,
        ));
      }
    }
    return out;
  }
}

class _Highlight {
  final Rect rect; // PDF points
  final Color color;
  final bool strong;
  const _Highlight(this.rect, this.color, {this.strong = false});
}

class _PagePane extends StatelessWidget {
  final String role, name;
  final int page;
  final Future<Uint8List?> image;
  final double pageWidth, pageHeight;
  final List<_Highlight> highlights;
  final bool scanned;
  const _PagePane({
    required this.role,
    required this.name,
    required this.page,
    required this.image,
    required this.pageWidth,
    required this.pageHeight,
    required this.highlights,
    required this.scanned,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
          child: Row(
            children: [
              Text(role, style: AppTheme.manrope(800, size: 11)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.manrope(600,
                        size: 11.5, color: scheme.onSurfaceVariant)),
              ),
              const SizedBox(width: 8),
              Text('p${page + 1}${scanned ? ' · scan' : ''}',
                  style: AppTheme.manrope(750, size: 12)),
            ],
          ),
        ),
        Expanded(
          child: InteractiveViewer(
            maxScale: 6,
            child: Center(
              child: FutureBuilder<Uint8List?>(
                future: image,
                builder: (context, snap) {
                  final bytes = snap.data;
                  if (bytes == null) {
                    return const CircularProgressIndicator();
                  }
                  return AspectRatio(
                    aspectRatio: pageWidth / pageHeight,
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final sx = box.maxWidth / pageWidth;
                        final sy = box.maxHeight / pageHeight;
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: Image.memory(bytes,
                                  fit: BoxFit.fill, gaplessPlayback: true),
                            ),
                            for (final h in highlights)
                              Positioned(
                                left: (h.rect.left - 1) * sx,
                                top: (h.rect.top - 1) * sy,
                                width: (h.rect.width + 2) * sx,
                                height: (h.rect.height + 2) * sy,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: h.color
                                        .withValues(alpha: h.strong ? 0.4 : 0.2),
                                    borderRadius: BorderRadius.circular(2),
                                    border: h.strong
                                        ? Border.all(color: h.color, width: 1.4)
                                        : null,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
