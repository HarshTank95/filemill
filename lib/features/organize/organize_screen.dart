import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

import '../../core/models/tool.dart';
import '../../core/services/file_service.dart';
import '../../core/services/pdf_service.dart';
import '../../core/services/render_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../merge/merge_screen.dart';
import '../result/result_screen.dart';
import '../shared/page_grid.dart';

class _OrgPage {
  final int srcIndex;
  int turns = 0;
  _OrgPage(this.srcIndex);
}

/// Reorder (drag), rotate and delete pages, then save a rebuilt PDF.
class OrganizeScreen extends StatefulWidget {
  final PickedItem? initial;
  const OrganizeScreen({super.key, this.initial});

  @override
  State<OrganizeScreen> createState() => _OrganizeScreenState();
}

class _OrganizeScreenState extends State<OrganizeScreen> {
  PickedItem? _item;
  ThumbCache? _cache;
  List<_OrgPage> _pages = [];
  int _originalCount = 0;

  bool get _dirty =>
      _pages.length != _originalCount ||
      _pages.asMap().entries.any(
          (e) => e.value.srcIndex != e.key || e.value.turns % 4 != 0);

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
    final doc = await runBusy<RenderedDoc>(
      context,
      label: 'Opening ${item.name}…',
      task: () => RenderedDoc.openFile(item.path),
    );
    if (doc == null) return;
    _cache?.doc.close();
    setState(() {
      _item = item;
      _cache = ThumbCache(doc);
      _originalCount = doc.pageCount;
      _pages = [for (var i = 0; i < doc.pageCount; i++) _OrgPage(i)];
    });
  }

  Future<void> _save() async {
    final item = _item!;
    final out = await runBusy<OutFile>(
      context,
      label: 'Rebuilding PDF…',
      task: () async {
        final src = await item.readBytes();
        final bytes = await PdfService.rebuild(
          src,
          [for (final p in _pages) PageEdit(p.srcIndex, p.turns % 4)],
        );
        final base =
            item.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
        return OutFile(
          name: '${base}_organized.pdf',
          bytes: bytes,
          mime: 'application/pdf',
        );
      },
    );
    if (out != null && mounted) {
      Navigator.of(context).push(Motion.fadeThrough(
          ResultScreen(tool: Tool.organize, files: [out])));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cache = _cache;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Organize'),
        actions: [
          if (_item != null)
            IconButton(
              tooltip: 'Open another PDF',
              icon: const Icon(Icons.folder_open_rounded),
              onPressed: _pick,
            ),
        ],
      ),
      body: cache == null
          ? EmptyState(
              icon: Tool.organize.style.icon,
              title: 'Reorder, rotate, delete',
              message:
                  'Open a PDF, drag pages to rearrange, rotate or remove them, then save a new copy.',
              action: FilledButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Open PDF'),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      Icon(Icons.touch_app_rounded,
                          size: 16, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Long-press and drag to reorder · ${_pages.length} pages',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableGridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 130,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.62,
                    ),
                    itemCount: _pages.length,
                    onReorder: (oldIndex, newIndex) {
                      HapticFeedback.mediumImpact();
                      setState(() =>
                          _pages.insert(newIndex, _pages.removeAt(oldIndex)));
                    },
                    itemBuilder: (context, i) {
                      final page = _pages[i];
                      return Column(
                        key: ValueKey(page.srcIndex),
                        children: [
                          Expanded(
                            child: PageThumb(
                              cache: cache,
                              index: page.srcIndex,
                              quarterTurns: page.turns % 4,
                            ),
                          ),
                          SizedBox(
                            height: 36,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  iconSize: 19,
                                  tooltip: 'Rotate',
                                  icon: Icon(Icons.rotate_90_degrees_cw_rounded,
                                      color: scheme.primary),
                                  onPressed: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => page.turns++);
                                  },
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  iconSize: 19,
                                  tooltip: 'Delete',
                                  icon: Icon(Icons.delete_outline_rounded,
                                      color: scheme.error),
                                  onPressed: _pages.length <= 1
                                      ? null
                                      : () {
                                          HapticFeedback.selectionClick();
                                          setState(() => _pages.removeAt(i));
                                        },
                                ),
                              ],
                            ),
                          ),
                        ],
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
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Tool.organize.style.base,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _dirty ? _save : null,
                    icon: const Icon(Icons.save_alt_rounded),
                    label: Text(_dirty ? 'Save new PDF' : 'No changes yet'),
                  ),
                ),
              ],
            ),
    );
  }
}
