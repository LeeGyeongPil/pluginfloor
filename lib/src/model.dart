import 'i18n/messages.dart';
import 'version.dart';

/// Thrown for usage and input problems; the CLI maps it to exit code 2.
///
/// [key] is a message key (see `i18n/messages.dart`) so the CLI can print the
/// text in the selected language; [message] is always the English text.
class PluginFloorException implements Exception {
  PluginFloorException(this.key, [this.args = const {}]);

  final String key;
  final Map<String, String> args;

  /// English text.
  String get message => Messages.en.text(key, args);

  @override
  String toString() => 'PluginFloorException: $message';
}

/// One floor the scanner can compare.
enum Target {
  androidMinSdk('android', 'minSdk', 'PF001'),
  androidCompileSdk('android', 'compileSdk', 'PF002'),
  iosDeployment('ios', 'deploymentTarget', 'PF003'),
  macosDeployment('macos', 'deploymentTarget', 'PF004');

  const Target(this.platform, this.kind, this.ruleId);

  /// `android`, `ios` or `macos`.
  final String platform;

  /// `minSdk`, `compileSdk` or `deploymentTarget`.
  final String kind;

  /// Rule raised when the app value is below the plugin requirement.
  final String ruleId;

  /// Stable identifier such as `android.minSdk`.
  String get id => '$platform.$kind';
}

/// Where a value was read from.
enum Source { gradle, manifest, podspec, spm, app }

/// One declared value with its location.
class Finding {
  Finding({
    required this.target,
    required this.source,
    required this.expr,
    required this.file,
    required this.line,
    this.package,
    this.value,
    this.reason,
    this.viaFile,
    this.viaLine,
    this.assumed = false,
  });

  /// Plugin name, or null for app-side values.
  final String? package;
  final Target target;
  final Source source;

  /// Raw expression text (`24`, `flutter.minSdkVersion`, ...).
  final String expr;

  /// Normalized numeric value, or null when it cannot be resolved statically.
  final String? value;

  /// Why [value] is null: `flutter`, `rootProject`, `expression`, `ext`.
  final String? reason;

  /// App-relative (app side) or `<package>/<path>` (plugin side), 1-based line.
  final String file;
  final int line;

  /// When the value came from an `ext` hop, the declaring gradle location.
  final String? viaFile;
  final int? viaLine;

  /// True when [value] was filled in by `--assume` or `local.properties`.
  final bool assumed;

  bool get resolved => value != null;

  Version? get version => value == null ? null : Version.tryParse(value!);

  Finding copyWith({String? value, bool? assumed}) => Finding(
    package: package,
    target: target,
    source: source,
    expr: expr,
    file: file,
    line: line,
    value: value ?? this.value,
    reason: value != null ? null : reason,
    viaFile: viaFile,
    viaLine: viaLine,
    assumed: assumed ?? this.assumed,
  );
}

/// A rule hit.
class Violation {
  Violation({
    required this.ruleId,
    required this.severity,
    required this.messageKey,
    required this.fixKey,
    required this.args,
    this.target,
    this.package,
    this.file,
    this.line,
    this.appFile,
    this.appLine,
    this.required,
    this.appValue,
  });

  /// `PF001` ... `PF012`.
  final String ruleId;

  /// `error`, `warning` or `note`.
  final String severity;
  final String messageKey;
  final String? fixKey;
  final Map<String, String> args;
  final Target? target;
  final String? package;

  /// Plugin-side location that raises the floor (or holds the unresolved value).
  final String? file;
  final int? line;

  /// App-side location where the value is declared.
  final String? appFile;
  final int? appLine;
  final String? required;
  final String? appValue;
}

/// Highest floor per target compared with the app value.
class TargetSummary {
  TargetSummary({required this.target, this.app, this.highest});

  final Target target;
  final Finding? app;
  final Finding? highest;
}

/// Result of [scanApp].
class ScanReport {
  ScanReport({
    required this.pluginNames,
    required this.findings,
    required this.appFindings,
    required this.summaries,
    required this.violations,
    required this.unresolved,
    required this.benign,
  });

  /// Sorted plugin package names.
  final List<String> pluginNames;

  /// Plugin-side values (after `--assume` substitution).
  final List<Finding> findings;

  /// App-side values.
  final List<Finding> appFindings;
  final List<TargetSummary> summaries;
  final List<Violation> violations;

  /// Values that could not be resolved statically (plugin and app side).
  final List<Finding> unresolved;

  /// Unresolved plugin values that use the same expression as the app, so
  /// they cannot exceed it (not reported as PF010).
  final Set<Finding> benign;

  int count(String severity) =>
      violations.where((v) => v.severity == severity).length;

  /// Exit code: 1 on errors, or on warnings when [strict] is set; else 0.
  int exitCode({bool strict = false}) {
    if (count('error') > 0) return 1;
    if (strict && count('warning') > 0) return 1;
    return 0;
  }
}
