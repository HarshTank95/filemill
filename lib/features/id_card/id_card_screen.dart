import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/tool.dart';
import '../../core/services/file_service.dart';
import '../../core/services/id_card_service.dart';
import '../../core/services/ocr_service.dart';
import '../../core/services/scan_processor.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../../ui/theme.dart';
import '../merge/merge_screen.dart' show BottomBar;
import '../result/result_screen.dart';
import '../scan/crop_screen.dart';
import 'mask_screen.dart';

/// ID Card → PDF: scan the front and back of an Aadhaar/PAN/DL and lay both
/// out on one A4 at TRUE card size (ISO ID-1) — the format every KYC desk
/// asks for. Optional UIDAI-style masking burns the number out of the pixels.
class IdCardScreen extends StatefulWidget {
  const IdCardScreen({super.key});

  @override
  State<IdCardScreen> createState() => _IdCardScreenState();
}

class _Side {
  SideImage? neutral; // deskewed, unfiltered, landscape-normalized crop
  List<Rect> masks = []; // applied masks (burned on export)
  List<Rect> suggested = []; // Aadhaar auto-detections, offered in the editor
  Uint8List? preview; // small finalized render (filter + masks)
  int previewStamp = 0;
  bool rotating = false;
}

class _IdCardScreenState extends State<IdCardScreen> {
  final _front = _Side();
  final _back = _Side();
  ScanFilter _filter = ScanFilter.enhanced;

  Future<void> _capture(_Side side, {required bool camera}) async {
    Uint8List? raw;
    if (camera) {
      final shot = await FileService.capturephoto();
      if (shot == null) return;
      raw = await shot.readBytes();
    } else {
      final picked = await FileService.pickImages(multiple: false);
      if (picked.isEmpty) return;
      raw = await picked.first.readBytes();
    }
    if (!mounted) return;
    final cropped = await Navigator.of(context).push<Uint8List>(
      Motion.fadeThrough(
          CropScreen(original: raw, filter: ScanFilter.original)),
    );
    if (cropped == null || !mounted) return;

    // Smart intake: OCR decides the upright rotation (works for vertical
    // Voter IDs too) and auto-masks any Aadhaar number it finds.
    final status = ValueNotifier<String?>(null);
    final result = await runBusy<(SideImage, List<Rect>)>(
      context,
      label: 'Reading card…',
      status: status,
      task: () async {
        status.value = 'Detecting orientation';
        final candidates = await IdCardService.orientationCandidates(cropped);
        final recognizer = OcrService.newRecognizer();
        var bestScore = -1, bestIdx = 0;
        var bestLines = const <OcrScanLine>[];
        try {
          for (var i = 0; i < candidates.length; i++) {
            final tmp = await FileService.writeTemp(
                'idcard_orient_$i.jpg', candidates[i].bytes);
            final lines = await OcrService.imageScan(tmp.path, recognizer);
            File(tmp.path).delete().ignore();
            final score =
                IdCardService.textScore([for (final l in lines) l.text]);
            if (score > bestScore) {
              bestScore = score;
              bestIdx = i;
              bestLines = lines;
            }
          }
        } finally {
          await recognizer.close();
        }
        if (bestScore < 8) {
          // Unreadable card — fall back to the landscape-shape guess.
          return (await IdCardService.normalizeSide(cropped), const <Rect>[]);
        }
        status.value = 'Checking for Aadhaar number';
        final neutral =
            await IdCardService.applyRotation(cropped, bestIdx * 90);
        final masks = IdCardService.aadhaarMasks(
            bestLines,
            candidates[bestIdx].width.toDouble(),
            candidates[bestIdx].height.toDouble());
        return (neutral, masks);
      },
    );
    if (result == null || !mounted) return;
    setState(() {
      side.neutral = result.$1;
      // Nothing is masked without the user's say-so — detections are only
      // OFFERED when they open the mask editor.
      side.masks = [];
      side.suggested = [...result.$2];
      side.preview = null;
    });
    _refreshPreview(side);
  }

