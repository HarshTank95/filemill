import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/models/tool.dart';
import '../../core/services/file_service.dart';
import '../../core/services/metadata_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../../ui/theme.dart';
import '../merge/merge_screen.dart' show BottomBar;
import '../result/result_screen.dart';
import '../shared/unlock_helper.dart';

const _criticalColor = Color(0xFFE53935);
const _moderateColor = Color(0xFFEF9A00);

/// Metadata Cleaner: see everything a file secretly says about you, then
/// scrub it — verified at the raw-byte level, fully on-device.
class MetadataScreen extends StatefulWidget {
  const MetadataScreen({super.key});

  @override
  State<MetadataScreen> createState() => _MetadataScreenState();
}

class _MetadataScreenState extends State<MetadataScreen> {
  PickedItem? _item;
  Uint8List? _bytes;
  MetaReport? _report;
  bool _cleanedVerified = false;

  Future<void> _pick() async {
    final picked = await FileService.pickInspectables();
    if (picked.isEmpty || !mounted) return;
    final item = picked.first;
    if (item.name.toLowerCase().endsWith('.pdf')) {
      if (!await ensureUnlocked(context, item)) return;
      if (!mounted) return;
    }
    final outcome = await runBusy<(Uint8List, MetaReport)>(
      context,
      label: 'Reading hidden data…',
      task: () async {
        final bytes = item.unlockedBytes ?? await item.readBytes();
        return (bytes, await MetadataService.inspect(bytes));
      },
    );
    if (outcome == null || !mounted) return;
    setState(() {
      _item = item;
      _bytes = outcome.$1;
      _report = outcome.$2;
      _cleanedVerified = false;
    });
  }

  Future<void> _clean() async {
    final item = _item!, bytes = _bytes!;
    final outcome = await runBusy<(OutFile, MetaReport)>(
      context,
      label: 'Scrubbing & verifying…',
      task: () async {
        final cleaned = await MetadataService.clean(bytes);
        // Proof: re-inspect the OUTPUT — the report the user sees next is
        // measured on the actual cleaned bytes.
        final after = await MetadataService.inspect(cleaned);
        final base = p.basenameWithoutExtension(item.name);
        final ext = p.extension(item.name);
        return (
          OutFile(
              name: '${base}_clean$ext', bytes: cleaned, mime: _mime(ext)),
          after
        );
      },
    );
    if (outcome == null || !mounted) return;
    setState(() {
      _report = outcome.$2;
      _cleanedVerified = true;
    });
    Navigator.of(context).push(Motion.fadeThrough(
        ResultScreen(tool: Tool.metadata, files: [outcome.$1])));
  }

  static String _mime(String ext) {
    switch (ext.toLowerCase()) {
      case '.pdf':
        return 'application/pdf';
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case '.xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case '.pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      default:
        return 'application/octet-stream';
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('Metadata Cleaner')),
      body: report == null ? _intro() : _reportView(report),
      bottomNavigationBar: report == null || !report.cleanable
          ? null
          : BottomBar(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Tool.metadata.style.base,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _cleanedVerified ? null : _clean,
                    icon: const Icon(Icons.cleaning_services_rounded),
                    label: Text(_cleanedVerified
                        ? 'Cleaned & verified'
                        : report.findings.isEmpty
                            ? 'Clean anyway'
                            : 'Clean this file'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _intro() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Entrance(
          child: Card(
            color: Tool.metadata.style.base.withValues(alpha: 0.07),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.privacy_tip_rounded,
                          color: Tool.metadata.style.base),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('What does this file say about you?',
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Photos can carry your location, device and exact '
                    'timestamps. PDFs and Office files carry author names, '
                    'companies and editing history. See it all — then scrub '
                    'it with one tap. Inspection and cleaning happen entirely '
                    'on this phone.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.45),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in const [
                        'JPG',
                        'PNG',
                        'PDF',
                        'DOCX',
                        'XLSX',
                        'PPTX'
                      ])
                        Chip(
                          label: Text(t),
                          visualDensity: VisualDensity.compact,
                          labelStyle: AppTheme.manrope(700, size: 11),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Entrance(
          index: 1,
          child: FilledButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('Choose a file to inspect'),
          ),
        ),
      ],
    );
  }

  Widget _reportView(MetaReport report) {
    final scheme = Theme.of(context).colorScheme;
    final clean = report.findings.isEmpty;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Entrance(
          child: Card(
            color: (clean ? AppTheme.offlineGreen : _criticalColor)
                .withValues(alpha: clean ? 0.08 : 0.06),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    clean
                        ? Icons.verified_user_rounded
                        : Icons.visibility_rounded,
                    color: clean ? AppTheme.offlineGreen : _criticalColor,
                    size: 32,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          clean
                              ? _cleanedVerified
                                  ? 'Verified clean'
                                  : 'Nothing sensitive found'
                              : '${report.findings.length} thing${report.findings.length == 1 ? '' : 's'} this file reveals',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${report.kind} · ${_item?.name ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_cleanedVerified)
          Entrance(
            index: 1,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'This report was re-run on the cleaned file — what you see '
                'is what remains.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        const SizedBox(height: 6),
        for (var i = 0; i < report.findings.length; i++)
          Entrance(
            index: i + 1,
            child: _FindingTile(finding: report.findings[i]),
          ),
        if (report.cleanNote != null) ...[
          const SizedBox(height: 14),
          Entrance(
            index: report.findings.length + 1,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    report.cleanNote!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Center(
          child: TextButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.folder_open_rounded, size: 18),
            label: const Text('Inspect another file'),
          ),
        ),
      ],
    );
  }
}

class _FindingTile extends StatelessWidget {
  final MetaFinding finding;
  const _FindingTile({required this.finding});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final critical = finding.severity == MetaSeverity.critical;
    final color = critical ? _criticalColor : _moderateColor;
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                critical ? Icons.warning_rounded : Icons.info_rounded,
                size: 18,
                color: color,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(finding.label,
                      style: AppTheme.manrope(750, size: 13.5)),
                  const SizedBox(height: 2),
                  Text(finding.value,
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 3),
                  Text(finding.detail,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
