import 'package:flutter/material.dart';

import '../../core/models/tool.dart';
import '../../core/services/file_service.dart';
import '../../core/services/render_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../merge/merge_screen.dart';
import '../result/result_screen.dart';
import '../shared/page_grid.dart';
import '../shared/unlock_helper.dart';

class PdfToImagesScreen extends StatefulWidget {
  final PickedItem? initial;
  const PdfToImagesScreen({super.key, this.initial});

  @override
  State<PdfToImagesScreen> createState() => _PdfToImagesScreenState();
}

class _PdfToImagesScreenState extends State<PdfToImagesScreen> {
  PickedItem? _item;
  ThumbCache? _cache;
  Set<int> _selected = {};
  bool _png = true;

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
      // Exporting all pages is the common case: preselect everything.
      _selected = {for (var i = 0; i < doc.pageCount; i++) i};
    });
  }

  Future<void> _export() async {
    final cache = _cache!;
    final item = _item!;
    final indices = _selected.toList()..sort();
    final status = ValueNotifier<String?>(null);
    final ext = _png ? 'png' : 'jpg';
    final base =
        item.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    final files = await runBusy<List<OutFile>>(
      context,
      label: 'Exporting pages…',
      status: status,
      task: () async {
        final out = <OutFile>[];
        for (var i = 0; i < indices.length; i++) {
          status.value = 'Page ${i + 1} of ${indices.length}';
          final bytes = await cache.doc.renderPage(
            indices[i],
            scale: 2.5, // ≈180 dpi
            png: _png,
            jpgQuality: 92,
          );
          out.add(OutFile(
            name:
                '${base}_p${(indices[i] + 1).toString().padLeft(2, '0')}.$ext',
            bytes: bytes,
            mime: _png ? 'image/png' : 'image/jpeg',
          ));
        }
        return out;
      },
    );
    if (files != null && mounted) {
      Navigator.of(context).push(Motion.fadeThrough(
          ResultScreen(tool: Tool.pdfToImages, files: files)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cache = _cache;
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF → Images'),
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
              icon: Tool.pdfToImages.style.icon,
              title: 'Pages to pictures',
              message:
                  'Open a PDF and export any pages as crisp PNG or JPG images.',
              action: FilledButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Open PDF'),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                                value: true,
                                label: Text('PNG'),
                                icon: Icon(Icons.high_quality_rounded)),
                            ButtonSegment(
                                value: false,
                                label: Text('JPG'),
                                icon: Icon(Icons.photo_size_select_actual_rounded)),
                          ],
                          selected: {_png},
                          onSelectionChanged: (s) =>
                              setState(() => _png = s.first),
                        ),
                      ),
                    ],
                  ),
                ),
                SelectionBar(
                  pageCount: cache.doc.pageCount,
                  selected: _selected,
                  onChanged: (s) => setState(() => _selected = s),
                ),
                Expanded(
                  child: PageSelectGrid(
                    cache: cache,
                    selected: _selected,
                    onToggle: (i) => setState(() {
                      _selected.contains(i)
                          ? _selected.remove(i)
                          : _selected.add(i);
                    }),
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
                      backgroundColor: Tool.pdfToImages.style.base,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _selected.isEmpty ? null : _export,
                    icon: const Icon(Icons.photo_library_rounded),
                    label: Text(_selected.isEmpty
                        ? 'Select pages'
                        : 'Export ${_selected.length} as ${_png ? 'PNG' : 'JPG'}'),
                  ),
                ),
              ],
            ),
    );
  }
}
