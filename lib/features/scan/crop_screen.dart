import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/scan_processor.dart';
import '../../ui/common.dart';
import '../../ui/theme.dart';

/// Post-capture scan editor: auto-suggested document edges, draggable
/// corners with a magnifier loupe, perspective-corrected output with the
/// "Enhanced" document look applied automatically. Pops with the processed
/// JPEG bytes, or null if discarded.
class CropScreen extends StatefulWidget {
  final Uint8List original;
  const CropScreen({super.key, required this.original});

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  List<Offset>? _corners; // normalized TL TR BR BL
  double _aspect = 0.75;
  int? _dragIndex;
  Offset? _dragWidgetPos;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  Future<void> _detect() async {
    final result = await ScanProcessor.detect(widget.original);
    if (!mounted) return;
    setState(() {
      _aspect = result.aspect;
      _corners = List.of(result.corners);
    });
  }

  Future<void> _usePage() async {
    final corners = _corners;
    if (corners == null) return;
    final bytes = await runBusy<Uint8List>(
      context,
      label: 'Straightening & enhancing…',
      task: () => ScanProcessor.process(ScanJob(
        bytes: widget.original,
        corners: corners,
        filter: ScanFilter.enhanced,
      )),
    );
    if (bytes != null && mounted) Navigator.of(context).pop(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final corners = _corners;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text('Adjust scan',
            style: AppTheme.grotesk(650, size: 19, color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: corners == null
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _aspect,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final size = Size(constraints.maxWidth,
                                constraints.maxHeight);
                            return GestureDetector(
                              onPanStart: (d) =>
                                  _onPanStart(d.localPosition, size),
                              onPanUpdate: (d) =>
                                  _onPanUpdate(d.localPosition, size),
                              onPanEnd: (_) => _onPanEnd(),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.memory(
                                      widget.original,
                                      fit: BoxFit.fill,
                                      width: size.width,
                                      height: size.height,
                                    ),
                                  ),
                                  CustomPaint(
                                    size: size,
                                    painter: _QuadPainter(
                                      corners: corners,
                                      accent: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      activeIndex: _dragIndex,
                                    ),
                                  ),
                                  if (_dragIndex != null &&
                                      _dragWidgetPos != null)
                                    Positioned(
                                      left: _dragWidgetPos!.dx - 55,
                                      top: _dragWidgetPos!.dy - 150,
                                      child: RawMagnifier(
                                        size: const Size(110, 110),
                                        magnificationScale: 2,
                                        focalPointOffset:
                                            const Offset(0, 95),
                                        decoration: MagnifierDecoration(
                                          shape: CircleBorder(
                                            side: BorderSide(
                                              color: Colors.white
                                                  .withValues(alpha: 0.9),
                                              width: 2.5,
                                            ),
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
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                  color:
                                      Colors.white.withValues(alpha: 0.4)),
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Discard'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: _usePage,
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Use page'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  void _onPanStart(Offset pos, Size size) {
    final corners = _corners!;
    var best = -1;
    var bestDist = 44.0 * 44.0;
    for (var i = 0; i < 4; i++) {
      final c = Offset(corners[i].dx * size.width, corners[i].dy * size.height);
      final d = (c - pos).distanceSquared;
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    if (best >= 0) {
      HapticFeedback.selectionClick();
      setState(() {
        _dragIndex = best;
        _dragWidgetPos = pos;
      });
    }
  }

  void _onPanUpdate(Offset pos, Size size) {
    final index = _dragIndex;
    if (index == null) return;
    setState(() {
      _dragWidgetPos = pos;
      _corners![index] = Offset(
        (pos.dx / size.width).clamp(0.0, 1.0),
        (pos.dy / size.height).clamp(0.0, 1.0),
      );
    });
  }

  void _onPanEnd() {
    if (_dragIndex == null) return;
    setState(() {
      _dragIndex = null;
      _dragWidgetPos = null;
    });
  }
}

class _QuadPainter extends CustomPainter {
  final List<Offset> corners;
  final Color accent;
  final int? activeIndex;
  _QuadPainter({
    required this.corners,
    required this.accent,
    required this.activeIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final points = [
      for (final c in corners) Offset(c.dx * size.width, c.dy * size.height),
    ];
    final quad = Path()..addPolygon(points, true);

    // Dim everything outside the document.
    final outside = Path()
      ..addRect(Offset.zero & size)
      ..addPath(quad, Offset.zero)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
        outside, Paint()..color = Colors.black.withValues(alpha: 0.55));

    canvas.drawPath(
      quad,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = accent,
    );

    // Edge midpoint ticks help perspective adjustments read clearly.
    for (var i = 0; i < 4; i++) {
      final mid = (points[i] + points[(i + 1) % 4]) / 2;
      canvas.drawCircle(mid, 4, Paint()..color = accent.withValues(alpha: 0.6));
    }

    for (var i = 0; i < 4; i++) {
      final active = i == activeIndex;
      canvas.drawCircle(
        points[i],
        active ? 15 : 11,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        points[i],
        active ? 10 : 6.5,
        Paint()..color = accent,
      );
    }
  }

  @override
  bool shouldRepaint(_QuadPainter old) =>
      old.corners != corners || old.activeIndex != activeIndex;
}

