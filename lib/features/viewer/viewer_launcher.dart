import 'package:flutter/material.dart';

import '../../core/models/tool.dart';
import '../../core/services/file_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import 'viewer_screen.dart';

/// Entry point for the "Read PDF" tool card: pick a file, then read it.
/// (The viewer is also reachable via the system "Open with" menu.)
class ViewerLauncherScreen extends StatelessWidget {
  const ViewerLauncherScreen({super.key});

  Future<void> _pick(BuildContext context) async {
    final picked = await FileService.pickPdfs(multiple: false);
    if (picked.isEmpty || !context.mounted) return;
    final item = picked.first;
    Navigator.of(context).pushReplacement(
      Motion.fadeThrough(ViewerScreen(path: item.path, name: item.name)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Read PDF')),
      body: EmptyState(
        icon: Tool.viewer.style.icon,
        title: 'A reader that can\'t leak',
        message:
            'Open any PDF in a fast pinch-zoom viewer. Tip: FileMill also appears in "Open with" when you tap a PDF anywhere on your phone.',
        action: FilledButton.icon(
          onPressed: () => _pick(context),
          icon: const Icon(Icons.folder_open_rounded),
          label: const Text('Open PDF'),
        ),
      ),
    );
  }
}
