import 'package:yaml/yaml.dart';

/// What a plugin's `pubspec.yaml` says about itself.
class PluginInfo {
  PluginInfo(this.platforms);

  /// Platforms listed under `flutter.plugin.platforms` (`android`, `ios`,
  /// `macos`, ...), or null when the pubspec does not list any (older
  /// pubspec style or an app-facing package) - then every folder is scanned.
  final Set<String>? platforms;
}

/// Returns plugin info when [pubspecText] declares `flutter: plugin:`, else
/// null. Unparseable YAML counts as "not a plugin".
PluginInfo? readPluginInfo(String pubspecText) {
  final Object? doc;
  try {
    doc = loadYaml(pubspecText);
  } on YamlException {
    return null;
  }
  if (doc is! YamlMap) return null;
  final flutter = doc['flutter'];
  if (flutter is! YamlMap) return null;
  final plugin = flutter['plugin'];
  if (plugin is! YamlMap) return null;
  final platforms = plugin['platforms'];
  if (platforms is YamlMap) {
    return PluginInfo({for (final k in platforms.keys) k.toString()});
  }
  return PluginInfo(null);
}
