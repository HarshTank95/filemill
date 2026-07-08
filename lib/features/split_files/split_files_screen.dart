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
import '../shared/unlock_helper.dart';

enum _Mode { eachPage, everyN, ranges }

/// Breaks a PDF into MULTIPLE files — one per page, in fixed-size chunks, or
/// by custom ranges. Distinct from Split (which extracts into a single PDF).
class SplitFilesScreen extends StatefulWidget {
  final PickedItem? initial;
  const SplitFilesScreen({super.key, this.initial});

  /// Parses "1-3, 5, 8-10" into groups of 0-based indices, one per token.
  static List<List<int>> parseRangeGroups(String input, int pageCount) {
    final groups = <List<int>>[];
    for (final part in input.split(',')) {
      final token = part.trim();
      if (token.isEmpty) continue;
      final bounds = token.split('-');
      final start = int.tryParse(bounds.first.trim());
      final end = int.tryParse(bounds.last.trim());
      if (start == null || end == null || start > end) continue;
      final group = <int>[
        for (var p = start; p <= end; p++)
          if (p >= 1 && p <= pageCount) p - 1,
      ];
      if (group.isNotEmpty) groups.add(group);
    }
    return groups;
  }

  @override
  State<SplitFilesScreen> createState() => _SplitFilesScreenState();
}

class _SplitFilesScreenState extends State<SplitFilesScreen> {
  PickedItem? _item;
  int _pageCount = 0;
  _Mode _mode = _Mode.eachPage;
  int _chunk = 2;
  final _ranges = TextEditingController(text: '1-3, 4-6');

  @override
  void initState() {
    super.initState();
    _ranges.addListener(() => setState(() {}));
    if (widget.initial != null) _open(widget.initial!);
  }

  @override
  void dispose() {
    _ranges.dispose();
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
    final count = await runBusy<int>(
      context,
      label: 'Opening ${item.name}…',
      task: () async {
        final doc = item.unlockedBytes != null
            ? await RenderedDoc.openData(item.unlockedBytes!)
            : await RenderedDoc.openFile(item.path);
        final n = doc.pageCount;
        await doc.close();
        return n;
      },
    );
    if (count == null) return;
    setState(() {
      _item = item;
      _pageCount = count;
    });
  }

  /// Groups of 0-based page indices, one per output file.
  List<List<int>> _groups() {
    switch (_mode) {
      case _Mode.eachPage:
        return [for (var i = 0; i < _pageCount; i++) [i]];
      case _Mode.everyN:
        final out = <List<int>>[];
        for (var i = 0; i < _pageCount; i += _chunk) {
          out.add([
            for (var j = i; j < i + _chunk && j < _pageCount; j++) j,
          ]);
        }
        return out;
      case _Mode.ranges:
        return SplitFilesScreen.parseRangeGroups(_ranges.text, _pageCount);
    }
  }

  String _fileName(String base, List<int> group) {
    if (group.length == 1) {
      return '${base}_p${(group.first + 1).toString().padLeft(2, '0')}.pdf';
    }
    return '${base}_${group.first + 1}-${group.last + 1}.pdf';
  }

  Future<void> _split() async {
    final item = _item!;
    final groups = _groups();
    if (groups.isEmpty) return;
    final status = ValueNotifier<String?>(null);
    final files = await runBusy<List<OutFile>>(
      context,
      label: 'Splitting into ${groups.length} files…',
      status: status,
      task: () async {
        final Uint8List src = await item.readBytes();
        final base =
            item.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
        final out = <OutFile>[];
        for (var i = 0; i < groups.length; i++) {
          status.value = 'File ${i + 1} of ${groups.length}';
          final bytes = await PdfService.rebuild(
              src, [for (final p in groups[i]) PageEdit(p)]);
          out.add(OutFile(
            name: _fileName(base, groups[i]),
            bytes: bytes,
            mime: 'application/pdf',
          ));
        }
        return out;
      },
    );
    if (files != null && mounted) {
      Navigator.of(context).push(Motion.fadeThrough(
          ResultScreen(tool: Tool.splitFiles, files: files)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = _item;
    final groups = item == null ? const <List<int>>[] : _groups();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Split to Files'),
        actions: [
          if (item != null)
            IconButton(
              tooltip: 'Open another PDF',
              icon: const Icon(Icons.folder_open_rounded),
              onPressed: _pick,
            ),
        ],
      ),
      body: item == null
          ? EmptyState(
              icon: Tool.splitFiles.style.icon,
              title: 'Break it into separate PDFs',
              message:
                  'One file per page, fixed-size chunks, or custom ranges — split a big PDF into many files at once.',
              action: FilledButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Open PDF'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Entrance(
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      leading: GradientBadge(
                          style: Tool.splitFiles.style, size: 46),
                      title: Text(item.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('$_pageCount pages'),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Entrance(
                  index: 1,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final m in const [
                        (_Mode.eachPage, 'Each page'),
                        (_Mode.everyN, 'Every N pages'),
                        (_Mode.ranges, 'Custom ranges'),
                      ])
                        ChoiceChip(
                          label: Text(m.$2),
                          selected: _mode == m.$1,
                          onSelected: (_) => setState(() => _mode = m.$1),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_mode == _Mode.everyN)
                  Entrance(
                    index: 2,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('Pages per file',
                                  style:
                                      Theme.of(context).textTheme.bodyLarge),
                            ),
                            IconButton.filledTonal(
                              onPressed: _chunk > 1
                                  ? () => setState(() => _chunk--)
                                  : null,
                              icon: const Icon(Icons.remove_rounded),
                            ),
                            SizedBox(
                              width: 40,
                              child: Text('$_chunk',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge),
                            ),
                            IconButton.filledTonal(
                              onPressed: _chunk < _pageCount
                                  ? () => setState(() => _chunk++)
                                  : null,
                              icon: const Icon(Icons.add_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_mode == _Mode.ranges)
                  Entrance(
                    index: 2,
                    child: TextField(
                      controller: _ranges,
                      decoration: const InputDecoration(
                        labelText: 'Ranges (one file each)',
                        hintText: 'e.g. 1-3, 4-6, 7-10',
                        prefixIcon: Icon(Icons.tag_rounded),
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                Entrance(
                  index: 3,
                  child: Row(
                    children: [
                      Icon(Icons.folder_zip_rounded,
                          size: 16, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          groups.isEmpty
                              ? 'No valid ranges yet'
                              : 'Will produce ${groups.length} file${groups.length == 1 ? '' : 's'} (saved together as a ZIP).',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: item == null
          ? null
          : BottomBar(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Tool.splitFiles.style.base,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: groups.isEmpty ? null : _split,
                    icon: const Icon(Icons.call_split_rounded),
                    label: Text(groups.isEmpty
                        ? 'Set a valid split'
                        : 'Split into ${groups.length} files'),
                  ),
                ),
              ],
            ),
    );
  }
}
