import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:path/path.dart' as p;

import '../../core/models/tool.dart';
import '../../core/services/file_service.dart';
import '../../core/services/image_convert_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../merge/merge_screen.dart';
import '../result/result_screen.dart';

class ImageConvertScreen extends StatefulWidget {
  final List<PickedItem> initial;
  const ImageConvertScreen({super.key, this.initial = const []});

  @override
  State<ImageConvertScreen> createState() => _ImageConvertScreenState();
}

class _ImageConvertScreenState extends State<ImageConvertScreen> {
  late final List<PickedItem> _items = [...widget.initial];
  ImageOutFormat _format = ImageOutFormat.jpg;
  ImageMaxSize _maxSize = ImageMaxSize.original;
  double _quality = 88;

  Future<void> _add() async {
    final picked = await FileService.pickImages();
    if (picked.isEmpty) return;
    setState(() => _items.addAll(picked));
  }

  Future<void> _convert() async {
    final status = ValueNotifier<String?>(null);
    final files = await runBusy<List<OutFile>>(
      context,
      label: 'Converting on-device…',
      status: status,
      task: () async {
        final out = <OutFile>[];
        for (var i = 0; i < _items.length; i++) {
          status.value = 'Image ${i + 1} of ${_items.length}';
          final bytes = await ImageConvertService.convert(
            await _items[i].readBytes(),
            format: _format,
            jpgQuality: _quality.round(),
            maxDim: _maxSize.maxDim,
          );
          final base = p.basenameWithoutExtension(_items[i].name);
          final ext = _format == ImageOutFormat.jpg ? 'jpg' : 'png';
          out.add(OutFile(
            name: '$base.$ext',
            bytes: bytes,
            mime: _format == ImageOutFormat.jpg ? 'image/jpeg' : 'image/png',
          ));
        }
        return out;
      },
    );
    if (files != null && mounted) {
      final before = _items.fold<int>(0, (s, f) => s + f.size);
      final after = files.fold<int>(0, (s, f) => s + f.bytes.length);
      if (after < before) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '${humanSize(before)} → ${humanSize(after)} (saved ${((before - after) * 100 / before).round()}%)')));
      }
      Navigator.of(context).push(Motion.fadeThrough(
          ResultScreen(tool: Tool.imageConvert, files: files)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Convert Images')),
      body: _items.isEmpty
          ? EmptyState(
              icon: Tool.imageConvert.style.icon,
              title: 'Any image, the format you need',
              message:
                  'WebP that won\'t upload, photos too big to send — convert to JPG or PNG and resize, all on this phone.',
              action: FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add_photo_alternate_rounded),
                label: const Text('Add images'),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<ImageOutFormat>(
                          segments: const [
                            ButtonSegment(
                                value: ImageOutFormat.jpg,
                                label: Text('JPG'),
                                icon: Icon(Icons.photo_rounded)),
                            ButtonSegment(
                                value: ImageOutFormat.png,
                                label: Text('PNG'),
                                icon: Icon(Icons.image_rounded)),
                          ],
                          selected: {_format},
                          onSelectionChanged: (s) =>
                              setState(() => _format = s.first),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<ImageMaxSize>(
                          segments: const [
                            ButtonSegment(
                                value: ImageMaxSize.original,
                                label: Text('Full size')),
                            ButtonSegment(
                                value: ImageMaxSize.px2048,
                                label: Text('2048 px')),
                            ButtonSegment(
                                value: ImageMaxSize.px1080,
                                label: Text('1080 px')),
                          ],
                          selected: {_maxSize},
                          onSelectionChanged: (s) =>
                              setState(() => _maxSize = s.first),
                        ),
                      ),
                      if (_format == ImageOutFormat.jpg)
                        Row(
                          children: [
                            Text('Quality',
                                style:
                                    Theme.of(context).textTheme.bodyMedium),
                            Expanded(
                              child: Slider(
                                value: _quality,
                                min: 40,
                                max: 100,
                                divisions: 12,
                                label: '${_quality.round()}',
                                onChanged: (v) =>
                                    setState(() => _quality = v),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimationLimiter(
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 130,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.82,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (context, i) {
                        final item = _items[i];
                        return AnimationConfiguration.staggeredGrid(
                          position: i,
                          columnCount: 3,
                          duration: const Duration(milliseconds: 300),
                          child: ScaleAnimation(
                            scale: 0.92,
                            child: FadeInAnimation(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: scheme.outlineVariant),
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
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.55),
                                          borderRadius:
                                              BorderRadius.circular(100),
                                        ),
                                        child: Text(
                                          humanSize(item.size),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      right: 4,
                                      top: 4,
                                      child: Material(
                                        color: Colors.black
                                            .withValues(alpha: 0.45),
                                        shape: const CircleBorder(),
                                        child: InkWell(
                                          customBorder:
                                              const CircleBorder(),
                                          onTap: () => setState(
                                              () => _items.removeAt(i)),
                                          child: const Padding(
                                            padding: EdgeInsets.all(5),
                                            child: Icon(
                                                Icons.close_rounded,
                                                size: 15,
                                                color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
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
                    onPressed: _add,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Tool.imageConvert.style.base,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _convert,
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: Text(
                        'Convert ${_items.length} to ${_format == ImageOutFormat.jpg ? 'JPG' : 'PNG'}'),
                  ),
                ),
              ],
            ),
    );
  }
}
