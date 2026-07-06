import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart' as px;

import '../../core/models/tool.dart';
import '../../core/services/file_service.dart';
import '../../core/services/pdf_service.dart';
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
  late px.PdfControllerPinch _controller;
  int _page = 1;
  int _total = 0;
  String? _error;
  bool _locked = false;
  bool _unlocking = false;
  String? _passwordError;
  bool _chromeVisible = true;
  final _password = TextEditingController();

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
    _password.dispose();
    super.dispose();
  }

  /// The native renderer can't open encrypted PDFs — if that's why we
  /// failed, ask for the password instead of showing an error.
  Future<void> _handleOpenError(Object error) async {
    debugPrint('FileMill viewer failed to open ${widget.name}: $error');
    var locked = false;
    try {
      locked =
          await PdfService.isProtected(await File(widget.path).readAsBytes());
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      if (locked) {
        _locked = true;
      } else {
        _error =
            'This PDF could not be opened. It may be corrupted or use an unsupported format.';
      }
    });
  }

  Future<void> _unlock() async {
    setState(() {
      _unlocking = true;
      _passwordError = null;
    });
    try {
      final src = await File(widget.path).readAsBytes();
      final unlocked = await PdfService.unlock(src, _password.text);
      if (!mounted) return;
      _controller.dispose();
      setState(() {
        _controller = px.PdfControllerPinch(
          document: px.PdfDocument.openData(unlocked),
        );
        _locked = false;
        _unlocking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _unlocking = false;
        _passwordError = friendlyError(e);
      });
    }
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
          : _locked
              ? _LockedView(
                  name: widget.name,
                  controller: _password,
                  busy: _unlocking,
                  errorText: _passwordError,
                  onUnlock: _unlock,
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
                    onDocumentError: _handleOpenError,
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

/// Password gate shown when the opened PDF is encrypted.
class _LockedView extends StatelessWidget {
  final String name;
  final TextEditingController controller;
  final bool busy;
  final String? errorText;
  final VoidCallback onUnlock;
  const _LockedView({
    required this.name,
    required this.controller,
    required this.busy,
    required this.errorText,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_rounded, size: 38, color: scheme.primary),
            ),
            const SizedBox(height: 18),
            Text('This PDF is protected',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => busy ? null : onUnlock(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.key_rounded),
                errorText: errorText,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: busy ? null : onUnlock,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(Icons.lock_open_rounded),
              label: Text(busy ? 'Unlocking…' : 'Open'),
            ),
          ],
        ),
      ),
    );
  }
}
