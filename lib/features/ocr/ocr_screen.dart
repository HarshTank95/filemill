import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/tool.dart';
import '../../core/services/file_service.dart';
import '../../core/services/history_service.dart';
import '../../core/services/ocr_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../../ui/theme.dart';
import '../merge/merge_screen.dart';
import '../scan/crop_screen.dart';

class OcrScreen extends StatelessWidget {
  final PickedItem? initialPdf;
  final List<PickedItem> initialImages;
  const OcrScreen({super.key, this.initialPdf, this.initialImages = const []});

  @override
  Widget build(BuildContext context) {
    // Share-sheet entries skip the source chooser entirely.
    if (initialPdf != null || initialImages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (initialPdf != null) {
          _runPdf(context, initialPdf!);
        } else {
          _runImages(context, initialImages);
        }
      });
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Extract Text')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Entrance(
            child: Card(
              color: Tool.ocr.style.base.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    GradientBadge(style: Tool.ocr.style, size: 46),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'On-device OCR — text is recognized by your phone, never uploaded.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Entrance(
            index: 1,
            child: _SourceTile(
              icon: Icons.image_rounded,
              title: 'From images',
              subtitle: 'Pick photos or screenshots with text',
              onTap: () async {
                final items = await FileService.pickImages();
                if (items.isNotEmpty && context.mounted) {
                  _runImages(context, items);
                }
              },
            ),
          ),
          Entrance(
            index: 2,
            child: _SourceTile(
              icon: Icons.photo_camera_rounded,
              title: 'From camera',
              subtitle: 'Snap a document — auto crop & deskew',
              onTap: () async {
                final shot = await FileService.capturephoto();
                if (shot == null || !context.mounted) return;
                // Perspective-corrected input reads dramatically better.
                final raw = await shot.readBytes();
                if (!context.mounted) return;
                final processed =
                    await Navigator.of(context).push<Uint8List>(
                  Motion.fadeThrough(CropScreen(original: raw)),
                );
                if (processed == null || !context.mounted) return;
                final item = await FileService.writeTemp(
                    'ocr_capture.jpg', processed);
                if (context.mounted) _runImages(context, [item]);
              },
            ),
          ),
          Entrance(
            index: 3,
            child: _SourceTile(
              icon: Icons.picture_as_pdf_rounded,
              title: 'From a PDF',
              subtitle: 'Recognize text on every page of a scan',
              onTap: () async {
                final items = await FileService.pickPdfs(multiple: false);
                if (items.isNotEmpty && context.mounted) {
                  _runPdf(context, items.first);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runImages(BuildContext context, List<PickedItem> items) async {
    final status = ValueNotifier<String?>(null);
    final texts = await runBusy<List<String>>(
      context,
      label: 'Reading text on-device…',
      status: status,
      task: () => OcrService.imagesText(
        [for (final f in items) f.path],
        onProgress: (done, total) =>
            status.value = 'Image $done of $total',
      ),
    );
    if (texts != null && context.mounted) {
      Navigator.of(context).push(Motion.fadeThrough(
          OcrResultScreen(sourceName: items.first.name, pages: texts)));
    }
  }

  Future<void> _runPdf(BuildContext context, PickedItem item) async {
    final status = ValueNotifier<String?>(null);
    final texts = await runBusy<List<String>>(
      context,
      label: 'Reading text on-device…',
      status: status,
      task: () => OcrService.pdfText(
        item.path,
        onProgress: (done, total) => status.value = 'Page $done of $total',
      ),
    );
    if (texts != null && context.mounted) {
      Navigator.of(context).push(Motion.fadeThrough(
          OcrResultScreen(sourceName: item.name, pages: texts)));
    }
  }
}

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Tool.ocr.style.base.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: Tool.ocr.style.base),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing:
            Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
        onTap: onTap,
      ),
    );
  }
}

class OcrResultScreen extends StatefulWidget {
  final String sourceName;
  final List<String> pages;
  const OcrResultScreen(
      {super.key, required this.sourceName, required this.pages});

  @override
  State<OcrResultScreen> createState() => _OcrResultScreenState();
}

class _OcrResultScreenState extends State<OcrResultScreen> {
  bool _recorded = false;

  String get _fullText {
    if (widget.pages.length == 1) return widget.pages.first;
    final buffer = StringBuffer();
    for (var i = 0; i < widget.pages.length; i++) {
      buffer.writeln('— Page ${i + 1} —');
      buffer.writeln(widget.pages[i]);
      buffer.writeln();
    }
    return buffer.toString();
  }

  OutFile get _txtFile {
    final base = widget.sourceName.replaceAll(RegExp(r'\.\w+$'), '');
    return OutFile(
      name: '${base}_text.txt',
      bytes: Uint8List.fromList(utf8.encode(_fullText)),
      mime: 'text/plain',
    );
  }

  void _recordOnce() {
    if (_recorded) return;
    _recorded = true;
    HistoryService.record(Tool.ocr, _txtFile);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = _fullText.trim().isEmpty;
    final charCount = _fullText.trim().length;
    return Scaffold(
      appBar: AppBar(title: const Text('Recognized text')),
      body: empty
          ? const EmptyState(
              icon: Icons.search_off_rounded,
              title: 'No text found',
              message:
                  'Nothing readable was detected. Try a sharper photo with better lighting, or a higher-quality scan.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${widget.pages.length} page${widget.pages.length == 1 ? '' : 's'} · $charCount characters',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    const PrivacyPill(compact: true),
                  ],
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < widget.pages.length; i++)
                  if (widget.pages[i].trim().isNotEmpty)
                    Entrance(
                      index: i,
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (widget.pages.length > 1) ...[
                                Text('PAGE ${i + 1}',
                                    style: AppTheme.manrope(800,
                                        size: 11,
                                        spacing: 1.2,
                                        color: Tool.ocr.style.base)),
                                const SizedBox(height: 8),
                              ],
                              SelectableText(
                                widget.pages[i].trim(),
                                style:
                                    Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
              ],
            ),
      bottomNavigationBar: empty
          ? null
          : BottomBar(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _fullText));
                      HapticFeedback.mediumImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied to clipboard')));
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _recordOnce();
                      FileService.shareOut([_txtFile]);
                    },
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('Share'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Tool.ocr.style.base,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      _recordOnce();
                      final path = await FileService.saveOut(_txtFile);
                      if (path != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Saved ${_txtFile.name}')));
                      }
                    },
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Save'),
                  ),
                ),
              ],
            ),
    );
  }
}
