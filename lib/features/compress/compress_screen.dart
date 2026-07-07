import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/models/tool.dart';
import '../../core/services/compress_service.dart';
import '../../core/services/file_service.dart';
import '../../core/services/render_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../merge/merge_screen.dart';
import '../result/result_screen.dart';
import '../shared/unlock_helper.dart';

enum _Mode { quality, target }

class CompressScreen extends StatefulWidget {
  final PickedItem? initial;
  const CompressScreen({super.key, this.initial});

  @override
  State<CompressScreen> createState() => _CompressScreenState();
}

class _CompressScreenState extends State<CompressScreen> {
  PickedItem? _item;
  RenderedDoc? _doc;
  _Mode _mode = _Mode.quality;
  int _preset = 1; // 0 high, 1 balanced, 2 small
  int _targetMb = 2;

  static const _presets = [
    ('High quality', 'Sharper pages, larger file', 2.0, 80),
    ('Balanced', 'Good quality, much smaller', 1.3, 60),
    ('Smallest', 'Max compression for uploads', 0.9, 40),
  ];

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
      label: 'Compressing on-device…',
      status: status,
      task: () async {
        final Uint8List bytes;
        if (_mode == _Mode.target) {
          bytes = await CompressService.fitUnder(
            doc,
            targetBytes: _targetMb * 1024 * 1024,
            onStatus: (s) => status.value = s,
          );
        } else {
          bytes = await CompressService.compress(
            doc,
            scale: _presets[_preset].$3,
            jpgQuality: _presets[_preset].$4,
            onProgress: (done, total) =>
                status.value = 'Page $done of $total',
          );
        }
        final base =
            item.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
        return OutFile(
          name: '${base}_compressed.pdf',
          bytes: bytes,
          mime: 'application/pdf',
        );
      },
    );
    if (out == null || !mounted) return;
    final saved = item.size - out.bytes.length;
    final message = saved > 0
        ? '${humanSize(item.size)} → ${humanSize(out.bytes.length)} (saved ${(saved * 100 / item.size).round()}%)'
        : 'This PDF was already smaller than the re-rendered version.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    if (_mode == _Mode.target && out.bytes.length > _targetMb * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Could not fit under $_targetMb MB — this is the smallest result.')));
    }
    Navigator.of(context).push(
        Motion.fadeThrough(ResultScreen(tool: Tool.compress, files: [out])));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = _item;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compress PDF'),
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
              icon: Tool.compress.style.icon,
              title: 'Shrink it for that upload',
              message:
                  'Email limits, portal limits, WhatsApp — make any PDF fit, entirely on this phone.',
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
                          style: Tool.compress.style, size: 46),
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
                  child: SegmentedButton<_Mode>(
                    segments: const [
                      ButtonSegment(
                          value: _Mode.quality,
                          label: Text('Quality'),
                          icon: Icon(Icons.tune_rounded)),
                      ButtonSegment(
                          value: _Mode.target,
                          label: Text('Fit under size'),
                          icon: Icon(Icons.flag_rounded)),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) =>
                        setState(() => _mode = s.first),
                  ),
                ),
                const SizedBox(height: 16),
                if (_mode == _Mode.quality)
                  for (var i = 0; i < _presets.length; i++)
                    Entrance(
                      index: 2 + i,
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: BorderSide(
                            color: _preset == i
                                ? Tool.compress.style.base
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 4),
                          title: Text(_presets[i].$1),
                          subtitle: Text(_presets[i].$2),
                          trailing: AnimatedScale(
                            duration: const Duration(milliseconds: 160),
                            scale: _preset == i ? 1 : 0,
                            curve: Curves.easeOutBack,
                            child: Icon(Icons.check_circle_rounded,
                                color: Tool.compress.style.base),
                          ),
                          onTap: () => setState(() => _preset = i),
                        ),
                      ),
                    )
                else
                  Entrance(
                    index: 2,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Target size',
                                style:
                                    Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              children: [
                                for (final mb in [1, 2, 5, 10])
                                  ChoiceChip(
                                    label: Text('$mb MB'),
                                    selected: _targetMb == mb,
                                    onSelected: (_) =>
                                        setState(() => _targetMb = mb),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'FileMill tries progressively stronger compression until the file fits.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Entrance(
                  index: 6,
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 15, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Pages are re-rendered as images — text won\'t be selectable in the compressed copy. Best for sharing and uploads.',
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
                      backgroundColor: Tool.compress.style.base,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _run,
                    icon: const Icon(Icons.compress_rounded),
                    label: Text(_mode == _Mode.target
                        ? 'Fit under $_targetMb MB'
                        : 'Compress (${_presets[_preset].$1})'),
                  ),
                ),
              ],
            ),
    );
  }
}
