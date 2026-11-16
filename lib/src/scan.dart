import 'dart:convert';
import 'dart:io';

import 'android_parser.dart';
import 'app_config.dart';
import 'apple_parser.dart';
import 'compare.dart';
import 'model.dart';
import 'package_resolver.dart';
import 'text_utils.dart';

/// Inputs of [scanApp].
class AppScanOptions {
  AppScanOptions({
    required this.appDir,
    this.packageConfig,
    this.assume = const {},
    this.darwinPath = DarwinPath.both,
  });

  /// Flutter app directory (the one that contains `.dart_tool/`).
  final String appDir;

  /// Explicit path to `package_config.json`.
  final String? packageConfig;

  /// Values for names that cannot be resolved statically.
  final Map<String, String> assume;
  final DarwinPath darwinPath;
}

String _read(File f) => utf8.decode(f.readAsBytesSync(), allowMalformed: true);

const _skipDirs = {'example', 'build', 'Pods', '.symlinks', '.build', '.git'};

void _walk(Directory dir, int depth, List<File> out) {
  final entries = dir.listSync(followLinks: false)
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final e in entries) {
    final segs = e.uri.pathSegments.where((s) => s.isNotEmpty);
    final name = segs.isEmpty ? '' : segs.last;
    if (e is Directory) {
      if (depth < 3 && !_skipDirs.contains(name)) _walk(e, depth + 1, out);
    } else if (e is File &&
        (name.endsWith('.podspec') || name == 'Package.swift')) {
      out.add(e);
    }
  }
}

/// Collects every floor declared by one plugin.
List<Finding> collectPluginFindings(PluginPackage p) {
  final out = <Finding>[];
  String display(String absolute) =>
      '${p.name}/${absolute.substring(p.root.length + 1)}';

  if (p.declares('android')) {
    final androidDir = '${p.root}/android';
    for (final name in const ['build.gradle', 'build.gradle.kts']) {
      final f = File('$androidDir/$name');
      if (!f.existsSync()) continue;
      out.addAll(
        parseGradle(
          _read(f),
          file: display(f.path),
          package: p.name,
          readApply: (ref) {
            final path = joinInside(androidDir, ref);
            if (path == null || !File(path).existsSync()) return null;
            return (text: _read(File(path)), displayPath: display(path));
          },
        ),
      );
    }
    final manifest = File('$androidDir/src/main/AndroidManifest.xml');
    if (manifest.existsSync()) {
      out.addAll(
        parseManifest(
          _read(manifest),
          file: display(manifest.path),
          package: p.name,
        ),
      );
    }
  }

  final wantsIos = p.declares('ios');
  final wantsMacos = p.declares('macos');
  for (final folder in const ['ios', 'macos', 'darwin']) {
    final dir = Directory('${p.root}/$folder');
    if (!dir.existsSync()) continue;
    if (folder == 'ios' && !wantsIos) continue;
    if (folder == 'macos' && !wantsMacos) continue;
    if (folder == 'darwin' && !wantsIos && !wantsMacos) continue;
    final files = <File>[];
    _walk(dir, 0, files);
    for (final f in files) {
      final shown = display(f.path);
      final parsed = f.path.endsWith('.podspec')
          ? parsePodspec(_read(f), file: shown, folder: folder, package: p.name)
          : parsePackageSwift(_read(f), file: shown, package: p.name);
      for (final finding in parsed) {
        final wanted = finding.target == Target.iosDeployment
            ? wantsIos
            : wantsMacos;
        if (wanted) out.add(finding);
      }
    }
  }
  return out;
}

/// Scans the app and returns the comparison report.
///
/// Throws [PluginFloorException] for input problems (missing or malformed
/// `package_config.json`, missing app directory).
ScanReport scanApp(AppScanOptions options) {
  if (!Directory(options.appDir).existsSync()) {
    throw PluginFloorException('error.noAppDir', {'path': options.appDir});
  }
  final plugins = resolvePlugins(
    options.appDir,
    packageConfig: options.packageConfig,
  );
  final findings = [for (final p in plugins) ...collectPluginFindings(p)];
  return compare(
    pluginNames: [for (final p in plugins) p.name],
    pluginFindings: findings,
    app: readAppConfig(options.appDir),
    assume: options.assume,
    darwinPath: options.darwinPath,
  );
}
