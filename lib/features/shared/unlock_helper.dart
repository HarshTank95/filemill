import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/services/file_service.dart';
import '../../core/services/pdf_service.dart';
import '../../ui/common.dart';

/// Makes [item] processable by any tool: if the PDF is password-protected,
/// prompts for the password and stashes the decrypted bytes on the item.
/// Returns false when the user cancels (the tool should abort quietly).
Future<bool> ensureUnlocked(BuildContext context, PickedItem item) async {
  if (item.unlockedBytes != null) return true;
  final raw = await item.readBytes();
  var locked = false;
  try {
    locked = await PdfService.isProtected(raw);
  } catch (_) {
    // Not decidable here — let the tool surface its own friendly error.
    return true;
  }
  if (!locked) return true;
  if (!context.mounted) return false;
  final unlocked = await showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UnlockDialog(name: item.name, raw: raw),
  );
  if (unlocked == null) return false;
  item.unlockedBytes = unlocked;
  return true;
}

class _UnlockDialog extends StatefulWidget {
  final String name;
  final Uint8List raw;
  const _UnlockDialog({required this.name, required this.raw});

  @override
  State<_UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends State<_UnlockDialog> {
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _try() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await PdfService.unlock(widget.raw, _password.text);
      if (mounted) Navigator.of(context).pop(bytes);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.lock_rounded, color: scheme.primary),
      title: const Text('Protected PDF'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _password,
            obscureText: true,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => _busy ? null : _try(),
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.key_rounded),
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _try,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Text('Unlock'),
        ),
      ],
    );
  }
}
