import 'model.dart';
import 'text_utils.dart';
import 'version.dart';

/// Reads a file referenced by `apply from:`; returns null when it cannot be
/// read. `displayPath` is the path shown in reports.
typedef ApplyReader = ({String text, String displayPath})? Function(String ref);

final RegExp _declaration = RegExp(
  r'(?:^|[{;])[ \t]*(minSdkVersion|minSdk|compileSdkVersion|compileSdk)(?![\w.])'
  r'[ \t]*(=|\()?[ \t]*([^\r\n]*)',
  multiLine: true,
);

final RegExp _strictDef = RegExp(
  r'^[ \t]*(?:(?:def|val|var|final|int)[ \t]+|(?:project\.)?ext\.)'
  r'([A-Za-z_]\w*)[ \t]*=[ \t]*(\d+)[ \t]*;?[ \t]*$',
  multiLine: true,
);

final RegExp _looseDef = RegExp(
  r'^[ \t]*([A-Za-z_]\w*)[ \t]*(?:=[ \t]*)?(\d+)[ \t]*;?[ \t]*$',
  multiLine: true,
);

final RegExp _applyFrom = RegExp(
  r'apply[ \t]*(?:\([ \t]*)?from[ \t]*[:=][ \t]*(?:file[ \t]*\([ \t]*)?'
  r'[\x22\x27]([^\x22\x27$]+)[\x22\x27]',
);

final RegExp _chain = RegExp(r'^[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*$');

class _Def {
  _Def(this.value, this.file, this.line);
  final String value;
  final String file;
  final int line;
}

Map<String, _Def> _definitions(
  String stripped,
  String file, {
  required bool loose,
}) {
  final defs = <String, _Def>{};
  for (final m in _strictDef.allMatches(stripped)) {
    defs.putIfAbsent(m[1]!, () => _Def(m[2]!, file, lineOf(stripped, m.start)));
  }
  if (loose) {
    for (final m in _looseDef.allMatches(stripped)) {
      defs.putIfAbsent(
        m[1]!,
        () => _Def(m[2]!, file, lineOf(stripped, m.start)),
      );
    }
  }
  return defs;
}

Target _targetOf(String name) =>
    name.startsWith('minSdk') ? Target.androidMinSdk : Target.androidCompileSdk;

/// Extracts `minSdk` / `compileSdk` declarations from a Groovy or Kotlin DSL
/// Gradle file.
///
/// One `apply from:` hop is followed through [readApply]: `ext` values such as
/// `ext { minSdk = 23 }` resolve names like `project.ext.minSdk`. `flutter.*`
/// and `rootProject.*` expressions stay unresolved.
List<Finding> parseGradle(
  String text, {
  required String file,
  String? package,
  Source source = Source.gradle,
  ApplyReader? readApply,
}) {
  final s = stripComments(text, slash: true);
  final defs = _definitions(s, file, loose: false);
  if (readApply != null) {
    for (final m in _applyFrom.allMatches(s)) {
      final other = readApply(m[1]!);
      if (other == null) continue;
      final stripped = stripComments(other.text, slash: true);
      final hop = _definitions(stripped, other.displayPath, loose: true);
      hop.forEach((k, v) => defs.putIfAbsent(k, () => v));
    }
  }
  final out = <Finding>[];
  for (final m in _declaration.allMatches(s)) {
    final target = _targetOf(m[1]!);
    var expr = m[3]!.split(RegExp(r'[};]')).first.trim();
    if (m[2] == '(') {
      final close = expr.lastIndexOf(')');
      if (close >= 0) expr = expr.substring(0, close);
    }
    expr = expr.replaceAll(RegExp(r';\s*$'), '').trim();
    if (expr.isEmpty) continue;
    final line = lineOf(s, m.start);
    Finding unresolved(String reason) => Finding(
      package: package,
      target: target,
      source: source,
      expr: expr,
      file: file,
      line: line,
      reason: reason,
    );
    if (Version.isLiteral(expr) && !expr.contains('.')) {
      out.add(
        Finding(
          package: package,
          target: target,
          source: source,
          expr: expr,
          value: expr,
          file: file,
          line: line,
        ),
      );
      continue;
    }
    if (!_chain.hasMatch(expr)) {
      out.add(unresolved('expression'));
      continue;
    }
    if (expr.startsWith('flutter.')) {
      out.add(unresolved('flutter'));
      continue;
    }
    if (expr.startsWith('rootProject.')) {
      out.add(unresolved('rootProject'));
      continue;
    }
    var name = expr;
    for (final prefix in const ['project.ext.', 'ext.']) {
      if (name.startsWith(prefix)) {
        name = name.substring(prefix.length);
        break;
      }
    }
    final def = name.contains('.') ? null : defs[name];
    if (def == null) {
      out.add(unresolved(name.contains('.') ? 'expression' : 'ext'));
      continue;
    }
    out.add(
      Finding(
        package: package,
        target: target,
        source: source,
        expr: expr,
        value: def.value,
        file: def.file,
        line: def.line,
        viaFile: file,
        viaLine: line,
      ),
    );
  }
  return out;
}

final RegExp _manifestMin = RegExp(
  r'android:minSdkVersion[ \t]*=[ \t]*"([^"]*)"',
);

/// Extracts `<uses-sdk android:minSdkVersion>` from an AndroidManifest.xml.
List<Finding> parseManifest(
  String text, {
  required String file,
  String? package,
}) {
  final s = stripComments(text, xml: true);
  final out = <Finding>[];
  for (final m in _manifestMin.allMatches(s)) {
    final v = m[1]!.trim();
    final literal = Version.isLiteral(v) && !v.contains('.');
    out.add(
      Finding(
        package: package,
        target: Target.androidMinSdk,
        source: Source.manifest,
        expr: v,
        value: literal ? v : null,
        reason: literal ? null : 'expression',
        file: file,
        line: lineOf(s, m.start),
      ),
    );
  }
  return out;
}
