import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../../core/models/tool.dart';
import '../../core/services/history_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../../ui/theme.dart';
import '../about/about_screen.dart';
import '../addtext/addtext_screen.dart';
import '../compress/compress_screen.dart';
import '../crop/crop_pdf_screen.dart';
import '../draw/draw_screen.dart';
import '../highlight/highlight_screen.dart';
import '../history/history_screen.dart';
import '../image_convert/image_convert_screen.dart';
import '../images_to_pdf/images_to_pdf_screen.dart';
import '../merge/merge_screen.dart';
import '../ocr/ocr_screen.dart';
import '../organize/organize_screen.dart';
import '../pdf_to_images/pdf_to_images_screen.dart';
import '../pdf_to_word/pdf_to_word_screen.dart';
import '../protect/protect_screen.dart';
import '../redact/redact_screen.dart';
import '../searchable/searchable_screen.dart';
import '../sign/sign_screen.dart';
import '../split/split_screen.dart';
import '../split_files/split_files_screen.dart';
import '../viewer/viewer_launcher.dart';
import '../watermark/watermark_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

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
      case Tool.splitFiles:
        return const SplitFilesScreen();
      case Tool.crop:
        return const CropPdfScreen();
      case Tool.sign:
        return const SignScreen();
      case Tool.draw:
        return const DrawScreen();
      case Tool.addText:
        return const AddTextScreen();
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
      case Tool.pdfToWord:
        return const PdfToWordScreen();
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
    final searching = _query.trim().isNotEmpty;
    final results = searching
        ? Tool.values.where((t) => t.matches(_query)).toList()
        : const <Tool>[];

    return Scaffold(
      body: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          _appBar(context, scheme),
          if (searching)
            ..._searchResults(results)
          else ...[
            SliverToBoxAdapter(child: _PrivacyBanner(onTap: _openAbout)),
            SliverToBoxAdapter(child: _RecentStrip(onSeeAll: _openHistory)),
            for (final cat in ToolCategory.values)
              ..._categorySlivers(cat),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: Center(
                  child: Text('Milled locally. Nothing ever uploaded.',
                      style: AppTheme.manrope(600,
                          size: 12, color: scheme.outline)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openAbout() =>
      Navigator.of(context).push(Motion.sharedAxis(const AboutScreen()));
  void _openHistory() =>
      Navigator.of(context).push(Motion.sharedAxis(const HistoryScreen()));

  Widget _appBar(BuildContext context, ColorScheme scheme) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 20,
      title: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.seed, Color(0xFF7B6CFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.all_inclusive_rounded,
                color: Colors.white, size: 19),
          ),
          const SizedBox(width: 10),
          Text('FileMill',
              style: AppTheme.grotesk(750, size: 22, color: scheme.onSurface)),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'About',
          onPressed: _openAbout,
          icon: const Icon(Icons.info_outline_rounded),
        ),
        IconButton(
          tooltip: 'History',
          onPressed: _openHistory,
          icon: const Icon(Icons.history_rounded),
        ),
        const SizedBox(width: 8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search ${Tool.values.length} tools…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                        FocusScope.of(context).unfocus();
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _categorySlivers(ToolCategory cat) {
    final tools = Tool.inCategory(cat);
    if (tools.isEmpty) return const [];
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        sliver: SliverToBoxAdapter(
          child: Text(cat.label,
              style: AppTheme.grotesk(650,
                  size: 15,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      ),
      _toolGrid(tools),
    ];
  }

  List<Widget> _searchResults(List<Tool> results) {
    if (results.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.search_off_rounded,
            title: 'No tools match',
            message: 'Try “merge”, “scan”, “sign”, “compress”…',
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        sliver: SliverToBoxAdapter(
          child: Text('${results.length} tools',
              style: AppTheme.grotesk(650,
                  size: 15,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      ),
      _toolGrid(results),
    ];
  }

  Widget _toolGrid(List<Tool> tools) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.82,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => _ToolTile(tool: tools[i], screen: _screenFor(tools[i])),
          childCount: tools.length,
        ),
      ),
    );
  }
}

/// Compact tool tile: gradient badge + name, with a container-morph into
/// the tool screen.
class _ToolTile extends StatelessWidget {
  final Tool tool;
  final Widget screen;
  const _ToolTile({required this.tool, required this.screen});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OpenContainer(
      transitionDuration: const Duration(milliseconds: 400),
      transitionType: ContainerTransitionType.fadeThrough,
      closedElevation: 0,
      openElevation: 0,
      closedColor: scheme.surfaceContainerLow,
      openColor: Theme.of(context).scaffoldBackgroundColor,
      middleColor: scheme.surfaceContainerLow,
      closedShape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      openBuilder: (_, close) => screen,
      closedBuilder: (context, open) => InkWell(
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GradientBadge(style: tool.style, size: 46),
              const SizedBox(height: 10),
              Text(
                tool.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.grotesk(600,
                    size: 12.5, height: 1.1, color: scheme.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _PrivacyBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Material(
        color: AppTheme.offlineGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Icon(Icons.wifi_off_rounded,
                    size: 18, color: AppTheme.offlineGreen),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('100% offline',
                          style: AppTheme.manrope(750,
                              size: 13.5,
                              color: isDark
                                  ? const Color(0xFF5ADE8B)
                                  : const Color(0xFF13803B))),
                      Text('Zero network permission · nothing leaves this phone',
                          style: AppTheme.manrope(550,
                              size: 11.5, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentStrip extends StatelessWidget {
  final VoidCallback onSeeAll;
  const _RecentStrip({required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<List<HistoryEntry>>(
      valueListenable: HistoryService.entries,
      builder: (context, entries, _) {
        if (entries.isEmpty) return const SizedBox.shrink();
        final recent = entries.take(8).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 12, 6),
              child: Row(
                children: [
                  Text('Recent',
                      style: AppTheme.grotesk(650,
                          size: 15, color: scheme.onSurfaceVariant)),
                  const Spacer(),
                  TextButton(onPressed: onSeeAll, child: const Text('See all')),
                ],
              ),
            ),
            SizedBox(
              height: 96,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: recent.length,
                itemBuilder: (context, i) {
                  final entry = recent[i];
                  final tool = entry.tool ?? Tool.merge;
                  return GestureDetector(
                    onTap: onSeeAll,
                    child: Container(
                      width: 168,
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              GradientBadge(style: tool.style, size: 30),
                              const Spacer(),
                              Text(humanSize(entry.size),
                                  style: AppTheme.manrope(600,
                                      size: 10.5,
                                      color: scheme.onSurfaceVariant)),
                            ],
                          ),
                          const Spacer(),
                          Text(entry.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.manrope(700,
                                  size: 12.5, color: scheme.onSurface)),
                          Text(tool.title,
                              style: AppTheme.manrope(550,
                                  size: 11, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
