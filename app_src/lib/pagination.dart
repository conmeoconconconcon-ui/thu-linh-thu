String htmlToPlainText(String html) {
  // dọn mấy tag cơ bản (đủ dùng, không hoàn hảo nhưng ổn)
  var s = html;

  // bỏ script/style
  s = s.replaceAll(RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false), '');

  // xuống dòng khi gặp các thẻ block
  s = s.replaceAll(RegExp(r'</(p|div|h1|h2|h3|h4|li|br|tr)>', caseSensitive: false), '\n');

  // bỏ tag
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');

  // decode HTML entities đơn giản
  s = s.replaceAll('&nbsp;', ' ');
  s = s.replaceAll('&amp;', '&');
  s = s.replaceAll('&lt;', '<');
  s = s.replaceAll('&gt;', '>');
  s = s.replaceAll('&quot;', '"');
  s = s.replaceAll('&#39;', "'");

  // gộp khoảng trắng
  s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');

  return s.trim();
}

List<String> paginateText(
  String text, {
  int maxCharsPerPage = 1800,
}) {
  // chia theo đoạn, gộp cho vừa 1 trang
  final paras = text.split(RegExp(r'\n\s*\n'));
  final pages = <String>[];

  final buf = StringBuffer();
  int len = 0;

  void flush() {
    final t = buf.toString().trim();
    if (t.isNotEmpty) pages.add(t);
    buf.clear();
    len = 0;
  }

  for (final p in paras) {
    final para = p.trim();
    if (para.isEmpty) continue;

    // nếu đoạn quá dài -> cắt thô
    if (para.length > maxCharsPerPage) {
      if (len > 0) flush();
      int start = 0;
      while (start < para.length) {
        final end = (start + maxCharsPerPage).clamp(0, para.length);
        pages.add(para.substring(start, end).trim());
        start = end;
      }
      continue;
    }

    final addLen = para.length + 2;
    if (len + addLen > maxCharsPerPage) flush();

    buf.writeln(para);
    buf.writeln();
    len += addLen;
  }

  if (len > 0) flush();

  return pages.isEmpty ? ["(Không có nội dung)"] : pages;
}
