import 'dart:convert';
import 'dart:io';

import 'model.dart';
import 'pubspec_reader.dart';

/// A resolved package that declares `flutter: plugin:`.
class PluginPackage {
  PluginPackage(this.name, this.root, this.platforms);

  final String name;

  /// Absolute directory path without trailing slash.
  final String root;

  /// Declared platforms, or null when unknown (scan every folder).
  final Set<String>? platforms;

  bool declares(String platform) =>
      platforms == null || platforms!.contains(platform);
}

String _stripSlash(String p) =>
    p.length > 1 && p.endsWith('/') ? p.substring(0, p.length - 1) : p;

String _canonical(Directory d) {
  try {
    return _stripSlash(d.resolveSymbolicLinksSync());
  } on FileSystemException {
    return _stripSlash(d.absolute.path);
  }
}

/// Reads [packageConfig] (default `<appDir>/.dart_tool/package_config.json`)
/// and returns the plugin packages sorted by name.
///
/// `rootUri` values may be relative to the config file, absolute `file:` URIs
/// or percent-encoded. The app itself is never returned.
List<PluginPackage> resolvePlugins(String appDir, {String? packageConfig}) {
  final configPath = packageConfig ?? '$appDir/.dart_tool/package_config.json';
  final configFile = File(configPath);
  if (!configFile.existsSync()) {
    throw PluginFloorException('error.noPackageConfig', {'path': configPath});
  }
  final Object? json;
  try {
    json = jsonDecode(
      utf8.decode(configFile.readAsBytesSync(), allowMalformed: true),
    );
  } on FormatException catch (e) {
    throw PluginFloorException('error.badPackageConfig', {
      'path': configPath,
      'detail': e.message,
    });
  }
  if (json is! Map || json['packages'] is! List) {
    throw PluginFloorException('error.badPackageConfig', {
      'path': configPath,
      'detail': 'missing "packages" list',
    });
  }
  final configUri = configFile.absolute.uri;
  final appRoot = _canonical(Directory(appDir));
  final plugins = <PluginPackage>[];
  for (final entry in json['packages'] as List) {
    if (entry is! Map ||
        entry['name'] is! String ||
        entry['rootUri'] is! String) {
      continue;
    }
    final Uri uri;
    try {
      uri = configUri.resolve(entry['rootUri'] as String);
    } on FormatException {
      continue;
    }
    if (uri.scheme != 'file') continue;
    final dir = Directory.fromUri(uri);
    if (!dir.existsSync()) continue;
    final root = _canonical(dir);
    if (root == appRoot) continue;
    final pubspec = File('$root/pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    final info = readPluginInfo(
      utf8.decode(pubspec.readAsBytesSync(), allowMalformed: true),
    );
    if (info == null) continue;
    plugins.add(PluginPackage(entry['name'] as String, root, info.platforms));
  }
  plugins.sort((a, b) => a.name.compareTo(b.name));
  return plugins;
}

final RegExp _sdkMinSdk = RegExp(
  r'\bval\s+minSdkVersion\s*:\s*Int\s*=\s*(\d+)\b',
);
final RegExp _sdkCompileSdk = RegExp(
  r'\bval\s+compileSdkVersion\s*:\s*Int\s*=\s*(\d+)\b',
);

/// Reads the `flutter.minSdkVersion` and `flutter.compileSdkVersion` defaults
/// from the Flutter SDK that the app's `package_config.json` points to.
///
/// The SDK root is `<rootUri of package "flutter">/../..`. Only two integer
/// literals of `FlutterExtension.kt` are read (no build, no process, no
/// network). Anything missing or in an unexpected format is left out of the
/// result, so those names stay unresolved. Never throws.
Map<String, String> readFlutterSdkDefaults(
  String appDir, {
  String? packageConfig,
}) {
  try {
    final configFile = File(
      packageConfig ?? '$appDir/.dart_tool/package_config.json',
    );
    if (!configFile.existsSync()) return const {};
    final json = jsonDecode(
      utf8.decode(configFile.readAsBytesSync(), allowMalformed: true),
    );
    if (json is! Map || json['packages'] is! List) return const {};
    final configUri = configFile.absolute.uri;
    for (final entry in json['packages'] as List) {
      if (entry is! Map ||
          entry['name'] != 'flutter' ||
          entry['rootUri'] is! String) {
        continue;
      }
      final uri = configUri.resolve(entry['rootUri'] as String);
      if (uri.scheme != 'file') return const {};
      final flutterDir = Directory.fromUri(uri);
      if (!flutterDir.existsSync()) return const {};
      final sdkRoot = _canonical(Directory('${_canonical(flutterDir)}/../..'));
      final kt = File(
        '$sdkRoot/packages/flutter_tools/gradle/src/main/kotlin/'
        'FlutterExtension.kt',
      );
      if (!kt.existsSync()) return const {};
      final text = utf8.decode(kt.readAsBytesSync(), allowMalformed: true);
      final out = <String, String>{};
      final min = _sdkMinSdk.firstMatch(text);
      if (min != null) out['flutter.minSdkVersion'] = min.group(1)!;
      final compile = _sdkCompileSdk.firstMatch(text);
      if (compile != null) out['flutter.compileSdkVersion'] = compile.group(1)!;
      return out;
    }
  } on Object {
    return const {};
  }
  return const {};
}
