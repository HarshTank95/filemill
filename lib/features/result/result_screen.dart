import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/tool.dart';
import '../../core/services/file_service.dart';
import '../../core/services/history_service.dart';
import '../../core/services/render_service.dart';
import '../../ui/common.dart';

/// Success screen every tool lands on: animated confirmation, preview,
/// Save / Share actions. Multi-file outputs are saved as a single ZIP
/// (one system dialog) but shared as individual files.
class ResultScreen extends StatefulWidget {
  final Tool tool;
  final List<OutFile> files;
  const ResultScreen({super.key, required this.tool, required this.files});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  Future<OutFile>? _zipFuture;
  Uint8List? _pdfThumb;
  bool _saved = false;

  bool get _isMulti => widget.files.length > 1;
  OutFile get _single => widget.files.first;

  @override
  void initState() {
    super.initState();
    if (_isMulti) {
      final stamp = _timestamp();
      _zipFuture =
          FileService.zip(widget.files, 'filemill_${widget.tool.name}_$stamp.zip');
      _zipFuture!.then((z) => HistoryService.record(widget.tool, z));
    } else {
      HistoryService.record(widget.tool, _single);
      if (_single.mime == 'application/pdf') _loadPdfThumb();
    }
  }

  Future<void> _loadPdfThumb() async {
    try {
      final doc = await RenderedDoc.openData(_single.bytes);
      final thumb = await doc.renderPage(0, scale: 1, png: false);
      await doc.close();
      if (mounted) setState(() => _pdfThumb = thumb);
    } catch (_) {}
  }

  Future<void> _save() async {
    final target = _isMulti ? await _zipFuture! : _single;
    final path = await FileService.saveOut(target);
    if (path != null && mounted) {
      HapticFeedback.mediumImpact();
      setState(() => _saved = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${target.name}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final totalSize =
        widget.files.fold<int>(0, (sum, f) => sum + f.bytes.length);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Column(
                  children: [
                    _SuccessBurst(color: widget.tool.style.base),
                    const SizedBox(height: 20),
                    Text('Done!',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 6),
                    Text(
                      _isMulti
                          ? '${widget.files.length} files · ${humanSize(totalSize)} · processed on-device'
                          : '${humanSize(totalSize)} · processed on-device',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    const PrivacyPill(compact: true),
                    const SizedBox(height: 24),
                    _buildPreview(scheme),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: widget.tool.style.base,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _save,
                    icon: Icon(_saved
                        ? Icons.check_rounded
                        : Icons.download_rounded),
                    label: Text(_saved
                        ? 'Saved'
                        : _isMulti
                            ? 'Save all (ZIP)'
                            : 'Save to device'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => FileService.shareOut(widget.files),
                          icon: const Icon(Icons.share_rounded),
                          label: const Text('Share'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context)
                              .popUntil((r) => r.isFirst),
                          child: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(ColorScheme scheme) {
    if (!_isMulti) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (_pdfThumb != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: Image.memory(_pdfThumb!, fit: BoxFit.contain),
                  ),
                )
              else
                GradientBadge(style: widget.tool.style, size: 64),
              const SizedBox(height: 14),
              Text(_single.name,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    final previews = widget.files.take(6).toList();
    final isImages = previews.first.mime.startsWith('image/');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (isImages)
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  for (final f in previews)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(f.bytes, fit: BoxFit.cover),
                    ),
                ],
              )
            else
              GradientBadge(style: widget.tool.style, size: 64),
            const SizedBox(height: 12),
            Text(
              widget.files.length > 6
                  ? '${previews.map((f) => f.name).join(', ')} +${widget.files.length - 6} more'
                  : previews.map((f) => f.name).join(', '),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  static String _timestamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}';
  }
}

/// Pop-in check mark with a soft expanding halo.
class _SuccessBurst extends StatelessWidget {
  final Color color;
  const _SuccessBurst({required this.color});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutBack,
      builder: (context, t, _) {
        return SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 120 * t.clamp(0.0, 1.0),
                height: 120 * t.clamp(0.0, 1.0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.12 * t.clamp(0.0, 1.0)),
                ),
              ),
              Transform.scale(
                scale: t,
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [color, Color.lerp(color, Colors.white, 0.25)!],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 44),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
