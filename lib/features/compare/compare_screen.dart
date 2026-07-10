import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/models/tool.dart';
import '../../core/services/file_service.dart';
import '../../core/services/pdf_compare_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../../ui/theme.dart';
import '../merge/merge_screen.dart' show BottomBar;
import '../shared/unlock_helper.dart';
import 'compare_result_screen.dart';

/// Compare PDFs: pick two versions of a document and get an exact,
/// on-device diff — an Acrobat-Pro-only feature, free and private here.
class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key});

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  PickedItem? _original, _revised;

  Future<void> _pick(bool original) async {
    final picked = await FileService.pickPdfs(multiple: false);
    if (picked.isEmpty) return;
    setState(() {
      if (original) {
        _original = picked.first;
      } else {
        _revised = picked.first;
      }
    });
  }

  void _swap() => setState(() {
        final t = _original;
        _original = _revised;
        _revised = t;
      });

  Future<void> _compare() async {
    final original = _original!, revised = _revised!;
    if (!await ensureUnlocked(context, original)) return;
    if (!mounted || !await ensureUnlocked(context, revised)) return;
    if (!mounted) return;
    final outcome = await runBusy<(CompareResult, Uint8List, Uint8List)>(
      context,
      label: 'Comparing word by word…',
      task: () async {
        final a = original.unlockedBytes ?? await original.readBytes();
        final b = revised.unlockedBytes ?? await revised.readBytes();
        return (await PdfCompareService.compare(a, b), a, b);
      },
    );
    if (outcome == null || !mounted) return;
    Navigator.of(context).push(Motion.fadeThrough(CompareResultScreen(
      result: outcome.$1,
      originalBytes: outcome.$2,
      revisedBytes: outcome.$3,
      originalName: original.name,
      revisedName: revised.name,
    )));
  }

  @override
  Widget build(BuildContext context) {
    final ready = _original != null && _revised != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Compare PDFs')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Entrance(child: const _Note()),
          const SizedBox(height: 16),
          Entrance(
            index: 1,
            child: _Slot(
              label: 'ORIGINAL',
              hint: 'The earlier version',
              item: _original,
              onPick: () => _pick(true),
            ),
          ),
          Center(
            child: IconButton(
              tooltip: 'Swap',
              onPressed: ready ? _swap : null,
              icon: const Icon(Icons.swap_vert_rounded),
            ),
          ),
          Entrance(
            index: 2,
            child: _Slot(
              label: 'REVISED',
              hint: 'The newer version',
              item: _revised,
              onPick: () => _pick(false),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomBar(
        children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Tool.comparePdf.style.base,
                foregroundColor: Colors.white,
              ),
              onPressed: ready ? _compare : null,
              icon: const Icon(Icons.compare_rounded),
              label: const Text('Find the differences'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  final String label, hint;
  final PickedItem? item;
  final VoidCallback onPick;
  const _Slot({
    required this.label,
    required this.hint,
    required this.item,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final i = item;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onPick,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Tool.comparePdf.style.base.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(label,
                    style: AppTheme.manrope(800,
                        size: 11.5, color: Tool.comparePdf.style.base)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: i == null
                    ? Text(hint,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(i.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(humanSize(i.size),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ),
              ),
              Icon(i == null ? Icons.add_rounded : Icons.folder_open_rounded,
                  color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: Tool.comparePdf.style.base.withValues(alpha: 0.07),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.compare_rounded, color: Tool.comparePdf.style.base),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('What changed between two versions?',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Every added, removed or edited word is found by exact '
              'comparison of the documents\' own text — nothing is uploaded, '
              'nothing is guessed. Scanned (image-only) pages are compared '
              'visually with the overlay view.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
