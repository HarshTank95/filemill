import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/models/tool.dart';
import '../../core/services/file_service.dart';
import '../../core/services/pdf_service.dart';
import '../../core/services/render_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../merge/merge_screen.dart';
import '../result/result_screen.dart';
import '../shared/page_grid.dart';
import '../shared/unlock_helper.dart';

class SplitScreen extends StatefulWidget {
  final PickedItem? initial;
  const SplitScreen({super.key, this.initial});

  @override
  State<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends State<SplitScreen> {
  PickedItem? _item;
  ThumbCache? _cache;
  Set<int> _selected = {};

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
      _selected = {};
    });
  }

  Future<void> _extract() async {
    final item = _item!;
    final indices = _selected.toList()..sort();
    final out = await runBusy<OutFile>(
      context,
      label: 'Extracting ${indices.length} pages…',
      task: () async {
        final Uint8List src = await item.readBytes();
        final bytes = await PdfService.rebuild(
            src, [for (final i in indices) PageEdit(i)]);
        final base = item.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
        return OutFile(
          name: '${base}_pages.pdf',
          bytes: bytes,
          mime: 'application/pdf',
        );
      },
    );
    if (out != null && mounted) {
      Navigator.of(context).push(Motion.fadeThrough(
          ResultScreen(tool: Tool.split, files: [out])));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cache = _cache;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Split PDF'),
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
              icon: Tool.split.style.icon,
              title: 'Extract pages',
              message:
                  'Open a PDF and tap the pages you want in the new file.',
              action: FilledButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Open PDF'),
              ),
            )
          : Column(
              children: [
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
                      backgroundColor: Tool.split.style.base,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _selected.isEmpty ? null : _extract,
                    icon: const Icon(Icons.content_cut_rounded),
                    label: Text(_selected.isEmpty
                        ? 'Select pages'
                        : 'Extract ${_selected.length} page${_selected.length == 1 ? '' : 's'}'),
                  ),
                ),
              ],
            ),
    );
  }
}
