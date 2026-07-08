import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../../core/models/tool.dart';
import '../../core/services/history_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../../ui/theme.dart';
import '../compress/compress_screen.dart';
import '../highlight/highlight_screen.dart';
import '../history/history_screen.dart';
import '../image_convert/image_convert_screen.dart';
import '../images_to_pdf/images_to_pdf_screen.dart';
import '../merge/merge_screen.dart';
import '../ocr/ocr_screen.dart';
import '../organize/organize_screen.dart';
import '../pdf_to_images/pdf_to_images_screen.dart';
import '../protect/protect_screen.dart';
import '../redact/redact_screen.dart';
import '../searchable/searchable_screen.dart';
import '../sign/sign_screen.dart';
import '../split/split_screen.dart';
import '../viewer/viewer_launcher.dart';
import '../watermark/watermark_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Widget _screenFor(Tool tool) {
    switch (tool) {
      case Tool.viewer:
        return const ViewerLauncherScreen();
      case Tool.merge:
        return const MergeScreen();
      case Tool.split:
        return const SplitScreen();
      case Tool.organize:
        return const OrganizeScreen();
      case Tool.sign:
        return const SignScreen();
      case Tool.protect:
        return const ProtectScreen();
      case Tool.compress:
        return const CompressScreen();
      case Tool.watermark:
        return const WatermarkScreen();
      case Tool.highlight:
        return const HighlightScreen();
      case Tool.redact:
        return const RedactScreen();
      case Tool.pdfToImages:
        return const PdfToImagesScreen();
      case Tool.imagesToPdf:
        return const ImagesToPdfScreen();
      case Tool.scanToPdf:
        return const ImagesToPdfScreen(cameraMode: true);
      case Tool.ocr:
        return const OcrScreen();
      case Tool.searchable:
        return const SearchableScreen();
      case Tool.imageConvert:
        return const ImageConvertScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const pdfTools = [
      Tool.viewer,
      Tool.sign,
      Tool.merge,
      Tool.split,
      Tool.organize,
      Tool.compress,
      Tool.protect,
      Tool.highlight,
      Tool.redact,
      Tool.watermark,
      Tool.pdfToImages,
    ];
    const createTools = [
      Tool.scanToPdf,
      Tool.imagesToPdf,
      Tool.ocr,
      Tool.searchable,
      Tool.imageConvert,
    ];

    return Scaffold(
      body: SafeArea(
        child: AnimationLimiter(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    ...AnimationConfiguration.toStaggeredList(
                      duration: const Duration(milliseconds: 420),
                      childAnimationBuilder: (child) => SlideAnimation(
                        verticalOffset: 26,
                        curve: Motion.decelerate,
                        child: FadeInAnimation(child: child),
                      ),
                      children: [
                        _Header(onHistory: () {
                          Navigator.of(context)
                              .push(Motion.sharedAxis(const HistoryScreen()));
                        }),
                        const SizedBox(height: 18),
                        const _HeroCard(),
                        const SectionHeader('PDF tools'),
                        _ToolGrid(
                            tools: pdfTools, screenBuilder: _screenFor),
                        const SectionHeader('Create & capture'),
                        _ToolGrid(
                            tools: createTools, screenBuilder: _screenFor),
                        const _RecentSection(),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            'Milled locally. Nothing ever uploaded.',
                            style: AppTheme.manrope(600,
                                size: 12, color: scheme.outline),
                          ),
                        ),
                      ],
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onHistory;
  const _Header({required this.onHistory});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.seed, Color(0xFF7B6CFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(13),
          ),
          child:
              const Icon(Icons.all_inclusive_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Text('FileMill',
            style: AppTheme.grotesk(750, size: 26, color: scheme.onSurface)),
        const Spacer(),
        IconButton.filledTonal(
          tooltip: 'History',
          onPressed: onHistory,
          icon: const Icon(Icons.history_rounded),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1C2440), const Color(0xFF16192B)]
              : [const Color(0xFF283593), const Color(0xFF4353FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Every file tool.\nZero uploads.',
            style: AppTheme.grotesk(700,
                size: 26, height: 1.15, color: Colors.white),
          ),
          const SizedBox(height: 10),
          Text(
            'Merge, split, scan and read documents entirely on this phone. FileMill can\'t touch the internet — by design.',
            style: AppTheme.manrope(550,
                size: 13.5,
                height: 1.45,
                color: Colors.white.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 14),
          const PrivacyPill(),
        ],
      ),
    );
  }
}

class _ToolGrid extends StatelessWidget {
  final List<Tool> tools;
  final Widget Function(Tool) screenBuilder;
  const _ToolGrid({required this.tools, required this.screenBuilder});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: [
        for (final tool in tools)
          OpenContainer(
            transitionDuration: const Duration(milliseconds: 420),
            transitionType: ContainerTransitionType.fadeThrough,
            closedElevation: 0,
            openElevation: 0,
            closedColor: scheme.surfaceContainerLow,
            openColor: Theme.of(context).scaffoldBackgroundColor,
            middleColor: scheme.surfaceContainerLow,
            closedShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            openBuilder: (_, close) => screenBuilder(tool),
            closedBuilder: (context, open) => InkWell(
              onTap: open,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GradientBadge(style: tool.style, size: 44),
                    const Spacer(),
                    Text(tool.title,
                        style: AppTheme.grotesk(650,
                            size: 16, color: scheme.onSurface)),
                    const SizedBox(height: 3),
                    Text(
                      tool.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.manrope(550,
                          size: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RecentSection extends StatelessWidget {
  const _RecentSection();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<HistoryEntry>>(
      valueListenable: HistoryService.entries,
      builder: (context, entries, _) {
        if (entries.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              'Recent',
              trailing: TextButton(
                onPressed: () => Navigator.of(context)
                    .push(Motion.sharedAxis(const HistoryScreen())),
                child: const Text('See all'),
              ),
            ),
            for (final entry in entries.take(3))
              HistoryTile(entry: entry, margin: 10),
          ],
        );
      },
    );
  }
}
