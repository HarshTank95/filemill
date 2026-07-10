import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// One extracted word with its exact position — the unit of comparison.
/// Because tokens come from the PDF's own text layer with glyph-accurate
/// bounds, a diff over them is exact: no OCR, no reconstruction, no guesses.
class DiffToken {
  final String text;
  final int page; // 0-based
  final double x, y, w, h; // PDF points
  const DiffToken(this.text, this.page, this.x, this.y, this.w, this.h);
}

enum ChangeKind { added, removed, changed }

/// A grouped run of differences: words removed from the original and/or
/// words added in the revised version, plus a little surrounding context.
class ChangeBlock {
  final ChangeKind kind;
  final List<DiffToken> before; // tokens in the ORIGINAL (empty for added)
  final List<DiffToken> after; // tokens in the REVISED (empty for removed)
  final String contextBefore, contextAfter; // equal words around the change
  final int pageA, pageB; // where to look in each document

  const ChangeBlock({
    required this.kind,
    required this.before,
    required this.after,
    required this.contextBefore,
    required this.contextAfter,
    required this.pageA,
    required this.pageB,
  });

  String get beforeText => before.map((t) => t.text).join(' ');
  String get afterText => after.map((t) => t.text).join(' ');
}

class CompareResult {
  final List<ChangeBlock> blocks;
  final int pagesA, pagesB;
  final List<double> pageWidthsA, pageHeightsA, pageWidthsB, pageHeightsB;
  final int tokensA, tokensB;

  /// Pages (0-based, per document) that have no text layer at all — they
  /// can only be compared visually.
  final List<int> scannedPagesA, scannedPagesB;

  const CompareResult({
    required this.blocks,
    required this.pagesA,
    required this.pagesB,
    required this.pageWidthsA,
    required this.pageHeightsA,
    required this.pageWidthsB,
    required this.pageHeightsB,
    required this.tokensA,
    required this.tokensB,
    required this.scannedPagesA,
    required this.scannedPagesB,
  });

  bool get identicalText => blocks.isEmpty;
  int get added => blocks.where((b) => b.kind == ChangeKind.added).length;
  int get removed => blocks.where((b) => b.kind == ChangeKind.removed).length;
  int get edited => blocks.where((b) => b.kind == ChangeKind.changed).length;
}

/// Exact, on-device PDF comparison. Extraction and diff run in an isolate.
class PdfCompareService {
  PdfCompareService._();

  static Future<CompareResult> compare(Uint8List original, Uint8List revised) =>
      compute(_compare, [original, revised]);
}

// ---------------------------------------------------------------------------
// Extraction
// ---------------------------------------------------------------------------

class _Doc {
  final List<DiffToken> tokens;
  final List<double> widths, heights;
  final List<int> scanned;
  _Doc(this.tokens, this.widths, this.heights, this.scanned);
}

_Doc _extract(Uint8List bytes) {
  final doc = PdfDocument(inputBytes: bytes);
  final lines = PdfTextExtractor(doc).extractTextLines();
  final tokens = <DiffToken>[];
  final pagesWithText = <int>{};
  for (final line in lines) {
    for (final w in line.wordCollection) {
      final t = w.text.trim();
      if (t.isEmpty) continue;
      pagesWithText.add(line.pageIndex);
      tokens.add(DiffToken(t, line.pageIndex, w.bounds.left, w.bounds.top,
          w.bounds.width, w.bounds.height));
    }
  }
  final widths = <double>[], heights = <double>[];
  final scanned = <int>[];
  for (var i = 0; i < doc.pages.count; i++) {
    widths.add(doc.pages[i].size.width);
    heights.add(doc.pages[i].size.height);
    if (!pagesWithText.contains(i)) scanned.add(i);
  }
  doc.dispose();
  return _Doc(tokens, widths, heights, scanned);
}

// ---------------------------------------------------------------------------
// Diff (patience algorithm over token texts)
// ---------------------------------------------------------------------------

/// One primitive diff operation over token index ranges.
class _Op {
  static const equal = 0, del = 1, ins = 2;
  final int kind;
  final int aStart, aEnd; // [aStart, aEnd) in A
  final int bStart, bEnd; // [bStart, bEnd) in B
  const _Op(this.kind, this.aStart, this.aEnd, this.bStart, this.bEnd);
}

