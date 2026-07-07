import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../core/models/tool.dart';
import '../../core/services/file_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../images_to_pdf/images_to_pdf_screen.dart';
import '../merge/merge_screen.dart';
import '../ocr/ocr_screen.dart';
import '../organize/organize_screen.dart';
import '../pdf_to_images/pdf_to_images_screen.dart';
import '../protect/protect_screen.dart';
import '../sign/sign_screen.dart';
import '../split/split_screen.dart';
import '../viewer/viewer_screen.dart';

/// Landing screen when files are shared to FileMill from another app:
/// shows what arrived and the tools that make sense for it.
class ShareIntakeScreen extends StatefulWidget {
  final List<SharedMediaFile> shared;
  const ShareIntakeScreen({super.key, required this.shared});

  @override
  State<ShareIntakeScreen> createState() => _ShareIntakeScreenState();
}

class _ShareIntakeScreenState extends State<ShareIntakeScreen> {
  List<PickedItem> _pdfs = [];
  List<PickedItem> _images = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pdfs = <PickedItem>[];
    final images = <PickedItem>[];
    for (final f in widget.shared) {
      try {
        final item = await PickedItem.fromPath(f.path);
        final lower = item.name.toLowerCase();
        if (lower.endsWith('.pdf')) {
          pdfs.add(item);
        } else if (f.type == SharedMediaType.image ||
            RegExp(r'\.(png|jpe?g|webp|bmp|gif|heic|heif)$').hasMatch(lower)) {
          images.add(item);
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _pdfs = pdfs;
        _images = images;
        _loading = false;
      });
    }
  }

  void _go(Widget screen) {
    Navigator.of(context).pushReplacement(Motion.sharedAxis(screen));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = _pdfs.length + _images.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Shared with FileMill')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : total == 0
              ? const EmptyState(
                  icon: Icons.help_outline_rounded,
                  title: 'Unsupported files',
                  message:
                      'FileMill works with PDFs and images. The shared files were neither.',
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Entrance(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.inbox_rounded,
                                      color: scheme.primary),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _summary(),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              for (final f in [..._pdfs, ..._images].take(4))
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '• ${f.name}  (${humanSize(f.size)})',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            color: scheme.onSurfaceVariant),
                                  ),
                                ),
                              if (total > 4)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text('…and ${total - 4} more',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                              color:
                                                  scheme.onSurfaceVariant)),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SectionHeader('What do you want to do?'),
                    ..._actions().asMap().entries.map(
                          (e) => Entrance(index: e.key + 1, child: e.value),
                        ),
                  ],
                ),
    );
  }

  String _summary() {
    final parts = <String>[];
    if (_pdfs.isNotEmpty) {
      parts.add('${_pdfs.length} PDF${_pdfs.length == 1 ? '' : 's'}');
    }
    if (_images.isNotEmpty) {
      parts.add('${_images.length} image${_images.length == 1 ? '' : 's'}');
    }
    return 'Received ${parts.join(' and ')}';
  }

  List<Widget> _actions() {
    final actions = <Widget>[];

    void add(Tool tool, String subtitle, VoidCallback onTap) {
      actions.add(Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: GradientBadge(style: tool.style, size: 46),
          title: Text(tool.title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      ));
    }

    if (_pdfs.length > 1) {
      add(Tool.merge, 'Combine the ${_pdfs.length} PDFs into one',
          () => _go(MergeScreen(initial: _pdfs)));
    }
    if (_pdfs.length == 1) {
      final pdf = _pdfs.first;
      add(Tool.viewer, 'Read ${pdf.name}',
          () => _go(ViewerScreen(path: pdf.path, name: pdf.name)));
      add(Tool.sign, 'Place your signature',
          () => _go(SignScreen(initial: pdf)));
      add(Tool.split, 'Extract pages from ${pdf.name}',
          () => _go(SplitScreen(initial: pdf)));
      add(Tool.organize, 'Reorder, rotate or delete pages',
          () => _go(OrganizeScreen(initial: pdf)));
      add(Tool.pdfToImages, 'Export pages as PNG or JPG',
          () => _go(PdfToImagesScreen(initial: pdf)));
      add(Tool.ocr, 'Recognize text on every page',
          () => _go(OcrScreen(initialPdf: pdf)));
      add(Tool.protect, 'Add or remove a password',
          () => _go(ProtectScreen(initial: pdf)));
      add(Tool.merge, 'Combine with more PDFs',
          () => _go(MergeScreen(initial: [pdf])));
    }
    if (_images.isNotEmpty) {
      add(
          Tool.imagesToPdf,
          'Turn ${_images.length} image${_images.length == 1 ? '' : 's'} into a PDF',
          () => _go(ImagesToPdfScreen(initial: _images)));
      add(Tool.ocr, 'Extract text from the image${_images.length == 1 ? '' : 's'}',
          () => _go(OcrScreen(initialImages: _images)));
    }
    return actions;
  }
}