  Future<void> _rotate(_Side side) async {
    final neutral = side.neutral;
    // The guard serializes taps: a second tap during the rotate would read
    // the pre-rotation image and desync the mask transform from the pixels.
    if (neutral == null || side.rotating) return;
    side.rotating = true;
    HapticFeedback.selectionClick();
    try {
      final rotated = await IdCardService.rotateSide(neutral.bytes);
      if (!mounted) return;
      // 90° CW: (x,y) -> (1-y, x); masks and suggestions follow the pixels.
      List<Rect> turn(List<Rect> rects) => [
            for (final m in rects)
              Rect.fromLTRB(1 - m.bottom, m.left, 1 - m.top, m.right)
          ];
      setState(() {
        side.neutral = rotated;
        side.masks = turn(side.masks);
        side.suggested = turn(side.suggested);
        side.preview = null;
      });
      _refreshPreview(side);
    } finally {
      side.rotating = false;
    }
  }

  Future<void> _editMasks(_Side side) async {
    final neutral = side.neutral;
    if (neutral == null) return;
    // Detected Aadhaar digits are offered here, pre-placed for review —
    // never applied behind the user's back.
    final prefill = side.masks.isEmpty && side.suggested.isNotEmpty;
    final masks = await Navigator.of(context).push<List<Rect>>(
      Motion.fadeThrough(MaskScreen(
          image: neutral.bytes,
          aspect: neutral.aspect,
          initial: prefill ? side.suggested : side.masks,
          prefilled: prefill)),
    );
    if (masks == null) return;
    setState(() {
      side.masks = masks;
      // The suggestion was reviewed (kept or deleted) — don't re-offer it.
      side.suggested = [];
    });
    _refreshPreview(side);
  }

  Future<void> _refreshPreview(_Side side) async {
    final neutral = side.neutral;
    if (neutral == null) return;
    final stamp = ++side.previewStamp;
    try {
      final preview = await IdCardService.finalizeSide(
          neutral.bytes, _filter, side.masks,
          maxDim: 800);
      if (!mounted || stamp != side.previewStamp) return;
      setState(() => side.preview = preview);
    } catch (_) {
      // Preview is cosmetic — the export path surfaces real errors.
    }
  }

  void _setFilter(ScanFilter f) {
    if (f == _filter) return;
    HapticFeedback.selectionClick();
    setState(() => _filter = f);
    _refreshPreview(_front);
    _refreshPreview(_back);
  }

