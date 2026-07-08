import 'package:flutter/material.dart';

import '../../core/models/tool.dart';
import '../../ui/common.dart';
import '../../ui/theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.seed, Color(0xFF7B6CFF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.all_inclusive_rounded,
                      color: Colors.white, size: 44),
                ),
                const SizedBox(height: 14),
                Text('FileMill',
                    style: AppTheme.grotesk(750, size: 28, color: scheme.onSurface)),
                const SizedBox(height: 4),
                Text('Offline PDF & file toolkit',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 14),
                const PrivacyPill(),
              ],
            ),
          ),
          const SizedBox(height: 26),
          _Section(
            title: 'Your files never leave your device',
            child: Text(
              'FileMill ships with no INTERNET permission at all. Every tool — '
              'merging, scanning, OCR, signing, redaction — runs entirely on '
              'your phone. There is no upload, no account, no ads, and no way '
              'for the app to send your documents anywhere. You can verify this '
              'in Android Settings → Apps → FileMill → Permissions: the list is '
              'empty.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
          const SizedBox(height: 18),
          _Section(
            title: 'Everything it does',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final tool in Tool.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Icon(tool.style.icon,
                            size: 18, color: tool.style.base),
                        const SizedBox(width: 12),
                        Text(tool.title,
                            style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _Section(
            title: 'Built with',
            child: Text(
              'Flutter · on-device Google ML Kit OCR · Syncfusion & pure-Dart '
              'PDF engines · isolate-based processing · Storage Access '
              'Framework. Fonts (Manrope, Space Grotesk) are bundled, so even '
              'typography never phones home.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('Milled locally. Nothing ever uploaded.',
                style: AppTheme.manrope(600, size: 12, color: scheme.outline)),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