CompareResult _compare(List<Uint8List> docs) {
  final a = _extract(docs[0]);
  final b = _extract(docs[1]);
  final ta = [for (final t in a.tokens) t.text];
  final tb = [for (final t in b.tokens) t.text];

  final ops = <_Op>[];
  _diff(ta, tb, 0, ta.length, 0, tb.length, ops);

  return CompareResult(
    blocks: _group(ops, a.tokens, b.tokens),
    pagesA: a.widths.length,
    pagesB: b.widths.length,
    pageWidthsA: a.widths,
    pageHeightsA: a.heights,
    pageWidthsB: b.widths,
    pageHeightsB: b.heights,
    tokensA: a.tokens.length,
    tokensB: b.tokens.length,
    scannedPagesA: a.scanned,
    scannedPagesB: b.scanned,
  );
}

void _diff(List<String> a, List<String> b, int aLo, int aHi, int bLo, int bHi,
    List<_Op> ops) {
  // Strip common prefix.
  var pa = aLo, pb = bLo;
  while (pa < aHi && pb < bHi && a[pa] == b[pb]) {
    pa++;
    pb++;
  }
  if (pa > aLo) ops.add(_Op(_Op.equal, aLo, pa, bLo, pb));

  // Strip common suffix.
  var sa = aHi, sb = bHi;
  while (sa > pa && sb > pb && a[sa - 1] == b[sb - 1]) {
    sa--;
    sb--;
  }
  final suffix = aHi - sa;

  if (pa == sa && pb == sb) {
    // nothing in the middle
  } else if (pa == sa) {
    ops.add(_Op(_Op.ins, pa, pa, pb, sb));
  } else if (pb == sb) {
    ops.add(_Op(_Op.del, pa, sa, pb, pb));
  } else {
    final anchors = _patienceAnchors(a, b, pa, sa, pb, sb);
    if (anchors.isEmpty) {
      _diffSmall(a, b, pa, sa, pb, sb, ops);
    } else {
      var ca = pa, cb = pb;
      for (final (ai, bi) in anchors) {
        _diff(a, b, ca, ai, cb, bi, ops);
        ops.add(_Op(_Op.equal, ai, ai + 1, bi, bi + 1));
        ca = ai + 1;
        cb = bi + 1;
      }
      _diff(a, b, ca, sa, cb, sb, ops);
    }
  }

  if (suffix > 0) ops.add(_Op(_Op.equal, sa, aHi, sb, bHi));
}

/// Tokens unique in BOTH ranges, kept in a longest-increasing subsequence —
/// the classic patience-diff anchor chain.
List<(int, int)> _patienceAnchors(
    List<String> a, List<String> b, int aLo, int aHi, int bLo, int bHi) {
  final countA = <String, int>{}, posA = <String, int>{};
  for (var i = aLo; i < aHi; i++) {
    countA[a[i]] = (countA[a[i]] ?? 0) + 1;
    posA[a[i]] = i;
  }
  final countB = <String, int>{}, posB = <String, int>{};
  for (var i = bLo; i < bHi; i++) {
    countB[b[i]] = (countB[b[i]] ?? 0) + 1;
    posB[b[i]] = i;
  }
  final pairs = <(int, int)>[];
  for (final e in posA.entries) {
    if (countA[e.key] == 1 && countB[e.key] == 1) {
      pairs.add((e.value, posB[e.key]!));
    }
  }
  pairs.sort((x, y) => x.$1.compareTo(y.$1));
  if (pairs.isEmpty) return const [];

  // LIS over the B positions.
  final tailIdx = <int>[]; // index into pairs of smallest tail per length
  final prev = List<int>.filled(pairs.length, -1);
  for (var i = 0; i < pairs.length; i++) {
    final v = pairs[i].$2;
    var lo = 0, hi = tailIdx.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (pairs[tailIdx[mid]].$2 < v) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo > 0) prev[i] = tailIdx[lo - 1];
    if (lo == tailIdx.length) {
      tailIdx.add(i);
    } else {
      tailIdx[lo] = i;
    }
  }
  final chain = <(int, int)>[];
  var k = tailIdx.isEmpty ? -1 : tailIdx.last;
  while (k >= 0) {
    chain.add(pairs[k]);
    k = prev[k];
  }
  return chain.reversed.toList();
}

