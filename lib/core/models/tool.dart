import 'package:flutter/material.dart';

import '../../ui/theme.dart';

/// The Stage-1 toolset. Each tool carries its visual identity so cards,
/// headers and history entries stay consistent everywhere.
enum Tool {
  viewer(
    'Read PDF',
    'Fast, private viewer',
    ToolStyle([Color(0xFF5E35B1), Color(0xFF9C7BD8)], Icons.menu_book_rounded),
  ),
  merge(
    'Merge PDF',
    'Combine PDFs into one',
    ToolStyle([Color(0xFF4353FF), Color(0xFF7B6CFF)], Icons.merge_rounded),
  ),
  split(
    'Split PDF',
    'Extract pages to a new PDF',
    ToolStyle([Color(0xFF00897B), Color(0xFF4DD0B1)], Icons.content_cut_rounded),
  ),
  organize(
    'Organize',
    'Reorder · rotate · delete pages',
    ToolStyle([Color(0xFFF4511E), Color(0xFFFF8A65)], Icons.dashboard_customize_rounded),
  ),
  sign(
    'Sign PDF',
    'Draw & place your signature',
    ToolStyle([Color(0xFF00695C), Color(0xFF2BB39A)], Icons.draw_rounded),
  ),
  protect(
    'Protect PDF',
    'Lock or unlock with a password',
    ToolStyle([Color(0xFFD81B60), Color(0xFFF0709A)], Icons.lock_rounded),
  ),
  compress(
    'Compress PDF',
    'Fit email & portal size limits',
    ToolStyle([Color(0xFFEF6C00), Color(0xFFFFA751)], Icons.compress_rounded),
  ),
  pdfToImages(
    'PDF → Images',
    'Export pages as PNG or JPG',
    ToolStyle([Color(0xFF8E24AA), Color(0xFFC77DDA)], Icons.photo_library_rounded),
  ),
  imagesToPdf(
    'Images → PDF',
    'Photos into a clean PDF',
    ToolStyle([Color(0xFF1E88E5), Color(0xFF64C1FF)], Icons.picture_as_pdf_rounded),
  ),
  scanToPdf(
    'Scan → PDF',
    'Camera pages into a PDF',
    ToolStyle([Color(0xFF00ACC1), Color(0xFF5DDEF4)], Icons.document_scanner_rounded),
  ),
  ocr(
    'Extract Text',
    'On-device OCR, no upload',
    ToolStyle([Color(0xFFFB8C00), Color(0xFFFFC46B)], Icons.text_fields_rounded),
  );

  final String title;
  final String subtitle;
  final ToolStyle style;
  const Tool(this.title, this.subtitle, this.style);
}
