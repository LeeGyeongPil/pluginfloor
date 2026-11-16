/// Dotted numeric version such as `21`, `10.15` or `15.5.1`.
///
/// Comparison pads the shorter list with zeros, so `15 == 15.0` and
/// `10.15 > 10.9` (components are integers, not decimals).
class Version implements Comparable<Version> {
  Version._(this.parts, this.text);

  /// Integer components.
  final List<int> parts;

  /// The original text.
  final String text;

  static final RegExp _literal = RegExp(r'^\d+(?:\.\d+)*$');

  /// Whether [text] is a plain dotted numeric literal.
  static bool isLiteral(String text) => _literal.hasMatch(text.trim());

  /// Parses [text], returning null when it is not a numeric literal.
  static Version? tryParse(String text) {
    final t = text.trim();
    if (!_literal.hasMatch(t)) return null;
    return Version._([for (final p in t.split('.')) int.parse(p)], t);
  }

  @override
  int compareTo(Version other) {
    final n = parts.length > other.parts.length
        ? parts.length
        : other.parts.length;
    for (var i = 0; i < n; i++) {
      final a = i < parts.length ? parts[i] : 0;
      final b = i < other.parts.length ? other.parts[i] : 0;
      if (a != b) return a < b ? -1 : 1;
    }
    return 0;
  }

  bool operator <(Version other) => compareTo(other) < 0;
  bool operator >(Version other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) => other is Version && compareTo(other) == 0;

  @override
  int get hashCode {
    var end = parts.length;
    while (end > 1 && parts[end - 1] == 0) {
      end--;
    }
    return Object.hashAll(parts.sublist(0, end));
  }

  @override
  String toString() => text;
}
