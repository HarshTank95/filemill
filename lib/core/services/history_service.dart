import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/tool.dart';
import 'file_service.dart';

class HistoryEntry {
  final String id;
  final String toolName;
  final String fileName;
  final int size;
  final String path; // private app-storage copy, powers re-share/re-save
  final DateTime date;

  const HistoryEntry({
    required this.id,
    required this.toolName,
    required this.fileName,
    required this.size,
    required this.path,
    required this.date,
  });

  Tool? get tool {
    for (final t in Tool.values) {
      if (t.name == toolName) return t;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tool': toolName,
        'file': fileName,
        'size': size,
        'path': path,
        'date': date.toIso8601String(),
      };

  static HistoryEntry fromJson(Map<String, dynamic> j) => HistoryEntry(
        id: j['id'] as String,
        toolName: j['tool'] as String,
        fileName: j['file'] as String,
        size: j['size'] as int,
        path: j['path'] as String,
        date: DateTime.parse(j['date'] as String),
      );
}

/// Local-only history of produced files. Copies live in app-private storage
/// (reinforces the "nothing leaves the device" brand); index is a JSON file.
class HistoryService {
  HistoryService._();

  static const int _maxEntries = 40;
  static final ValueNotifier<List<HistoryEntry>> entries = ValueNotifier([]);
  static Directory? _dir;

  static Future<void> init() async {
    try {
      final support = await getApplicationSupportDirectory();
      _dir = Directory(p.join(support.path, 'history'));
      await _dir!.create(recursive: true);
      final index = File(p.join(_dir!.path, 'index.json'));
      if (await index.exists()) {
        final list = (jsonDecode(await index.readAsString()) as List)
            .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
            .toList();
        entries.value = list;
      }
    } catch (_) {
      // History is a convenience; never block the app on it.
    }
  }

  static Future<void> record(Tool tool, OutFile file) async {
    final dir = _dir;
    if (dir == null) return;
    try {
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final copy = File(p.join(dir.path, '${id}_${file.name}'));
      await copy.writeAsBytes(file.bytes);
      final entry = HistoryEntry(
        id: id,
        toolName: tool.name,
        fileName: file.name,
        size: file.bytes.length,
        path: copy.path,
        date: DateTime.now(),
      );
      final list = [entry, ...entries.value];
      while (list.length > _maxEntries) {
        final removed = list.removeLast();
        File(removed.path).delete().ignore();
      }
      entries.value = list;
      await _persist();
    } catch (_) {}
  }

  static Future<void> remove(HistoryEntry entry) async {
    File(entry.path).delete().ignore();
    entries.value =
        entries.value.where((e) => e.id != entry.id).toList(growable: false);
    await _persist();
  }

  static Future<void> clear() async {
    for (final e in entries.value) {
      File(e.path).delete().ignore();
    }
    entries.value = const [];
    await _persist();
  }

  static Future<void> _persist() async {
    final dir = _dir;
    if (dir == null) return;
    final index = File(p.join(dir.path, 'index.json'));
    await index.writeAsString(
        jsonEncode([for (final e in entries.value) e.toJson()]));
  }
}
