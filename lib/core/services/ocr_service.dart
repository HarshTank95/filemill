import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'render_service.dart';

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
