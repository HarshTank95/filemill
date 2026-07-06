import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

import '../../core/models/tool.dart';
import '../../core/services/file_service.dart';
import '../../core/services/image_pdf_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../merge/merge_screen.dart';
import '../result/result_screen.dart';

/// Images→PDF and Scan→PDF share this screen; [cameraMode] flips the primary
/// add action (and the produced file name / history tool) to scanning.
class ImagesToPdfScreen extends StatefulWidget {
  final bool cameraMode;
  final List<PickedItem> initial;
  const ImagesToPdfScreen(
      {super.key, this.cameraMode = false, this.initial = const []});

  @override
  State<ImagesToPdfScreen> createState() => _ImagesToPdfScreenState();
}

class _ImagesToPdfScreenState extends State<ImagesToPdfScreen> {
  late final List<PickedItem> _items = [...widget.initial];
  PageSizeOption _pageSize = PageSizeOption.auto;
  bool _margin = false;

  Tool get _tool => widget.cameraMode ? Tool.scanToPdf : Tool.imagesToPdf;

  @override
  void initState() {
    super.initState();
    if (widget.cameraMode && widget.initial.isEmpty) {
      // Jump straight into the camera: that's what "Scan" means.
      WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
    }
  }

  Future<void> _addFromGallery() async {
    final picked = await FileService.pickImages();
    if (picked.isEmpty) return;
    setState(() => _items.addAll(picked));
  }

  Future<void> _capture() async {
    final shot = await FileService.capturephoto();
    if (shot == null) return;
    setState(() => _items.add(shot));
  }

  Future<void> _create() async {
    final status = ValueNotifier<String?>(null);
    final out = await runBusy<OutFile>(
      context,
      label: 'Building your PDF…',
      status: status,
      task: () async {
        final normalized = <Uint8List>[];
        for (var i = 0; i < _items.length; i++) {
          status.value = 'Preparing page ${i + 1} of ${_items.length}';
          normalized
              .add(await ImagePdfService.normalize(await _items[i].readBytes()));
        }
        status.value = 'Assembling PDF';
        final bytes = await ImagePdfService.assemble(
          normalized,
          pageSize: _pageSize,
          margin: _margin,
        );
        final prefix = widget.cameraMode ? 'scan' : 'images';
        return OutFile(
          name: '${prefix}_${_items.length}p.pdf',
          bytes: bytes,
          mime: 'application/pdf',
        );
      },
    );
    if (out != null && mounted) {
      Navigator.of(context)
          .push(Motion.fadeThrough(ResultScreen(tool: _tool, files: [out])));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(_tool.title)),
      body: _items.isEmpty
          ? EmptyState(
              icon: _tool.style.icon,
              title: widget.cameraMode
                  ? 'Scan pages with your camera'
                  : 'Turn photos into a PDF',
              message: widget.cameraMode
                  ? 'Capture one page at a time — everything stays on this phone.'
                  : 'Pick images, drag to order them, and mill them into one clean PDF.',
              action: FilledButton.icon(
                onPressed: widget.cameraMode ? _capture : _addFromGallery,
                icon: Icon(widget.cameraMode
                    ? Icons.photo_camera_rounded
                    : Icons.add_photo_alternate_rounded),
                label: Text(
                    widget.cameraMode ? 'Scan first page' : 'Add images'),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<PageSizeOption>(
                          segments: const [
                            ButtonSegment(
                                value: PageSizeOption.auto,
                                label: Text('Fit image')),
                            ButtonSegment(
                                value: PageSizeOption.a4, label: Text('A4')),
                            ButtonSegment(
                                value: PageSizeOption.letter,
                                label: Text('Letter')),
                          ],
                          selected: {_pageSize},
                          onSelectionChanged: (s) =>
                              setState(() => _pageSize = s.first),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text('Page margin',
                          style: Theme.of(context).textTheme.bodyMedium),
                      const Spacer(),
                      Switch(
                        value: _margin,
                        onChanged: (v) => setState(() => _margin = v),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableGridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 130,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.74,
                    ),
                    itemCount: _items.length,
                    onReorder: (oldIndex, newIndex) {
                      HapticFeedback.mediumImpact();
                      setState(() =>
                          _items.insert(newIndex, _items.removeAt(oldIndex)));
                    },
                    itemBuilder: (context, i) {
                      final item = _items[i];
                      return Container(
                        key: ValueKey('${item.path}_$i'),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(File(item.path),
                                fit: BoxFit.cover, cacheWidth: 300),
                            Positioned(
                              left: 6,
                              bottom: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color:
                                      Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Text('${i + 1}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                            Positioned(
                              right: 4,
                              top: 4,
                              child: Material(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () =>
                                      setState(() => _items.removeAt(i)),
                                  child: const Padding(
                                    padding: EdgeInsets.all(5),
                                    child: Icon(Icons.close_rounded,
                                        size: 15, color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _items.isEmpty
          ? null
          : BottomBar(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        widget.cameraMode ? _capture : _addFromGallery,
                    icon: Icon(widget.cameraMode
                        ? Icons.photo_camera_rounded
                        : Icons.add_rounded),
                    label: Text(widget.cameraMode ? 'Scan' : 'Add'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _tool.style.base,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _create,
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: Text(
                        'Create PDF (${_items.length} page${_items.length == 1 ? '' : 's'})'),
                  ),
                ),
              ],
            ),
    );
  }
}
