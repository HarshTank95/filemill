import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../../core/services/render_service.dart';

/// Caches page thumbnails for one open document so grids can rebuild freely.
class ThumbCache {
  final RenderedDoc doc;
  final Map<int, Future<Uint8List>> _futures = {};
  ThumbCache(this.doc);

  Future<Uint8List> thumb(int index) =>
      _futures[index] ??= doc.renderPage(index, scale: 0.7, png: false, jpgQuality: 80);
}

/// Selectable page-thumbnail grid used by Split and PDF→Images.
class PageSelectGrid extends StatelessWidget {
  final ThumbCache cache;
  final Set<int> selected;
  final void Function(int index) onToggle;

  const PageSelectGrid({
    super.key,
    required this.cache,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return AnimationLimiter(
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 130,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.74,
        ),
        itemCount: cache.doc.pageCount,
        itemBuilder: (context, i) {
          return AnimationConfiguration.staggeredGrid(
            position: i,
            columnCount: 3,
            duration: const Duration(milliseconds: 320),
            child: ScaleAnimation(
              scale: 0.92,
              child: FadeInAnimation(
                child: PageThumb(
                  cache: cache,
                  index: i,
                  selected: selected.contains(i),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onToggle(i);
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class PageThumb extends StatelessWidget {
  final ThumbCache cache;
  final int index;
  final bool selected;
  final VoidCallback? onTap;
  final int quarterTurns;
  final Widget? footer;

  const PageThumb({
    super.key,
    required this.cache,
    required this.index,
    this.selected = false,
    this.onTap,
    this.quarterTurns = 0,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2.5 : 1,
          ),
          color: Colors.white,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List>(
              future: cache.thumb(index),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  );
                }
                return RotatedBox(
                  quarterTurns: quarterTurns,
                  child: Image.memory(snap.data!, fit: BoxFit.cover),
                );
              },
            ),
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (onTap != null)
              Positioned(
                right: 6,
                top: 6,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  scale: selected ? 1 : 0,
                  curve: Curves.easeOutBack,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.check_rounded,
                        size: 14, color: Colors.white),
                  ),
                ),
              ),
            if (footer != null)
              Positioned(left: 0, right: 0, bottom: 0, child: footer!),
          ],
        ),
      ),
    );
  }
}

/// "All · None · 1-3,7" quick-selection bar.
class SelectionBar extends StatelessWidget {
  final int pageCount;
  final Set<int> selected;
  final void Function(Set<int>) onChanged;

  const SelectionBar({
    super.key,
    required this.pageCount,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Text('${selected.length} of $pageCount selected',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const Spacer(),
          TextButton(
            onPressed: () =>
                onChanged({for (var i = 0; i < pageCount; i++) i}),
            child: const Text('All'),
          ),
          TextButton(
            onPressed: () => onChanged({}),
            child: const Text('None'),
          ),
          TextButton(
            onPressed: () => _askRange(context),
            child: const Text('Range'),
          ),
        ],
      ),
    );
  }

  Future<void> _askRange(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select a range'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. 1-3, 7, 12-14'),
          keyboardType: TextInputType.text,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Select'),
          ),
        ],
      ),
    );
    if (result == null || result.trim().isEmpty) return;
    final picked = parseRanges(result, pageCount);
    if (picked.isNotEmpty) onChanged(picked);
  }

  /// Parses "1-3, 7" into 0-based indices, clamped to the document.
  static Set<int> parseRanges(String input, int pageCount) {
    final out = <int>{};
    for (final part in input.split(RegExp(r'[,\s]+'))) {
      if (part.isEmpty) continue;
      final range = part.split('-');
      final start = int.tryParse(range.first);
      final end = int.tryParse(range.last);
      if (start == null || end == null) continue;
      for (var page = start; page <= end; page++) {
        if (page >= 1 && page <= pageCount) out.add(page - 1);
      }
    }
    return out;
  }
}
