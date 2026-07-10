import 'package:flutter/material.dart';

import '../../ui/theme.dart';

/// Top-level grouping used to organise the home screen.
enum ToolCategory {
  create('Scan & create'),
  organize('Organize pages'),
  annotate('Annotate & sign'),
  secure('Secure & optimize'),
  convert('Convert & extract');

  final String label;
  const ToolCategory(this.label);
}

/// The full toolset. Each tool carries its visual identity and category so
/// cards, headers and history entries stay consistent everywhere.
enum Tool {
  viewer(
    'Read PDF',
    'Fast, private viewer',
    ToolStyle([Color(0xFF5E35B1), Color(0xFF9C7BD8)], Icons.menu_book_rounded),
    ToolCategory.organize,
  ),
  merge(
    'Merge PDF',
    'Combine PDFs into one',
    ToolStyle([Color(0xFF4353FF), Color(0xFF7B6CFF)], Icons.merge_rounded),
    ToolCategory.organize,
  ),
  split(
    'Split PDF',
    'Extract pages to a new PDF',
    ToolStyle([Color(0xFF00897B), Color(0xFF4DD0B1)], Icons.content_cut_rounded),
    ToolCategory.organize,
  ),
  splitFiles(
    'Split to Files',
    'Break into separate PDFs',
    ToolStyle([Color(0xFF00897B), Color(0xFF4DB6AC)], Icons.call_split_rounded),
    ToolCategory.organize,
  ),
  organize(
    'Organize',
    'Reorder · rotate · delete pages',
    ToolStyle([Color(0xFFF4511E), Color(0xFFFF8A65)], Icons.dashboard_customize_rounded),
    ToolCategory.organize,
  ),
  crop(
    'Crop PDF',
    'Trim margins · crop pages',
    ToolStyle([Color(0xFF6D4C41), Color(0xFFA98274)], Icons.crop_rounded),
    ToolCategory.organize,
  ),
  sign(
    'Sign PDF',
    'Draw & place your signature',
    ToolStyle([Color(0xFF00695C), Color(0xFF2BB39A)], Icons.draw_rounded),
    ToolCategory.annotate,
  ),
  addText(
    'Add Text',
    'Fill forms · type on PDF',
    ToolStyle([Color(0xFF00838F), Color(0xFF4DD0E1)], Icons.text_fields_rounded),
    ToolCategory.annotate,
  ),
  draw(
    'Draw',
    'Freehand pen markup',
    ToolStyle([Color(0xFFEC407A), Color(0xFFF48FB1)], Icons.gesture_rounded),
    ToolCategory.annotate,
  ),
  highlight(
    'Highlight',
    'Mark up text in color',
    ToolStyle([Color(0xFFF9A825), Color(0xFFFFD54F)], Icons.highlight_rounded),
    ToolCategory.annotate,
  ),
  watermark(
    'Watermark',
    'Stamp text & page numbers',
    ToolStyle([Color(0xFF7B1FA2), Color(0xFFBA68C8)], Icons.branding_watermark_rounded),
    ToolCategory.annotate,
  ),
  protect(
    'Protect PDF',
    'Lock or unlock with a password',
    ToolStyle([Color(0xFFD81B60), Color(0xFFF0709A)], Icons.lock_rounded),
    ToolCategory.secure,
  ),
  redact(
    'Redact',
    'Destroy sensitive info, truly',
    ToolStyle([Color(0xFF263238), Color(0xFF546E7A)], Icons.visibility_off_rounded),
    ToolCategory.secure,
  ),
  compress(
    'Compress PDF',
    'Fit email & portal size limits',
    ToolStyle([Color(0xFFEF6C00), Color(0xFFFFA751)], Icons.compress_rounded),
    ToolCategory.secure,
  ),
  scanToPdf(
    'Scan → PDF',
    'Camera pages into a PDF',
    ToolStyle([Color(0xFF00ACC1), Color(0xFF5DDEF4)], Icons.document_scanner_rounded),
    ToolCategory.create,
  ),
  imagesToPdf(
    'Images → PDF',
    'Photos into a clean PDF',
    ToolStyle([Color(0xFF1E88E5), Color(0xFF64C1FF)], Icons.picture_as_pdf_rounded),
    ToolCategory.create,
  ),
  idCard(
    'ID Card → PDF',
    'Front & back, true size A4',
    ToolStyle([Color(0xFF283593), Color(0xFF7986CB)], Icons.badge_rounded),
    ToolCategory.create,
  ),
  pdfToWord(
    'PDF → Word',
    'Editable .docx, on-device',
    ToolStyle([Color(0xFF1565C0), Color(0xFF5E9CEA)], Icons.description_rounded),
    ToolCategory.convert,
  ),
  pdfToImages(
    'PDF → Images',
    'Export pages as PNG or JPG',
    ToolStyle([Color(0xFF8E24AA), Color(0xFFC77DDA)], Icons.photo_library_rounded),
    ToolCategory.convert,
  ),
  ocr(
    'Extract Text',
    'On-device OCR, no upload',
    ToolStyle([Color(0xFFFB8C00), Color(0xFFFFC46B)], Icons.text_fields_rounded),
    ToolCategory.convert,
  ),
  searchable(
    'Searchable PDF',
    'Give scans selectable text',
    ToolStyle([Color(0xFF3949AB), Color(0xFF7E8CE0)], Icons.manage_search_rounded),
    ToolCategory.convert,
  ),
  imageConvert(
    'Convert Images',
    'JPG · PNG · resize · shrink',
    ToolStyle([Color(0xFF43A047), Color(0xFF81CB84)], Icons.swap_horiz_rounded),
    ToolCategory.convert,
  );

  final String title;
  final String subtitle;
  final ToolStyle style;
  final ToolCategory category;
  const Tool(this.title, this.subtitle, this.style, this.category);

  static List<Tool> inCategory(ToolCategory c) =>
      Tool.values.where((t) => t.category == c).toList();

  bool matches(String query) {
    final q = query.toLowerCase();
    return title.toLowerCase().contains(q) ||
        subtitle.toLowerCase().contains(q);
  }
}
