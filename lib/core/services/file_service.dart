import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// A file the user handed us (picker, camera or share sheet).
class PickedItem {
  final String name;
  final String path;
  final int size;

  /// Decrypted content, set once the user unlocks a password-protected PDF
  /// (see ensureUnlocked). All processing then reads this instead of disk.
  Uint8List? unlockedBytes;

  PickedItem({required this.name, required this.path, required this.size});

  Future<Uint8List> readBytes() async =>
      unlockedBytes ?? await File(path).readAsBytes();

  static Future<PickedItem> fromPath(String path, {String? name}) async {
    final f = File(path);
    return PickedItem(
      name: name ?? p.basename(path),
      path: path,
      size: await f.length(),
    );
  }
}

/// A produced output ready to be saved or shared.
class OutFile {
  final String name;
  final Uint8List bytes;
  final String mime;
  const OutFile({required this.name, required this.bytes, required this.mime});
}

/// All user-file IO goes through here. Reading uses the system pickers
/// (Storage Access Framework under the hood); writing uses
/// ACTION_CREATE_DOCUMENT via FilePicker.saveFile. No storage permissions.
class FileService {
  FileService._();

  static final ImagePicker _imagePicker = ImagePicker();

  static Future<List<PickedItem>> pickPdfs({bool multiple = true}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: multiple,
    );
    return _toItems(result);
  }

  static Future<List<PickedItem>> pickImages({bool multiple = true}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: multiple,
    );
    return _toItems(result);
  }

  static Future<List<PickedItem>> _toItems(FilePickerResult? result) async {
    if (result == null) return const [];
    final items = <PickedItem>[];
    for (final f in result.files) {
      if (f.path == null) continue;
      items.add(PickedItem(name: f.name, path: f.path!, size: f.size));
    }
    return items;
  }

  /// One camera shot; re-encoded to JPEG (strips EXIF rotation surprises).
  static Future<PickedItem?> capturephoto() async {
    final shot = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
      maxWidth: 3000,
      maxHeight: 3000,
    );
    if (shot == null) return null;
    return PickedItem.fromPath(shot.path, name: shot.name);
  }

  /// Writes bytes to the app temp dir and returns them as a pickable item
  /// (used for processed scan pages).
  static Future<PickedItem> writeTemp(String name, Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final path =
        p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}_$name');
    await File(path).writeAsBytes(bytes);
    return PickedItem(name: name, path: path, size: bytes.length);
  }

  /// Save via the system "create document" dialog. Returns the chosen
  /// location, or null if the user cancelled.
  static Future<String?> saveOut(OutFile file) {
    return FilePicker.platform.saveFile(
      fileName: file.name,
      type: FileType.any,
      bytes: file.bytes,
    );
  }

  static Future<void> shareOut(List<OutFile> files, {String? text}) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final xfiles = <XFile>[];
    for (final f in files) {
      final path = p.join(dir.path, 'share_$stamp', f.name);
      final out = File(path);
      await out.create(recursive: true);
      await out.writeAsBytes(f.bytes);
      xfiles.add(XFile(path, mimeType: f.mime));
    }
    await SharePlus.instance.share(ShareParams(files: xfiles, text: text));
  }

  static Future<OutFile> zip(List<OutFile> files, String zipName) async {
    final bytes = await compute(_zipSync, files);
    return OutFile(name: zipName, bytes: bytes, mime: 'application/zip');
  }

  static Uint8List _zipSync(List<OutFile> files) {
    final archive = Archive();
    for (final f in files) {
      archive.addFile(ArchiveFile(f.name, f.bytes.length, f.bytes));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
}
