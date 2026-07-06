import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/models/tool.dart';
import '../../core/services/file_service.dart';
import '../../core/services/history_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../viewer/viewer_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          ValueListenableBuilder<List<HistoryEntry>>(
            valueListenable: HistoryService.entries,
            builder: (context, entries, _) => entries.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Clear all',
                    icon: const Icon(Icons.delete_sweep_rounded),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Clear history?'),
                          content: const Text(
                              'All locally stored copies of your outputs will be deleted from this device.'),
                          actions: [
                            TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, false),
                                child: const Text('Cancel')),
                            FilledButton(
                                onPressed: () =>
                                    Navigator.pop(context, true),
                                child: const Text('Clear')),
                          ],
                        ),
                      );
                      if (confirmed == true) HistoryService.clear();
                    },
                  ),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<HistoryEntry>>(
        valueListenable: HistoryService.entries,
        builder: (context, entries, _) {
          if (entries.isEmpty) {
            return const EmptyState(
              icon: Icons.history_rounded,
              title: 'Nothing here yet',
              message:
                  'Files you create with FileMill appear here — stored only on this device — so you can re-share or re-save them anytime.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: entries.length,
            itemBuilder: (context, i) =>
                HistoryTile(entry: entries[i], margin: 10),
          );
        },
      ),
    );
  }
}

class HistoryTile extends StatelessWidget {
  final HistoryEntry entry;
  final double margin;
  const HistoryTile({super.key, required this.entry, this.margin = 0});

  @override
  Widget build(BuildContext context) {
    final tool = entry.tool ?? Tool.merge;
    return Card(
      margin: EdgeInsets.only(bottom: margin),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: GradientBadge(style: tool.style, size: 44),
        title: Text(entry.fileName,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
            '${tool.title} · ${humanSize(entry.size)} · ${_ago(entry.date)}'),
        trailing: const Icon(Icons.more_horiz_rounded),
        onTap: () => _showActions(context),
      ),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final exists = await File(entry.path).exists();
    if (!context.mounted) return;
    if (!exists) {
      messenger.showSnackBar(const SnackBar(
          content: Text('The stored copy of this file is gone.')));
      HistoryService.remove(entry);
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (entry.fileName.toLowerCase().endsWith('.pdf'))
              ListTile(
                leading: const Icon(Icons.menu_book_rounded),
                title: const Text('Read'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(Motion.fadeThrough(
                      ViewerScreen(path: entry.path, name: entry.fileName)));
                },
              ),
            ListTile(
              leading: const Icon(Icons.share_rounded),
              title: const Text('Share'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final bytes = await File(entry.path).readAsBytes();
                FileService.shareOut([
                  OutFile(
                      name: entry.fileName,
                      bytes: bytes,
                      mime: _mimeFor(entry.fileName)),
                ]);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('Save to device'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final bytes = await File(entry.path).readAsBytes();
                final path = await FileService.saveOut(OutFile(
                    name: entry.fileName,
                    bytes: bytes,
                    mime: _mimeFor(entry.fileName)));
                if (path != null) {
                  messenger.showSnackBar(
                      SnackBar(content: Text('Saved ${entry.fileName}')));
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.error),
              title: const Text('Remove from history'),
              onTap: () {
                Navigator.pop(sheetContext);
                HistoryService.remove(entry);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static String _mimeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.zip')) return 'application/zip';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }

  static String _ago(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}