  Future<void> _create() async {
    final out = await runBusy<OutFile>(
      context,
      label: 'Composing true-size A4…',
      task: () async {
        final sides = <Uint8List>[];
        for (final side in [_front, _back]) {
          final neutral = side.neutral;
          if (neutral == null) continue;
          sides.add(await IdCardService.finalizeSide(
              neutral.bytes, _filter, side.masks));
        }
        final pdf = await IdCardService.compose(sides);
        final stamp = DateTime.now();
        final name =
            'ID-Card_${stamp.year}${stamp.month.toString().padLeft(2, '0')}${stamp.day.toString().padLeft(2, '0')}.pdf';
        return OutFile(name: name, bytes: pdf, mime: 'application/pdf');
      },
    );
    if (out != null && mounted) {
      Navigator.of(context).push(Motion.fadeThrough(
          ResultScreen(tool: Tool.idCard, files: [out])));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFront = _front.neutral != null;
    return Scaffold(
      appBar: AppBar(title: const Text('ID Card → PDF')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Entrance(child: const _InfoNote()),
          const SizedBox(height: 16),
          Entrance(
            index: 1,
            child: _SideCard(
              label: 'FRONT',
              side: _front,
              onCamera: () => _capture(_front, camera: true),
              onGallery: () => _capture(_front, camera: false),
              onMask: () => _editMasks(_front),
              onRotate: () => _rotate(_front),
              onRemove: () => setState(() {
                _front.neutral = null;
                _front.preview = null;
                _front.masks = [];
              }),
            ),
          ),
          const SizedBox(height: 14),
          Entrance(
            index: 2,
            child: _SideCard(
              label: 'BACK',
              side: _back,
              optional: true,
              onCamera: () => _capture(_back, camera: true),
              onGallery: () => _capture(_back, camera: false),
              onMask: () => _editMasks(_back),
              onRotate: () => _rotate(_back),
              onRemove: () => setState(() {
                _back.neutral = null;
                _back.preview = null;
                _back.masks = [];
              }),
            ),
          ),
          const SizedBox(height: 18),
          Entrance(
            index: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Look', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (f, label) in const [
                      (ScanFilter.enhanced, 'Color'),
                      (ScanFilter.grayscale, 'Grayscale'),
                      (ScanFilter.blackWhite, 'Photocopy'),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: _filter == f,
                        onSelected: (_) => _setFilter(f),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
      bottomNavigationBar: BottomBar(
        children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Tool.idCard.style.base,
                foregroundColor: Colors.white,
              ),
              onPressed: hasFront ? _create : null,
              icon: const Icon(Icons.picture_as_pdf_rounded),
              label: Text(_back.neutral != null
                  ? 'Create A4 PDF (front + back)'
                  : 'Create A4 PDF'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideCard extends StatelessWidget {
  final String label;
  final _Side side;
  final bool optional;
  final VoidCallback onCamera, onGallery, onMask, onRotate, onRemove;
  const _SideCard({
    required this.label,
    required this.side,
    required this.onCamera,
    required this.onGallery,
    required this.onMask,
    required this.onRotate,
    required this.onRemove,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = side.preview ?? side.neutral?.bytes;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Tool.idCard.style.base.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(label,
                      style: AppTheme.manrope(800,
                          size: 11.5, color: Tool.idCard.style.base)),
                ),
                if (optional) ...[
                  const SizedBox(width: 8),
                  Text('optional',
                      style: AppTheme.manrope(600,
                          size: 11.5, color: scheme.onSurfaceVariant)),
                ],
                const Spacer(),
                if (image != null) ...[
                  IconButton(
                    tooltip: 'Rotate',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.rotate_90_degrees_cw_rounded,
                        size: 20, color: scheme.onSurfaceVariant),
                    onPressed: onRotate,
                  ),
                  IconButton(
                    tooltip: side.suggested.isNotEmpty && side.masks.isEmpty
                        ? 'Aadhaar number detected — review masks'
                        : 'Mask number',
                    visualDensity: VisualDensity.compact,
                    icon: Badge(
                      isLabelVisible:
                          side.suggested.isNotEmpty && side.masks.isEmpty,
                      smallSize: 8,
                      child: Icon(Icons.password_rounded,
                          size: 20,
                          color: side.masks.isEmpty
                              ? scheme.onSurfaceVariant
                              : Tool.idCard.style.base),
                    ),
                    onPressed: onMask,
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 20, color: scheme.onSurfaceVariant),
                    onPressed: onRemove,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            AspectRatio(
              // Show the capture at its real shape; the export box follows it.
              aspectRatio: side.neutral?.aspect ??
                  IdCardService.cardWidthMm / IdCardService.cardHeightMm,
              child: image != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(image,
                          fit: BoxFit.fill, gaplessPlayback: true),
                    )
                  : _EmptySlot(onCamera: onCamera, onGallery: onGallery),
            ),
            if (image != null && side.masks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.verified_user_rounded,
                      size: 14, color: AppTheme.offlineGreen),
                  const SizedBox(width: 6),
                  Text(
                      '${side.masks.length} mask${side.masks.length == 1 ? '' : 's'} burned in on export',
                      style: AppTheme.manrope(600,
                          size: 11.5, color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  final VoidCallback onCamera, onGallery;
  const _EmptySlot({required this.onCamera, required this.onGallery});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.7), width: 1.2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton.icon(
            onPressed: onCamera,
            icon: const Icon(Icons.photo_camera_rounded),
            label: const Text('Scan'),
          ),
          Container(
            width: 1,
            height: 28,
            color: scheme.outlineVariant.withValues(alpha: 0.7),
          ),
          TextButton.icon(
            onPressed: onGallery,
            icon: const Icon(Icons.photo_library_rounded),
            label: const Text('Gallery'),
          ),
        ],
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: Tool.idCard.style.base.withValues(alpha: 0.07),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.badge_rounded, color: Tool.idCard.style.base),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Aadhaar · PAN · Driving Licence · any card',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Both sides are printed at TRUE card size (85.6 × 54 mm) on one '
              'A4 — the exact format banks and KYC desks accept. Your card '
              'never leaves this phone. Tip: UIDAI recommends masking the '
              'first 8 digits of your Aadhaar number — use the mask button.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
