import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/models/tool.dart';
import '../../core/services/file_service.dart';
import '../../core/services/ocr_service.dart';
import '../../core/services/pdf_word_service.dart';
import '../../core/services/render_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../../ui/theme.dart';
import '../merge/merge_screen.dart';
import '../result/result_screen.dart';
import '../shared/unlock_helper.dart';

const _docxMime =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

class PdfToWordScreen extends StatefulWidget {
  final PickedItem? initial;
  const PdfToWordScreen({super.key, this.initial});

  @override
  State<PdfToWordScreen> createState() => _PdfToWordScreenState();
}

class _PdfToWordScreenState extends State<PdfToWordScreen> {
  PickedItem? _item;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _item = widget.initial;
  }

  Future<void> _pick() async {
    final picked = await FileService.pickPdfs(multiple: false);
    if (picked.isEmpty) return;
    setState(() => _item = picked.first);
  }

  Future<void> _convert() async {
    final item = _item!;
    if (!await ensureUnlocked(context, item)) return;
    if (!mounted) return;
    final status = ValueNotifier<String?>(null);
    final out = await runBusy<OutFile>(
      context,
      label: 'Reconstructing on-device…',
      status: status,
      task: () async {
        final bytes = item.unlockedBytes ?? await item.readBytes();
        status.value = 'Extracting text & fonts';
        final extracted = await PdfWordService.extractPages(bytes);
        // Fresh, fully-growable copies so the OCR fallback can add lines
        // regardless of how the isolate returned the data.
        final pages = [
          for (final p in extracted) PageData(p.width, p.height, [...p.lines])
        ];

        // Any page with no text layer is a scan → OCR it (platform code, so
        // it runs here, not in the extraction isolate).
        final scanned = <int>[
          for (var i = 0; i < pages.length; i++)
            if (pages[i].lines.isEmpty) i
        ];
        if (scanned.isNotEmpty) {
          final doc = await RenderedDoc.openData(bytes);
          final recognizer = OcrService.newRecognizer();
          try {
            for (var k = 0; k < scanned.length; k++) {
              final i = scanned[k];
              status.value =
                  'Reading scanned page ${k + 1} of ${scanned.length}';
              const scale = 3.0;
              final jpg = await doc.renderPage(i, scale: scale, png: false);
              final tmp = await FileService.writeTemp('p2w_$i.jpg', jpg);
              final ocrLines = await OcrService.imageLines(tmp.path, recognizer);
              final page = pages[i];
              for (final l in ocrLines) {
                page.lines.add(LineData(
                  l.text,
                  l.box.left / scale,
                  l.box.top / scale,
                  l.box.width / scale,
                  l.box.height / scale,
                  (l.box.height / scale) * 0.7,
                  false,
                  false,
                  false,
                  const [],
                ));
              }
              File(tmp.path).delete().ignore();
            }
          } finally {
            await recognizer.close();
            await doc.close();
          }
        }

        status.value = 'Building Word document';
        final docx = await PdfWordService.buildDocx(pages);
        final base =
            item.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
        return OutFile(name: '$base.docx', bytes: docx, mime: _docxMime);
      },
    );
    if (out != null && mounted) {
      Navigator.of(context).push(Motion.fadeThrough(
          ResultScreen(tool: Tool.pdfToWord, files: [out])));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = _item;
    return Scaffold(
      appBar: AppBar(title: const Text('PDF → Word')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Entrance(
            child: item == null
                ? _EmptyPicker(onPick: _pick)
                : Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      leading:
                          GradientBadge(style: Tool.pdfToWord.style, size: 46),
                      title: Text(item.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(humanSize(item.size)),
                      trailing: IconButton(
                        icon: const Icon(Icons.folder_open_rounded),
                        onPressed: _pick,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 18),
          Entrance(index: 1, child: const _TransparencyNote()),
          const SizedBox(height: 12),
          Entrance(
            index: 2,
            child: Row(
              children: [
                Icon(Icons.verified_user_rounded,
                    size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Converted entirely on this phone. Unlike other apps, your document is never uploaded.',
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
                      backgroundColor: Tool.pdfToWord.style.base,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _convert,
                    icon: const Icon(Icons.description_rounded),
                    label: const Text('Convert to Word'),
                  ),
                ),
              ],
            ),
    );
  }
}

class _EmptyPicker extends StatelessWidget {
  final VoidCallback onPick;
  const _EmptyPicker({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onPick,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
          child: Column(
            children: [
              GradientBadge(style: Tool.pdfToWord.style, size: 60),
              const SizedBox(height: 16),
              Text('Convert a PDF to an editable Word file',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('Text, fonts, headings and lists rebuilt on your device.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Choose PDF'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Honest, upfront transparency about what this converter can and can't do.
class _TransparencyNote extends StatelessWidget {
  const _TransparencyNote();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget row(IconData icon, Color color, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(height: 1.4)),
              ),
            ],
          ),
        );

    return Card(
      color: Tool.pdfToWord.style.base.withValues(alpha: 0.07),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    color: Tool.pdfToWord.style.base),
                const SizedBox(width: 10),
                Text('Before you convert',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'A PDF stores placed letters, not a document structure, so any PDF→Word '
              'conversion rebuilds that structure — it is never a pixel-perfect copy '
              '(no tool, including paid ones, is). Here is exactly what to expect:',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
            ),
            const SizedBox(height: 12),
            row(Icons.check_circle_rounded, AppTheme.offlineGreen,
                'Works great: text, paragraphs, headings, bold/italic, font sizes, '
                'bullet & numbered lists, alignment.'),
            row(Icons.change_history_rounded, const Color(0xFFEF9A00),
                'May need touch-ups: multi-column layouts, tables (kept as tab-aligned '
                'text), exact spacing.'),
            row(Icons.cancel_rounded, scheme.error,
                'Not preserved: embedded images, exact page layout, and text colour '
                '(the PDF engine can\'t extract these on-device).'),
            row(Icons.document_scanner_rounded, Tool.pdfToWord.style.base,
                'Scanned PDFs are read with on-device OCR, so they convert to editable '
                'text too.'),
            const SizedBox(height: 10),
            Text(
              'The result is fully editable — best for reusing the words, not for '
              'reproducing the design.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                  height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
