import 'package:flutter/material.dart';

import '../../core/models/tool.dart';
import '../../core/services/file_service.dart';
import '../../core/services/ocr_service.dart';
import '../../core/services/render_service.dart';
import '../../core/services/searchable_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../merge/merge_screen.dart';
import '../result/result_screen.dart';
import '../shared/unlock_helper.dart';

/// Turns a scanned PDF into a searchable one: pages are re-rendered and an
/// invisible OCR text layer is placed over the printed words.
class SearchableScreen extends StatefulWidget {
  final PickedItem? initial;
  const SearchableScreen({super.key, this.initial});

  @override
  State<SearchableScreen> createState() => _SearchableScreenState();
}

class _SearchableScreenState extends State<SearchableScreen> {
  PickedItem? _item;
  RenderedDoc? _doc;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _open(widget.initial!);
  }

  @override
  void dispose() {
    _doc?.close();
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
    _doc?.close();
    setState(() {
      _item = item;
      _doc = doc;
    });
  }

  Future<void> _run() async {
    final item = _item!;
    final doc = _doc!;
    final status = ValueNotifier<String?>(null);
    final out = await runBusy<OutFile>(
      context,
      label: 'Reading & rebuilding on-device…',
      status: status,
      task: () async {
        const scale = 2.5;
        final recognizer = OcrService.newRecognizer();
        final pages = <SearchablePage>[];
        try {
          for (var i = 0; i < doc.pageCount; i++) {
            status.value = 'Page ${i + 1} of ${doc.pageCount}';
            final size = await doc.pageSize(i);
            final jpg = await doc.renderPage(i,
                scale: scale, png: false, jpgQuality: 85);
            final temp = await FileService.writeTemp('ocr_page_$i.jpg', jpg);
            final lines = await OcrService.imageLines(temp.path, recognizer);
            final imgW = size.width * scale;
            final imgH = size.height * scale;
            pages.add(SearchablePage(
              jpg: jpg,
              widthPt: size.width,
              heightPt: size.height,
              lines: [
                for (final l in lines)
                  SearchableLine(
                    l.text,
                    (l.box.left / imgW).clamp(0.0, 1.0),
                    (l.box.top / imgH).clamp(0.0, 1.0),
                    (l.box.width / imgW).clamp(0.001, 1.0),
                    (l.box.height / imgH).clamp(0.001, 1.0),
                  ),
              ],
            ));
          }
        } finally {
          await recognizer.close();
        }
        status.value = 'Building searchable PDF';
        final bytes = await SearchableService.assemble(pages);
        final base =
            item.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
        return OutFile(
          name: '${base}_searchable.pdf',
          bytes: bytes,
          mime: 'application/pdf',
        );
      },
    );
    if (out != null && mounted) {
      Navigator.of(context).push(Motion.fadeThrough(
          ResultScreen(tool: Tool.searchable, files: [out])));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = _item;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Searchable PDF'),
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
              icon: Tool.searchable.style.icon,
              title: 'Make scans searchable',
              message:
                  'FileMill reads every page on-device and hides a selectable text layer over the words — the scan looks the same, but you can search and copy it.',
              action: FilledButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Open scanned PDF'),
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
                          style: Tool.searchable.style, size: 46),
                      title: Text(item.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${humanSize(item.size)} · ${_doc?.pageCount ?? '…'} pages'),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Entrance(
                  index: 1,
                  child: Card(
                    color: Tool.searchable.style.base.withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.manage_search_rounded,
                                  color: Tool.searchable.style.base),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text('What you\'ll get',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '• Search works in any PDF viewer\n'
                            '• Text can be selected and copied\n'
                            '• Pages look identical to the original\n'
                            '• Everything happens on this phone',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(height: 1.6),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Entrance(
                  index: 2,
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 15, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Pages are re-rendered as images with hidden text. Works best on clear scans with Latin-script text.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
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
                      backgroundColor: Tool.searchable.style.base,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _run,
                    icon: const Icon(Icons.manage_search_rounded),
                    label: const Text('Make searchable'),
                  ),
                ),
              ],
            ),
    );
  }
}
