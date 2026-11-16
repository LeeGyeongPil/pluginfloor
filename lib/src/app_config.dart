import 'dart:convert';
import 'dart:io';

import 'android_parser.dart';
import 'model.dart';
import 'text_utils.dart';
import 'version.dart';

/// Values declared by the app itself.
class AppConfig {
  AppConfig({
    required this.findings,
    required this.platforms,
    required this.localProperties,
  });

  /// At most one finding per [Target].
  final List<Finding> findings;

  /// Platform folders that exist: `android`, `ios`, `macos`.
  final Set<String> platforms;

  /// Parsed `android/local.properties`.
  final Map<String, String> localProperties;

  Finding? of(Target t) {
    for (final f in findings) {
      if (f.target == t) return f;
    }
    return null;
  }
}

String _read(File f) => utf8.decode(f.readAsBytesSync(), allowMalformed: true);

/// Parses `key=value` lines (comments start with `#` or `!`).
Map<String, String> parseProperties(String text) {
  final out = <String, String>{};
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('!')) continue;
    final i = line.indexOf('=');
    if (i <= 0) continue;
    out[line.substring(0, i).trim()] = line.substring(i + 1).trim();
  }
  return out;
}

final RegExp _podfilePlatform = RegExp(
  r'^[ \t]*platform[ \t]*:(ios|osx)[ \t]*,[ \t]*[\x22\x27]([\d.]+)[\x22\x27]',
  multiLine: true,
);

Finding? _podfile(String appDir, String folder, String podPlatform, Target t) {
  final f = File('$appDir/$folder/Podfile');
  if (!f.existsSync()) return null;
  final s = stripComments(_read(f), hash: true);
  for (final m in _podfilePlatform.allMatches(s)) {
    if (m[1] == podPlatform) {
      return Finding(
        target: t,
        source: Source.app,
        expr: m[2]!,
        value: m[2],
        file: '$folder/Podfile',
        line: lineOf(s, m.start),
      );
    }
  }
  return null;
}

/// Lowest deployment target across all build configurations in a pbxproj.
Finding? _pbxproj(String appDir, String folder, String key, Target t) {
  final f = File('$appDir/$folder/Runner.xcodeproj/project.pbxproj');
  if (!f.existsSync()) return null;
  final text = _read(f);
  final re = RegExp('$key[ \\t]*=[ \\t]*([\\d.]+)[ \\t]*;');
  Finding? best;
  for (final m in re.allMatches(text)) {
    final v = Version.tryParse(m[1]!);
    if (v == null) continue;
    if (best == null || v < best.version!) {
      best = Finding(
        target: t,
        source: Source.app,
        expr: m[1]!,
        value: m[1],
        file: '$folder/Runner.xcodeproj/project.pbxproj',
        line: lineOf(text, m.start),
      );
    }
  }
  return best;
}

/// Reads the app's own minSdk, compileSdk and deployment targets.
///
/// iOS and macOS use `Podfile` `platform` first and fall back to the lowest
/// deployment target in `Runner.xcodeproj/project.pbxproj`.
AppConfig readAppConfig(String appDir) {
  final platforms = <String>{
    for (final p in const ['android', 'ios', 'macos'])
      if (Directory('$appDir/$p').existsSync()) p,
  };
  final findings = <Finding>[];
  var props = <String, String>{};

  if (platforms.contains('android')) {
    final lp = File('$appDir/android/local.properties');
    if (lp.existsSync()) props = parseProperties(_read(lp));
    for (final name in const ['build.gradle.kts', 'build.gradle']) {
      final f = File('$appDir/android/app/$name');
      if (!f.existsSync()) continue;
      final parsed = parseGradle(
        _read(f),
        file: 'android/app/$name',
        readApply: (ref) {
          final path = joinInside('$appDir/android/app', ref);
          if (path == null || !File(path).existsSync()) return null;
          return (
            text: _read(File(path)),
            displayPath: path.substring(appDir.length + 1),
          );
        },
      );
      for (final t in const [Target.androidMinSdk, Target.androidCompileSdk]) {
        for (final p in parsed) {
          if (p.target == t) {
            findings.add(p);
            break;
          }
        }
      }
      break;
    }
  }
  if (platforms.contains('ios')) {
    final f =
        _podfile(appDir, 'ios', 'ios', Target.iosDeployment) ??
        _pbxproj(
          appDir,
          'ios',
          'IPHONEOS_DEPLOYMENT_TARGET',
          Target.iosDeployment,
        );
    if (f != null) findings.add(f);
  }
  if (platforms.contains('macos')) {
    final f =
        _podfile(appDir, 'macos', 'osx', Target.macosDeployment) ??
        _pbxproj(
          appDir,
          'macos',
          'MACOSX_DEPLOYMENT_TARGET',
          Target.macosDeployment,
        );
    if (f != null) findings.add(f);
  }
  return AppConfig(
    findings: findings,
    platforms: platforms,
    localProperties: props,
  );
}
