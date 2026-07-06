import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart' as px;

import '../../core/models/tool.dart';
import '../../core/services/file_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../../ui/theme.dart';
import '../ocr/ocr_screen.dart';
import '../organize/organize_screen.dart';
import '../pdf_to_images/pdf_to_images_screen.dart';
import '../split/split_screen.dart';

/// Fast, private PDF reader. Also the landing screen when FileMill is chosen
/// from the system "Open with" menu for a PDF.
class ViewerScreen extends StatefulWidget {
  final String path;
  final String name;
  const ViewerScreen({super.key, required this.path, required this.name});

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  late final px.PdfControllerPinch _controller;
  int _page = 1;
  int _total = 0;
  String? _error;
  bool _chromeVisible = true;

  @override
  void initState() {
    super.initState();
    _controller = px.PdfControllerPinch(
      document: px.PdfDocument.openFile(widget.path),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openTools() async {
    final item = await PickedItem.fromPath(widget.path, name: widget.name);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Mill this PDF',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  const PrivacyPill(compact: true),
                ],
              ),
            ),
            _toolTile(sheetContext, Tool.split, 'Extract pages',
                SplitScreen(initial: item)),
            _toolTile(sheetContext, Tool.organize, 'Reorder, rotate, delete',
                OrganizeScreen(initial: item)),
            _toolTile(sheetContext, Tool.pdfToImages, 'Export pages as images',
                PdfToImagesScreen(initial: item)),
            _toolTile(sheetContext, Tool.ocr, 'Recognize text on every page',
                OcrScreen(initialPdf: item)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _toolTile(
      BuildContext sheetContext, Tool tool, String subtitle, Widget screen) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: GradientBadge(style: tool.style, size: 42),
      title: Text(tool.title),
      subtitle: Text(subtitle),
      onTap: () {
        Navigator.pop(sheetContext);
        Navigator.of(context).push(Motion.sharedAxis(screen));
      },
    );
  }

  Future<void> _share() async {
    final bytes = await File(widget.path).readAsBytes();
    await FileService.shareOut(
        [OutFile(name: widget.name, bytes: bytes, mime: 'application/pdf')]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF15171B) : const Color(0xFFE8EAF1),
      appBar: _chromeVisible
          ? AppBar(
              title: Text(
                widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.grotesk(600, size: 17),
              ),
              actions: [
                IconButton(
                  tooltip: 'Share',
                  icon: const Icon(Icons.share_rounded),
                  onPressed: _share,
                ),
                IconButton(
                  tooltip: 'Tools',
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  onPressed: _openTools,
                ),
              ],
            )
          : null,
      body: _error != null
          ? EmptyState(
              icon: Icons.picture_as_pdf_rounded,
              title: 'Could not open PDF',
              message: _error!,
            )
          : Stack(
              children: [
                GestureDetector(
                  onTap: () =>
                      setState(() => _chromeVisible = !_chromeVisible),
                  child: px.PdfViewPinch(
                    controller: _controller,
                    backgroundDecoration:
                        const BoxDecoration(color: Colors.transparent),
                    onDocumentLoaded: (doc) =>
                        setState(() => _total = doc.pagesCount),
                    onPageChanged: (page) => setState(() => _page = page),
                    onDocumentError: (e) =>
                        setState(() => _error = e.toString()),
                  ),
                ),
                if (_total > 0)
                  Positioned(
                    bottom: 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: AnimatedOpacity(
                        duration: Motion.fast,
                        opacity: _chromeVisible ? 1 : 0.35,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: scheme.inverseSurface
                                .withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            '$_page / $_total',
                            style: AppTheme.manrope(700,
                                size: 13, color: scheme.onInverseSurface),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
