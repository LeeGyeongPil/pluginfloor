/// Small text helpers shared by the parsers.
///
/// Comment stripping replaces comment characters with spaces but keeps every
/// newline, so offsets and line numbers of the remaining text stay valid.
library;

/// Blanks out comments in [text] while keeping its length and newlines.
///
/// * [slash]: `// ...` (not after `:` so URLs survive) and `/* ... */`.
/// * [hash]: `# ...` when the `#` starts the line or follows whitespace.
/// * [xml]: `<!-- ... -->`.
String stripComments(
  String text, {
  bool slash = false,
  bool hash = false,
  bool xml = false,
}) {
  final out = StringBuffer();
  var i = 0;
  final n = text.length;
  void blank(int from, int to) {
    for (var k = from; k < to; k++) {
      out.write(text[k] == '\n' || text[k] == '\r' ? text[k] : ' ');
    }
  }

  int endOfLine(int from) {
    var j = from;
    while (j < n && text[j] != '\n' && text[j] != '\r') {
      j++;
    }
    return j;
  }

  while (i < n) {
    final c = text[i];
    if (slash && c == '/' && i + 1 < n && text[i + 1] == '/') {
      if (i > 0 && text[i - 1] == ':') {
        out.write(c);
        i++;
        continue;
      }
      final j = endOfLine(i);
      blank(i, j);
      i = j;
    } else if (slash && c == '/' && i + 1 < n && text[i + 1] == '*') {
      final end = text.indexOf('*/', i + 2);
      final j = end < 0 ? n : end + 2;
      blank(i, j);
      i = j;
    } else if (hash &&
        c == '#' &&
        (i == 0 ||
            text[i - 1] == '\n' ||
            text[i - 1] == ' ' ||
            text[i - 1] == '\t')) {
      final j = endOfLine(i);
      blank(i, j);
      i = j;
    } else if (xml && text.startsWith('<!--', i)) {
      final end = text.indexOf('-->', i + 4);
      final j = end < 0 ? n : end + 3;
      blank(i, j);
      i = j;
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

/// 1-based line number of [offset] in [text].
int lineOf(String text, int offset) {
  var line = 1;
  final end = offset < text.length ? offset : text.length;
  for (var i = 0; i < end; i++) {
    if (text.codeUnitAt(i) == 10) line++;
  }
  return line;
}

/// Joins [rel] onto [base] (both `/` separated) and returns null when the
/// result would leave [base] or when [rel] is absolute.
String? joinInside(String base, String rel) {
  if (rel.startsWith('/') || rel.contains('\\')) return null;
  final parts = <String>[];
  for (final seg in rel.split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      if (parts.isEmpty) return null;
      parts.removeLast();
    } else {
      parts.add(seg);
    }
  }
  if (parts.isEmpty) return null;
  final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  return '$b/${parts.join('/')}';
}
