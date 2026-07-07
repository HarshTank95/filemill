import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Saved signatures live in app-private storage as transparent PNGs, so
/// re-signing the next document is one tap. Local-only, like everything.
class SignatureService {
  SignatureService._();

  static Future<Directory> _dir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'signatures'));
    await dir.create(recursive: true);
    return dir;
  }

  /// Newest first.
  static Future<List<File>> list() async {
    final dir = await _dir();
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.png'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  static Future<File> save(Uint8List png) async {
    final dir = await _dir();
    final file =
        File(p.join(dir.path, 'sig_${DateTime.now().millisecondsSinceEpoch}.png'));
    await file.writeAsBytes(png);
    return file;
  }

  static Future<void> delete(File file) => file.delete();
}
