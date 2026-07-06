import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Small shared UI atoms: privacy pill, gradient icon badge, section header,
/// empty state, busy overlay runner.

class PrivacyPill extends StatelessWidget {
  final bool compact;
  const PrivacyPill({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14, vertical: compact ? 6 : 8),
      decoration: BoxDecoration(
        color: AppTheme.offlineGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
            color: AppTheme.offlineGreen.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded,
              size: compact ? 13 : 15, color: AppTheme.offlineGreen),
          const SizedBox(width: 6),
          Text(
            compact ? '100% offline' : '100% offline · zero network permission',
            style: AppTheme.manrope(750,
                size: compact ? 11 : 12.5,
                color: scheme.brightness == Brightness.dark
                    ? const Color(0xFF5ADE8B)
                    : const Color(0xFF13803B)),
          ),
        ],
      ),
    );
  }
}

class GradientBadge extends StatelessWidget {
  final ToolStyle style;
  final double size;
  const GradientBadge({super.key, required this.style, this.size = 52});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: style.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.33),
        boxShadow: [
          BoxShadow(
            color: style.base.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(style.icon, color: Colors.white, size: size * 0.5),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionHeader(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 26, 4, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: AppTheme.grotesk(650,
                    size: 17,
                    color: Theme.of(context).colorScheme.onSurface)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: scheme.primary),
            ),
            const SizedBox(height: 20),
            Text(title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Runs [task] behind a modal busy card. Returns the result, or null if the
/// task threw (the error is surfaced as a snackbar).
Future<T?> runBusy<T>(
  BuildContext context, {
  required String label,
  required Future<T> Function() task,
  ValueListenable<String?>? status,
}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);
  HapticFeedback.lightImpact();
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(strokeWidth: 5),
              ),
              const SizedBox(height: 20),
              Text(label,
                  style: AppTheme.manrope(700, size: 15),
                  textAlign: TextAlign.center),
              if (status != null)
                ValueListenableBuilder<String?>(
                  valueListenable: status,
                  builder: (_, s, child) => s == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(s,
                              style: AppTheme.manrope(550,
                                  size: 12.5,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                        ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    final result = await task();
    nav.pop();
    HapticFeedback.mediumImpact();
    return result;
  } catch (e, stack) {
    nav.pop();
    HapticFeedback.heavyImpact();
    // Full details go to the log only — never leak internals to the UI.
    debugPrint('FileMill task failed: $e\n$stack');
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    return null;
  }
}

/// Short, human message for any failure. Raw exception text (class names,
/// paths, internals) must never reach the screen.
String friendlyError(Object e) {
  final s = e.toString();
  if (s.contains('Incorrect password')) {
    return 'Incorrect password — try again.';
  }
  if (s.contains('password') || s.contains('encrypt')) {
    return 'This PDF is password-protected.';
  }
  if (s.contains('Unsupported image')) {
    return 'This image format isn\'t supported.';
  }
  if (s.contains('Cannot open') || s.contains('format')) {
    return 'This file could not be read.';
  }
  return 'Something went wrong. Please try again.';
}

String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
