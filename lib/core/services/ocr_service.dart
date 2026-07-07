import 'dart:io';
import 'dart:ui' show Rect;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'render_service.dart';

/// One recognized line with its bounding box in source-image pixels.
class OcrLine {
  final String text;
  final Rect box;
  const OcrLine(this.text, this.box);
}

/// On-device OCR via ML Kit Text Recognition v2 (bundled model, no network).
class OcrService {
  OcrService._();

  static Future<String> imageText(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result =
          await recognizer.processImage(InputImage.fromFilePath(path));
      return result.text;
    } finally {
      await recognizer.close();
    }
  }

  static Future<List<String>> imagesText(
    List<String> paths, {
    void Function(int done, int total)? onProgress,
  }) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final out = <String>[];
      for (var i = 0; i < paths.length; i++) {
        final result =
            await recognizer.processImage(InputImage.fromFilePath(paths[i]));
        out.add(result.text);
        onProgress?.call(i + 1, paths.length);
      }
      return out;
    } finally {
      await recognizer.close();
    }
  }

  /// Recognized lines with positions — the input for searchable-PDF text
  /// layers. Reuse [recognizer] across a batch; caller closes it.
  static Future<List<OcrLine>> imageLines(
      String path, TextRecognizer recognizer) async {
    final result =
        await recognizer.processImage(InputImage.fromFilePath(path));
    final lines = <OcrLine>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        if (line.text.trim().isEmpty) continue;
        lines.add(OcrLine(line.text, line.boundingBox));
      }
    }
    return lines;
  }

  static TextRecognizer newRecognizer() =>
      TextRecognizer(script: TextRecognitionScript.latin);

  /// OCR every page of a PDF: rasterize at ~216 dpi, feed each page image
  /// to ML Kit. Returns one string per page.
  static Future<List<String>> pdfText(
    String path, {
    void Function(int done, int total)? onProgress,
  }) async {
    final doc = await RenderedDoc.openFile(path);
    final tmp = await getTemporaryDirectory();
    final workDir = Directory(
        p.join(tmp.path, 'ocr_${DateTime.now().millisecondsSinceEpoch}'));
    await workDir.create(recursive: true);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final out = <String>[];
      for (var i = 0; i < doc.pageCount; i++) {
        final bytes = await doc.renderPage(i, scale: 3, png: true);
        final file = File(p.join(workDir.path, 'page_$i.png'));
        await file.writeAsBytes(bytes);
        final result =
            await recognizer.processImage(InputImage.fromFilePath(file.path));
        out.add(result.text);
        onProgress?.call(i + 1, doc.pageCount);
      }
      return out;
    } finally {
      await recognizer.close();
      await doc.close();
      workDir.delete(recursive: true).ignore();
    }
  }
}
