import 'package:flutter/material.dart';

import '../../core/models/tool.dart';
import '../../core/services/file_service.dart';
import '../../core/services/pdf_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../../ui/theme.dart';
import '../result/result_screen.dart';

class MergeScreen extends StatefulWidget {
  final List<PickedItem> initial;
  const MergeScreen({super.key, this.initial = const []});

  @override
  State<MergeScreen> createState() => _MergeScreenState();
}

class _MergeScreenState extends State<MergeScreen> {
  late final List<PickedItem> _items = [...widget.initial];

  Future<void> _add() async {
    final picked = await FileService.pickPdfs();
    if (picked.isEmpty) return;
    setState(() => _items.addAll(picked));
  }

  Future<void> _merge() async {
    final result = await runBusy<OutFile>(
      context,
      label: 'Merging ${_items.length} PDFs…',
      task: () async {
        final docs = [for (final f in _items) await f.readBytes()];
        final bytes = await PdfService.merge(docs);
        return OutFile(
          name: 'merged_${_items.length}_files.pdf',
          bytes: bytes,
          mime: 'application/pdf',
        );
      },
    );
    if (result != null && mounted) {
      Navigator.of(context).push(
        Motion.fadeThrough(ResultScreen(tool: Tool.merge, files: [result])),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Merge PDF')),
      body: _items.isEmpty
          ? EmptyState(
              icon: Tool.merge.style.icon,
              title: 'Combine PDFs into one',
              message:
                  'Pick two or more PDFs, drag to set the order, then merge — all on your device.',
              action: FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add PDFs'),
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
              itemCount: _items.length,
              proxyDecorator: (child, index, animation) =>
                  Material(color: Colors.transparent, child: child),
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  _items.insert(newIndex, _items.removeAt(oldIndex));
                });
              },
              itemBuilder: (context, i) {
                final item = _items[i];
                return Entrance(
                  key: ValueKey('${item.path}_$i'),
                  index: i,
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Tool.merge.style.base.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text('${i + 1}',
                            style: AppTheme.grotesk(700,
                                size: 17, color: Tool.merge.style.base)),
                      ),
                      title: Text(item.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(humanSize(item.size)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.close_rounded,
                                color: scheme.onSurfaceVariant),
                            onPressed: () =>
                                setState(() => _items.removeAt(i)),
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            child: Icon(Icons.drag_handle_rounded,
                                color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: _items.isEmpty
          ? null
          : BottomBar(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Tool.merge.style.base,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _items.length >= 2 ? _merge : null,
                    icon: const Icon(Icons.merge_rounded),
                    label: Text('Merge ${_items.length} PDFs'),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Safe-area bottom action bar shared by tool screens.
class BottomBar extends StatelessWidget {
  final List<Widget> children;
  const BottomBar({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
            top: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.4))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(children: children),
        ),
      ),
    );
  }
}
