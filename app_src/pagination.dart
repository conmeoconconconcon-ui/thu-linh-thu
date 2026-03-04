import 'package:flutter/material.dart';
import 'package:html_unescape/html_unescape.dart';

final _unescape = HtmlUnescape();

String htmlToPlainText(String html) {
  final noScript = html
      .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '');

  String s = noScript
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'</div\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</h[1-6]\s*>', caseSensitive: false), '\n\n');

  s = s.replaceAll(RegExp(r'<[^>]+>'), ' ');
  s = _unescape.convert(s);

  s = s
      .replaceAll('\u00A0', ' ')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n[ \t]+'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  return s;
}

List<String> paginateText({
  required String fullText,
  required TextStyle style,
  required Size pageSize,
  required EdgeInsets padding,
}) {
  final maxWidth = pageSize.width - padding.left - padding.right;
  final maxHeight = pageSize.height - padding.top - padding.bottom;

  if (maxWidth <= 50 || maxHeight <= 50) return [fullText];

  final pages = <String>[];
  int start = 0;

  while (start < fullText.length) {
    int low = start + 1;
    int high = fullText.length;
    int best = low;

    while (low <= high) {
      final mid = (low + high) >> 1;
      final chunk = fullText.substring(start, mid);

      final tp = TextPainter(
        text: TextSpan(text: chunk, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth);

      if (tp.height <= maxHeight) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    int cut = best;
    final back = (cut - start) > 200 ? 200 : (cut - start);
    for (int i = 0; i < back; i++) {
      final idx = cut - i - 1;
      if (idx <= start) break;
      final ch = fullText[idx];
      if (ch == '\n' || ch == ' ') {
        cut = idx + 1;
        break;
      }
    }

    final page = fullText.substring(start, cut).trimRight();
    if (page.isNotEmpty) pages.add(page);
    start = cut;
  }

  return pages.isEmpty ? [fullText] : pages;
}
