import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/theme.dart';

/// Full-screen finger-signature pad. Pops with a trimmed transparent PNG
/// of the signature, or null if cancelled.
class SignaturePadScreen extends StatefulWidget {
  const SignaturePadScreen({super.key});

  @override
  State<SignaturePadScreen> createState() => _SignaturePadScreenState();
}

class _SignaturePadScreenState extends State<SignaturePadScreen> {
  final List<List<Offset>> _strokes = [];
  Color _ink = const Color(0xFF16233F);

  static const _inks = [Color(0xFF16233F), Color(0xFF1A3FBF), Color(0xFF14181D)];

  bool get _empty => _strokes.isEmpty;

  Future<void> _done() async {
    if (_empty) return;
    final png = await _renderPng();
    if (png != null && mounted) Navigator.of(context).pop(png);
  }

  /// Renders the strokes to a transparent PNG, trimmed to content bounds.
  Future<Uint8List?> _renderPng() async {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final stroke in _strokes) {
      for (final point in stroke) {
        if (point.dx < minX) minX = point.dx;
        if (point.dy < minY) minY = point.dy;
        if (point.dx > maxX) maxX = point.dx;
        if (point.dy > maxY) maxY = point.dy;
      }
    }
    const pad = 14.0;
    final width = (maxX - minX + pad * 2).ceil();
    final height = (maxY - minY + pad * 2).ceil();
    if (width <= 0 || height <= 0) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(pad - minX, pad - minY);
    _paintStrokes(canvas, _strokes, _ink);
    final image =
        await recorder.endRecording().toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Draw your signature'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Undo',
            icon: const Icon(Icons.undo_rounded),
            onPressed: _empty
                ? null
                : () => setState(() => _strokes.removeLast()),
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: _empty ? null : () => setState(_strokes.clear),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // Baseline guide, like signing on paper.
                    Positioned(
                      left: 30,
                      right: 30,
                      bottom: 70,
                      child: Container(
                        height: 1.5,
                        color: Colors.black.withValues(alpha: 0.12),
                      ),
                    ),
                    if (_empty)
                      Center(
                        child: Text(
                          'Sign here with your finger',
                          style: AppTheme.manrope(600,
                              size: 15,
                              color: Colors.black.withValues(alpha: 0.25)),
                        ),
                      ),
                    GestureDetector(
                      onPanStart: (d) {
                        HapticFeedback.selectionClick();
                        setState(() => _strokes.add([d.localPosition]));
                      },
                      onPanUpdate: (d) => setState(
                          () => _strokes.last.add(d.localPosition)),
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _StrokesPainter(_strokes, _ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
              child: Row(
                children: [
                  for (final ink in _inks)
                    GestureDetector(
                      onTap: () => setState(() => _ink = ink),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 34,
                        height: 34,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: ink,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _ink == ink
                                ? scheme.primary
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _empty ? null : _done,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Use signature'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _paintStrokes(Canvas canvas, List<List<Offset>> strokes, Color ink) {
  final paint = Paint()
    ..color = ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.4
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  for (final stroke in strokes) {
    if (stroke.length == 1) {
      canvas.drawCircle(stroke.first, 1.7, Paint()..color = ink);
      continue;
    }
    final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
    for (var i = 1; i < stroke.length - 1; i++) {
      // Midpoint smoothing keeps fast strokes from looking jagged.
      final mid = (stroke[i] + stroke[i + 1]) / 2;
      path.quadraticBezierTo(stroke[i].dx, stroke[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(stroke.last.dx, stroke.last.dy);
    canvas.drawPath(path, paint);
  }
}

class _StrokesPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final Color ink;
  _StrokesPainter(this.strokes, this.ink);

  @override
  void paint(Canvas canvas, Size size) => _paintStrokes(canvas, strokes, ink);

  @override
  bool shouldRepaint(_StrokesPainter old) => true;
}
