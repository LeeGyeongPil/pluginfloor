import 'model.dart';
import 'text_utils.dart';
import 'version.dart';

Target _target(String platform) =>
    platform == 'ios' ? Target.iosDeployment : Target.macosDeployment;

/// Drops later findings that repeat the same platform, source and value.
List<Finding> _merge(List<Finding> all) {
  final seen = <String>{};
  final out = <Finding>[];
  for (final f in all) {
    if (seen.add('${f.target.id}|${f.source.name}|${f.expr}')) out.add(f);
  }
  return out;
}

final RegExp _podDeploy = RegExp(
  r'\.(?:(ios|osx|macos|tvos|watchos|visionos)\.)?deployment_target'
  r'[ \t]*=[ \t]*([^\r\n]*)',
);
final RegExp _podPlatform = RegExp(
  r'\.platform[ \t]*=[ \t]*:(ios|osx|macos)'
  r'(?:[ \t]*,[ \t]*[\x22\x27]([\d.]+)[\x22\x27])?',
);
final RegExp _podPlatformsHash = RegExp(
  r'(?::(ios|osx|macos)[ \t]*=>|\b(ios|osx|macos):)[ \t]*[\x22\x27]([\d.]+)[\x22\x27]',
);
final RegExp _quoted = RegExp(r'^[\x22\x27]([\d.]+)[\x22\x27]');

/// Parses a `.podspec` for iOS and macOS deployment targets.
///
/// [folder] is `ios`, `macos` or `darwin`: a `deployment_target` without a
/// platform applies to the folder's platform (both platforms for `darwin`).
/// `s.platform = :ios` without a version is ignored. Repeated identical
/// values (for example `platform` plus `ios.deployment_target`) are merged.
List<Finding> parsePodspec(
  String text, {
  required String file,
  required String folder,
  String? package,
}) {
  final s = stripComments(text, hash: true);
  final raw = <({int offset, String platform, String? value, String expr})>[];
  String norm(String p) => p == 'osx' ? 'macos' : p;

  for (final m in _podDeploy.allMatches(s)) {
    final plat = m[1];
    if (plat == 'tvos' || plat == 'watchos' || plat == 'visionos') continue;
    final rest = m[2]!.trim();
    final q = _quoted.firstMatch(rest);
    final value = q?[1];
    final expr = q != null ? q[1]! : rest;
    final platforms = plat != null
        ? [norm(plat)]
        : folder == 'darwin'
        ? ['ios', 'macos']
        : [folder];
    for (final p in platforms) {
      raw.add((offset: m.start, platform: p, value: value, expr: expr));
    }
  }
  for (final m in _podPlatform.allMatches(s)) {
    if (m[2] == null) continue;
    raw.add((offset: m.start, platform: norm(m[1]!), value: m[2], expr: m[2]!));
  }
  for (final m in _podPlatformsHash.allMatches(s)) {
    raw.add((
      offset: m.start,
      platform: norm((m[1] ?? m[2])!),
      value: m[3],
      expr: m[3]!,
    ));
  }
  raw.sort((a, b) => a.offset.compareTo(b.offset));
  return _merge([
    for (final r in raw)
      Finding(
        package: package,
        target: _target(r.platform),
        source: Source.podspec,
        expr: r.expr,
        value: r.value != null && Version.isLiteral(r.value!) ? r.value : null,
        reason: r.value != null && Version.isLiteral(r.value!)
            ? null
            : 'expression',
        file: file,
        line: lineOf(s, r.offset),
      ),
  ]);
}

final RegExp _platformsOpen = RegExp(r'platforms[ \t\r\n]*:[ \t\r\n]*\[');
final RegExp _spmEntry = RegExp(r'\.(iOS|macOS)[ \t\r\n]*\(([^)]*)\)');
final RegExp _spmEnum = RegExp(r'^\.v(\d+)(?:_(\d+))?$');
final RegExp _spmQuoted = RegExp(r'^"([\d.]+)"$');

/// Parses the `platforms: [...]` array of a `Package.swift`:
/// `.iOS("13.0")`, `.iOS(.v13)`, `.iOS(.v15_5)`, `.macOS(.v10_15)`.
///
/// The array may start hundreds of lines into the file.
List<Finding> parsePackageSwift(
  String text, {
  required String file,
  String? package,
}) {
  final s = stripComments(text, slash: true);
  final out = <Finding>[];
  for (final open in _platformsOpen.allMatches(s)) {
    var depth = 1;
    var i = open.end;
    while (i < s.length && depth > 0) {
      final c = s[i];
      if (c == '[') depth++;
      if (c == ']') depth--;
      i++;
    }
    final block = s.substring(open.end, i);
    for (final m in _spmEntry.allMatches(block)) {
      final platform = m[1]!.toLowerCase();
      final inner = m[2]!.trim();
      String? value;
      final quoted = _spmQuoted.firstMatch(inner);
      if (quoted != null && Version.isLiteral(quoted[1]!)) {
        value = quoted[1];
      } else {
        final e = _spmEnum.firstMatch(inner);
        if (e != null) value = e[2] == null ? e[1] : '${e[1]}.${e[2]}';
      }
      out.add(
        Finding(
          package: package,
          target: _target(platform),
          source: Source.spm,
          expr: value ?? inner,
          value: value,
          reason: value == null ? 'expression' : null,
          file: file,
          line: lineOf(s, open.end + m.start),
        ),
      );
    }
  }
  return _merge(out);
}
