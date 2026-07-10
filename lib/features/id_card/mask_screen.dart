import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/theme.dart';

/// Full-screen privacy-mask editor for one card side. Black strips are
/// dragged over sensitive digits (UIDAI recommends hiding the first 8
/// Aadhaar digits); they are burned into the pixels on export.
/// Pops with the list of normalized rects, or null if cancelled.
class MaskScreen extends StatefulWidget {
  final Uint8List image;
  final double aspect;
  final List<Rect> initial;

  /// True when [initial] holds auto-detected Aadhaar masks awaiting review.
  final bool prefilled;
  const MaskScreen({
    super.key,
    required this.image,
    this.aspect = 85.6 / 54.0,
    this.initial = const [],
    this.prefilled = false,
  });

  @override
  State<MaskScreen> createState() => _MaskScreenState();
}

class _MaskScreenState extends State<MaskScreen> {
  late List<Rect> _masks = List.of(widget.initial);
  int? _selected;

  void _add() {
    HapticFeedback.selectionClick();
    setState(() {
      // A strip roughly where an Aadhaar number sits; user drags it anywhere.
      _masks.add(const Rect.fromLTWH(0.28, 0.72, 0.44, 0.11));
      _selected = _masks.length - 1;
    });
  }

  void _deleteSelected() {
    final s = _selected;
    if (s == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _masks.removeAt(s);
      _selected = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text('Mask sensitive info',
            style: AppTheme.grotesk(650, size: 19, color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_selected != null)
            IconButton(
              tooltip: 'Remove mask',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _deleteSelected,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: LayoutBuilder(
                  builder: (context, box) => _Editor(
                    image: widget.image,
                    aspect: widget.aspect,
                    masks: _masks,
                    selected: _selected,
                    onChanged: (masks, selected) => setState(() {
                      _masks = masks;
                      _selected = selected;
                    }),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              widget.prefilled
                  ? 'Aadhaar number detected — a mask is pre-placed over the '
                      'first 8 digits (UIDAI advice). Adjust, delete or add '
                      'more, then tap Done to apply.'
                  : 'Drag a strip over the number. Masks are burned into the '
                      'file — the digits underneath cannot be recovered.',
              textAlign: TextAlign.center,
              style: AppTheme.manrope(550,
                  size: 12.5, color: Colors.white.withValues(alpha: 0.65)),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                      ),
                      onPressed: _add,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add mask'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(_masks),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Done'),
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
}

class _Editor extends StatelessWidget {
  final Uint8List image;
  final double aspect;
  final List<Rect> masks;
  final int? selected;
  final void Function(List<Rect>, int?) onChanged;
  const _Editor({
    required this.image,
    required this.aspect,
    required this.masks,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspect,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(image, fit: BoxFit.fill),
                ),
              ),
              // Tap empty area to deselect.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => onChanged(masks, null),
                ),
              ),
              for (var i = 0; i < masks.length; i++)
                _MaskBox(
                  rect: masks[i],
                  bounds: Size(w, h),
                  isSelected: selected == i,
                  onTap: () => onChanged(masks, i),
                  onUpdate: (r) {
                    final next = List.of(masks);
                    next[i] = r;
                    onChanged(next, i);
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MaskBox extends StatelessWidget {
  final Rect rect; // normalized
  final Size bounds;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueChanged<Rect> onUpdate;
  const _MaskBox({
    required this.rect,
    required this.bounds,
    required this.isSelected,
    required this.onTap,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final w = bounds.width, h = bounds.height;
    final px = Rect.fromLTWH(
        rect.left * w, rect.top * h, rect.width * w, rect.height * h);

    Rect clamp(Rect r) {
      final left = r.left.clamp(0.0, 1.0 - r.width);
      final top = r.top.clamp(0.0, 1.0 - r.height);
      return Rect.fromLTWH(left, top, r.width, r.height);
    }

    return Positioned(
      left: px.left,
      top: px.top,
      width: px.width,
      height: px.height,
      child: GestureDetector(
        onTap: onTap,
        onPanStart: (_) => onTap(),
        onPanUpdate: (d) => onUpdate(clamp(rect.translate(
            d.delta.dx / w, d.delta.dy / h))),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: isSelected ? const Color(0xFF64B5F6) : Colors.white24,
                  width: isSelected ? 2 : 1,
                ),
              ),
            ),
            if (isSelected)
              Positioned(
                right: -16,
                bottom: -16,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) {
                    final nw =
                        (rect.width + d.delta.dx / w).clamp(0.06, 1.0);
                    final nh =
                        (rect.height + d.delta.dy / h).clamp(0.04, 1.0);
                    onUpdate(clamp(
                        Rect.fromLTWH(rect.left, rect.top, nw, nh)));
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: Color(0xFF64B5F6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.open_in_full_rounded,
                          size: 12, color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
