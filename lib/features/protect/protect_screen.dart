import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/models/tool.dart';
import '../../core/services/file_service.dart';
import '../../core/services/pdf_service.dart';
import '../../ui/common.dart';
import '../../ui/motion.dart';
import '../../ui/theme.dart';
import '../merge/merge_screen.dart';
import '../result/result_screen.dart';

/// Lock a PDF with AES-256, or remove the password from a locked one.
/// The mode is detected automatically from the picked file.
class ProtectScreen extends StatefulWidget {
  final PickedItem? initial;
  const ProtectScreen({super.key, this.initial});

  @override
  State<ProtectScreen> createState() => _ProtectScreenState();
}

class _ProtectScreenState extends State<ProtectScreen> {
  PickedItem? _item;
  bool? _locked;
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _open(widget.initial!);
    _password.addListener(() => setState(() {}));
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await FileService.pickPdfs(multiple: false);
    if (picked.isEmpty) return;
    await _open(picked.first);
  }

  Future<void> _open(PickedItem item) async {
    final locked = await runBusy<bool>(
      context,
      label: 'Checking ${item.name}…',
      task: () async => PdfService.isProtected(await item.readBytes()),
    );
    if (locked == null) return;
    setState(() {
      _item = item;
      _locked = locked;
      _password.clear();
      _confirm.clear();
    });
  }

  bool get _canSubmit {
    if (_locked == true) return _password.text.isNotEmpty;
    return _password.text.length >= 4 && _password.text == _confirm.text;
  }

  Future<void> _run() async {
    final item = _item!;
    final locked = _locked!;
    final out = await runBusy<OutFile>(
      context,
      label: locked ? 'Removing password…' : 'Encrypting with AES-256…',
      task: () async {
        final Uint8List src = await item.readBytes();
        final bytes = locked
            ? await PdfService.unlock(src, _password.text)
            : await PdfService.protect(src, _password.text);
        final base =
            item.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
        return OutFile(
          name: locked ? '${base}_unlocked.pdf' : '${base}_protected.pdf',
          bytes: bytes,
          mime: 'application/pdf',
        );
      },
    );
    if (out != null && mounted) {
      Navigator.of(context).push(Motion.fadeThrough(
          ResultScreen(tool: Tool.protect, files: [out])));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = _item;
    final locked = _locked;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Protect PDF'),
        actions: [
          if (item != null)
            IconButton(
              tooltip: 'Open another PDF',
              icon: const Icon(Icons.folder_open_rounded),
              onPressed: _pick,
            ),
        ],
      ),
      body: item == null || locked == null
          ? EmptyState(
              icon: Tool.protect.style.icon,
              title: 'Lock it down — locally',
              message:
                  'Add a password to a PDF, or remove one you know. AES-256 encryption, done entirely on this phone.',
              action: FilledButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Open PDF'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Entrance(
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      leading: GradientBadge(
                          style: Tool.protect.style, size: 46),
                      title: Text(item.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(humanSize(item.size)),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: locked
                              ? scheme.errorContainer
                              : AppTheme.offlineGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              locked
                                  ? Icons.lock_rounded
                                  : Icons.lock_open_rounded,
                              size: 13,
                              color: locked
                                  ? scheme.onErrorContainer
                                  : AppTheme.offlineGreen,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              locked ? 'Locked' : 'Unlocked',
                              style: AppTheme.manrope(750,
                                  size: 11,
                                  color: locked
                                      ? scheme.onErrorContainer
                                      : AppTheme.offlineGreen),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Entrance(
                  index: 1,
                  child: Text(
                    locked
                        ? 'This PDF is password-protected. Enter its password to save an unlocked copy.'
                        : 'Choose a password. You\'ll need it every time this PDF is opened — FileMill can\'t recover it.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 14),
                Entrance(
                  index: 2,
                  child: TextField(
                    controller: _password,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText:
                          locked ? 'Current password' : 'New password',
                      prefixIcon: const Icon(Icons.key_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                ),
                if (!locked) ...[
                  const SizedBox(height: 12),
                  Entrance(
                    index: 3,
                    child: TextField(
                      controller: _confirm,
                      obscureText: _obscure,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: 'Confirm password',
                        prefixIcon: const Icon(Icons.key_rounded),
                        errorText: _confirm.text.isNotEmpty &&
                                _confirm.text != _password.text
                            ? 'Passwords don\'t match'
                            : null,
                      ),
                    ),
                  ),
                  if (_password.text.isNotEmpty &&
                      _password.text.length < 4)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 4),
                      child: Text('Use at least 4 characters',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.error)),
                    ),
                ],
                const SizedBox(height: 18),
                Entrance(
                  index: 4,
                  child: Row(
                    children: [
                      Icon(Icons.verified_user_rounded,
                          size: 15, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'AES-256 encryption, performed on-device. Nothing is uploaded.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: item == null || locked == null
          ? null
          : BottomBar(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Tool.protect.style.base,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _canSubmit ? _run : null,
                    icon: Icon(locked
                        ? Icons.lock_open_rounded
                        : Icons.lock_rounded),
                    label: Text(locked ? 'Unlock & save' : 'Protect & save'),
                  ),
                ),
              ],
            ),
    );
  }
}