/// Exact LCS for anchor-less gaps. Guarded by size: beyond the cap the gap
/// is reported as one wholesale change (correct, just less granular).
void _diffSmall(List<String> a, List<String> b, int aLo, int aHi, int bLo,
    int bHi, List<_Op> ops) {
  final n = aHi - aLo, m = bHi - bLo;
  if (n == 0 && m == 0) return;
  if (n * m > 4000000) {
    ops.add(_Op(_Op.del, aLo, aHi, bLo, bLo));
    ops.add(_Op(_Op.ins, aHi, aHi, bLo, bHi));
    return;
  }
  // DP LCS lengths.
  final dp = List<Uint32List>.generate(n + 1, (_) => Uint32List(m + 1));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = a[aLo + i] == b[bLo + j]
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] > dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  // Backtrack into ops (merging runs).
  var i = 0, j = 0;
  void emit(int kind, int aS, int aE, int bS, int bE) {
    if (ops.isNotEmpty) {
      final last = ops.last;
      if (last.kind == kind && last.aEnd == aS && last.bEnd == bS) {
        ops[ops.length - 1] = _Op(kind, last.aStart, aE, last.bStart, bE);
        return;
      }
    }
    ops.add(_Op(kind, aS, aE, bS, bE));
  }

  while (i < n && j < m) {
    if (a[aLo + i] == b[bLo + j]) {
      emit(_Op.equal, aLo + i, aLo + i + 1, bLo + j, bLo + j + 1);
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      emit(_Op.del, aLo + i, aLo + i + 1, bLo + j, bLo + j);
      i++;
    } else {
      emit(_Op.ins, aLo + i, aLo + i, bLo + j, bLo + j + 1);
      j++;
    }
  }
  if (i < n) emit(_Op.del, aLo + i, aLo + n, bLo + j, bLo + j);
  if (j < m) emit(_Op.ins, aLo + i, aLo + i, bLo + j, bLo + m);
}

// ---------------------------------------------------------------------------
// Grouping into readable change blocks
// ---------------------------------------------------------------------------

List<ChangeBlock> _group(
    List<_Op> ops, List<DiffToken> a, List<DiffToken> b) {
  // First pass: absorb tiny equal runs (1-2 tokens) sandwiched between
  // changes, so "thirty (30) days notice" -> "sixty (60) days notice"
  // reads as one edit instead of three fragments.
  final merged = <_Op>[];
  for (var i = 0; i < ops.length; i++) {
    final op = ops[i];
    final isTinyEqual = op.kind == _Op.equal &&
        (op.aEnd - op.aStart) <= 2 &&
        i > 0 &&
        i < ops.length - 1 &&
        merged.isNotEmpty &&
        merged.last.kind != _Op.equal &&
        ops[i + 1].kind != _Op.equal;
    if (isTinyEqual) {
      // re-tag the equal run as a paired del+ins so it joins the block
      merged.add(_Op(_Op.del, op.aStart, op.aEnd, op.bStart, op.bStart));
      merged.add(_Op(_Op.ins, op.aEnd, op.aEnd, op.bStart, op.bEnd));
    } else {
      merged.add(op);
    }
  }

  String context(List<DiffToken> tokens, int start, int end) =>
      tokens.sublist(start, end).map((t) => t.text).join(' ');

  final blocks = <ChangeBlock>[];
  var i = 0;
  while (i < merged.length) {
    if (merged[i].kind == _Op.equal) {
      i++;
      continue;
    }
    // Collect the full run of consecutive del/ins ops.
    var aS = merged[i].aStart, aE = merged[i].aEnd;
    var bS = merged[i].bStart, bE = merged[i].bEnd;
    var j = i + 1;
    while (j < merged.length && merged[j].kind != _Op.equal) {
      if (merged[j].aEnd > aE) aE = merged[j].aEnd;
      if (merged[j].bEnd > bE) bE = merged[j].bEnd;
      j++;
    }
    final before = a.sublist(aS, aE);
    final after = b.sublist(bS, bE);

    // Context from the neighbouring equal runs.
    var ctxBefore = '';
    if (i > 0 && merged[i - 1].kind == _Op.equal) {
      final e = merged[i - 1];
      final s = (e.aEnd - 4).clamp(e.aStart, e.aEnd);
      ctxBefore = context(a, s, e.aEnd);
    }
    var ctxAfter = '';
    if (j < merged.length && merged[j].kind == _Op.equal) {
      final e = merged[j];
      final s = (e.aStart + 4).clamp(e.aStart, e.aEnd);
      ctxAfter = context(a, e.aStart, s);
    }

    // Anchor pages: where the change lives in each document. For a pure
    // insertion the original page comes from the surrounding context.
    final pageA = before.isNotEmpty
        ? before.first.page
        : (aS > 0 ? a[aS - 1].page : (a.isNotEmpty ? a[0].page : 0));
    final pageB = after.isNotEmpty
        ? after.first.page
        : (bS > 0 ? b[bS - 1].page : (b.isNotEmpty ? b[0].page : 0));

    blocks.add(ChangeBlock(
      kind: before.isEmpty
          ? ChangeKind.added
          : after.isEmpty
              ? ChangeKind.removed
              : ChangeKind.changed,
      before: before,
      after: after,
      contextBefore: ctxBefore,
      contextAfter: ctxAfter,
      pageA: pageA,
      pageB: pageB,
    ));
    i = j;
  }
  return blocks;
}
