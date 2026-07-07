import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/models/tool.dart';
import '../../core/services/file_service.dart';
import '../../core/services/pdf_service.dart';
import '../../core/services/render_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../../ui/theme.dart';
import '../merge/merge_screen.dart';
import '../result/result_screen.dart';
import '../shared/unlock_helper.dart';

class WatermarkScreen extends StatefulWidget {
  final PickedItem? initial;
  const WatermarkScreen({super.key, this.initial});

  @override
  State<WatermarkScreen> createState() => _WatermarkScreenState();
}

class _WatermarkScreenState extends State<WatermarkScreen> {
  PickedItem? _item;
  RenderedDoc? _doc;
  Uint8List? _previewPage;
  double _previewAspect = 0.71;

  final _text = TextEditingController(text: 'CONFIDENTIAL');
  bool _watermarkOn = true;
  double _opacity = 0.18;
  bool _red = false;
  bool _numbersOn = false;
  PageNumberFormat _format = PageNumberFormat.pageOfTotal;
  PageNumberAlign _align = PageNumberAlign.center;

  static const _presets = ['CONFIDENTIAL', 'DRAFT', 'APPROVED', 'COPY'];

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    if (widget.initial != null) _open(widget.initial!);
  }

  @override
  void dispose() {
    _text.dispose();
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
      _previewPage = null;
    });
    final size = await doc.pageSize(0);
    final page = await doc.renderPage(0, scale: 1.4, png: false);
    if (!mounted) return;
    setState(() {
      _previewAspect = size.width / size.height;
      _previewPage = page;
    });
  }

  bool get _canApply =>
      (_watermarkOn && _text.text.trim().isNotEmpty) || _numbersOn;

  Future<void> _apply() async {
    final item = _item!;
    final out = await runBusy<OutFile>(
      context,
      label: 'Stamping pages…',
      task: () async {
        final bytes = await PdfService.watermark(
          await item.readBytes(),
          WatermarkOptions(
            text: _watermarkOn ? _text.text.trim() : null,
            opacity: _opacity,
            red: _red,
            pageNumbers: _numbersOn,
            numberFormat: _format,
            numberAlign: _align,
          ),
        );
        final base =
            item.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
        return OutFile(
          name: '${base}_stamped.pdf',
          bytes: bytes,
          mime: 'application/pdf',
        );
      },
    );
    if (out != null && mounted) {
      Navigator.of(context).push(Motion.fadeThrough(
          ResultScreen(tool: Tool.watermark, files: [out])));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = _item;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Watermark'),
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
              icon: Tool.watermark.style.icon,
              title: 'Stamp it before it travels',
              message:
                  'Mark every page CONFIDENTIAL or DRAFT, add page numbers — applied on-device before the document goes anywhere.',
              action: FilledButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Open PDF'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Entrance(child: _buildPreview(scheme)),
                const SizedBox(height: 18),
                Entrance(
                  index: 1,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text('Watermark text',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                              ),
                              Switch(
                                value: _watermarkOn,
                                onChanged: (v) =>
                                    setState(() => _watermarkOn = v),
                              ),
                            ],
                          ),
                          if (_watermarkOn) ...[
                            const SizedBox(height: 10),
                            TextField(
                              controller: _text,
                              textCapitalization:
                                  TextCapitalization.characters,
                              decoration: const InputDecoration(
                                  hintText: 'e.g. CONFIDENTIAL'),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              children: [
                                for (final preset in _presets)
                                  ActionChip(
                                    label: Text(preset),
                                    onPressed: () => setState(
                                        () => _text.text = preset),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text('Strength',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium),
                                Expanded(
                                  child: Slider(
                                    value: _opacity,
                                    min: 0.06,
                                    max: 0.45,
                                    onChanged: (v) =>
                                        setState(() => _opacity = v),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Text('Red ink',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium),
                                const Spacer(),
                                Switch(
                                  value: _red,
                                  onChanged: (v) =>
                                      setState(() => _red = v),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Entrance(
                  index: 2,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text('Page numbers',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                              ),
                              Switch(
                                value: _numbersOn,
                                onChanged: (v) =>
                                    setState(() => _numbersOn = v),
                              ),
                            ],
                          ),
                          if (_numbersOn) ...[
                            const SizedBox(height: 10),
                            SegmentedButton<PageNumberFormat>(
                              segments: const [
                                ButtonSegment(
                                    value: PageNumberFormat.simple,
                                    label: Text('1')),
                                ButtonSegment(
                                    value: PageNumberFormat.ofTotal,
                                    label: Text('1 of N')),
                                ButtonSegment(
                                    value: PageNumberFormat.pageOfTotal,
                                    label: Text('Page 1 of N')),
                              ],
                              selected: {_format},
                              onSelectionChanged: (s) =>
                                  setState(() => _format = s.first),
                            ),
                            const SizedBox(height: 10),
                            SegmentedButton<PageNumberAlign>(
                              segments: const [
                                ButtonSegment(
                                    value: PageNumberAlign.left,
                                    icon: Icon(
                                        Icons.format_align_left_rounded)),
                                ButtonSegment(
                                    value: PageNumberAlign.center,
                                    icon: Icon(
                                        Icons.format_align_center_rounded)),
                                ButtonSegment(
                                    value: PageNumberAlign.right,
                                    icon: Icon(
                                        Icons.format_align_right_rounded)),
                              ],
                              selected: {_align},
                              onSelectionChanged: (s) =>
                                  setState(() => _align = s.first),
                            ),
                          ],
                        ],
                      ),
                    ),
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
                      backgroundColor: Tool.watermark.style.base,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _canApply ? _apply : null,
                    icon: const Icon(Icons.branding_watermark_rounded),
                    label: Text(
                        'Stamp all ${_doc?.pageCount ?? ''} pages'.trim()),
                  ),
                ),
              ],
            ),
    );
  }

  /// First page with the watermark simulated in Flutter — what you see is
  /// close to what Syncfusion stamps into the file.
  Widget _buildPreview(ColorScheme scheme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: AspectRatio(
          aspectRatio: _previewAspect,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                final angle = -math.atan2(h, w);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_previewPage != null)
                      Image.memory(_previewPage!,
                          fit: BoxFit.fill, gaplessPlayback: true)
                    else
                      const Center(child: CircularProgressIndicator()),
                    if (_watermarkOn && _text.text.trim().isNotEmpty)
                      Center(
                        child: Transform.rotate(
                          angle: angle,
                          child: Text(
                            _text.text.trim(),
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 0.7 *
                                  math.sqrt(w * w + h * h) /
                                  math.max(_text.text.trim().length, 1) *
                                  1.6,
                              fontWeight: FontWeight.w800,
                              color: (_red
                                      ? const Color(0xFFC81E1E)
                                      : const Color(0xFF5A5A5A))
                                  .withValues(alpha: _opacity),
                            ),
                          ),
                        ),
                      ),
                    if (_numbersOn)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 6,
                        child: Align(
                          alignment: switch (_align) {
                            PageNumberAlign.left => Alignment.centerLeft,
                            PageNumberAlign.center => Alignment.center,
                            PageNumberAlign.right => Alignment.centerRight,
                          },
                          child: Text(
                            WatermarkOptions(
                                    numberFormat: _format)
                                .numberLabel(1, _doc?.pageCount ?? 1),
                            style: AppTheme.manrope(600,
                                size: 8, color: const Color(0xFF6E6E6E)),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
