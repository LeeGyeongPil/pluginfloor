import 'app_config.dart';
import 'model.dart';
import 'version.dart';

/// Which Apple build path decides the iOS/macOS floor.
enum DarwinPath {
  /// Only `*.podspec` values.
  cocoapods,

  /// Only `Package.swift` values.
  spm,

  /// The higher of both (conservative default).
  both;

  static DarwinPath? tryParse(String s) {
    for (final v in values) {
      if (v.name == s) return v;
    }
    return null;
  }
}

Finding _substitute(Finding f, Map<String, String> values) {
  if (f.resolved) return f;
  final v = values[f.expr];
  if (v == null || !Version.isLiteral(v)) return f;
  return f.copyWith(value: v, assumed: true);
}

int _byHighest(Finding a, Finding b) {
  final c = b.version!.compareTo(a.version!);
  if (c != 0) return c;
  final p = (a.package ?? '').compareTo(b.package ?? '');
  if (p != 0) return p;
  final f = a.file.compareTo(b.file);
  return f != 0 ? f : a.line.compareTo(b.line);
}

bool _sourceAllowed(Finding f, DarwinPath path) {
  if (f.target != Target.iosDeployment && f.target != Target.macosDeployment) {
    return true;
  }
  return switch (path) {
    DarwinPath.both => true,
    DarwinPath.cocoapods => f.source == Source.podspec,
    DarwinPath.spm => f.source == Source.spm,
  };
}

String _hint(Target t) => switch (t) {
  Target.androidMinSdk ||
  Target.androidCompileSdk => 'android/app/build.gradle(.kts)',
  Target.iosDeployment => 'ios/Podfile',
  Target.macosDeployment => 'macos/Podfile',
};

String _pbxproj(Target t) => switch (t) {
  Target.iosDeployment => 'ios/Runner.xcodeproj/project.pbxproj',
  Target.macosDeployment => 'macos/Runner.xcodeproj/project.pbxproj',
  _ => '',
};

final RegExp _assumeKey = RegExp(r'^[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*$');

/// `--assume` needs a plain name; other fragments get a hint without a KEY.
String _unresolvedFix(String expr) =>
    _assumeKey.hasMatch(expr) ? 'fix.unresolved' : 'fix.unresolvedExpr';

/// Compares plugin floors with the app and applies the PF rules.
///
/// Precedence: [assume] > the app's `local.properties` (app side only) >
/// [sdkDefaults] (Flutter SDK defaults for `flutter.*`, both sides).
ScanReport compare({
  required List<String> pluginNames,
  required List<Finding> pluginFindings,
  required AppConfig app,
  required Map<String, String> assume,
  required DarwinPath darwinPath,
  Map<String, String> sdkDefaults = const {},
}) {
  final pluginValues = {...sdkDefaults, ...assume};
  final plugin = [for (final f in pluginFindings) _substitute(f, pluginValues)]
    ..sort((a, b) {
      var c = (a.package ?? '').compareTo(b.package ?? '');
      if (c != 0) return c;
      c = a.target.index.compareTo(b.target.index);
      if (c != 0) return c;
      c = a.file.compareTo(b.file);
      return c != 0 ? c : a.line.compareTo(b.line);
    });
  final appValues = {...sdkDefaults, ...app.localProperties, ...assume};
  final appFindings = [for (final f in app.findings) _substitute(f, appValues)];

  final violations = <Violation>[];
  final summaries = <TargetSummary>[];
  final unresolved = <Finding>[];
  final benign = <Finding>{};

  for (final t in Target.values) {
    if (!app.platforms.contains(t.platform)) continue;
    Finding? appF;
    for (final f in appFindings) {
      if (f.target == t) appF = f;
    }
    final all = plugin.where((f) => f.target == t).toList();
    final allowed = all.where((f) => _sourceAllowed(f, darwinPath)).toList();

    final resolved = allowed.where((f) => f.resolved).toList()
      ..sort(_byHighest);
    final seen = <String>{};
    final perPackage = [
      for (final f in resolved)
        if (seen.add(f.package!)) f,
    ];
    final highest = perPackage.isEmpty ? null : perPackage.first;
    summaries.add(TargetSummary(target: t, app: appF, highest: highest));

    // Plugin-side values that cannot be resolved.
    final open = allowed.where((f) => !f.resolved).toList()
      ..sort((a, b) {
        final c = a.file.compareTo(b.file);
        return c != 0 ? c : a.line.compareTo(b.line);
      });
    for (final f in open) {
      unresolved.add(f);
      if (appF != null && appF.expr == f.expr) {
        benign.add(f); // same expression as the app, so it cannot exceed it
        continue;
      }
      violations.add(
        Violation(
          ruleId: 'PF010',
          severity: 'warning',
          messageKey: 'msg.PF010.plugin',
          fixKey: _unresolvedFix(f.expr),
          target: t,
          package: f.package,
          file: f.file,
          line: f.line,
          args: {
            'package': f.package!,
            'expr': f.expr,
            'reason': f.reason ?? 'expression',
          },
        ),
      );
    }

    // App side.
    final needsApp = perPackage.isNotEmpty || open.isNotEmpty;
    if (appF == null) {
      if (needsApp) {
        violations.add(
          Violation(
            ruleId: 'PF012',
            severity: 'warning',
            messageKey: 'msg.PF012',
            fixKey: 'fix.notFound',
            target: t,
            args: {'hint': _hint(t)},
          ),
        );
      }
    } else if (!appF.resolved) {
      unresolved.add(appF);
      if (needsApp) {
        violations.add(
          Violation(
            ruleId: 'PF010',
            severity: 'warning',
            messageKey: 'msg.PF010.app',
            fixKey: _unresolvedFix(appF.expr),
            target: t,
            appFile: appF.file,
            appLine: appF.line,
            args: {'expr': appF.expr, 'reason': appF.reason ?? 'expression'},
          ),
        );
      }
    } else {
      for (final f in perPackage) {
        if (f.version! > appF.version!) {
          violations.add(
            Violation(
              ruleId: t.ruleId,
              severity: 'error',
              messageKey: 'msg.violation',
              fixKey: f.source == Source.spm ? 'fix.raiseSpm' : 'fix.raise',
              target: t,
              package: f.package,
              file: f.file,
              line: f.line,
              appFile: appF.file,
              appLine: appF.line,
              required: f.value,
              appValue: appF.value,
              args: {
                'package': f.package!,
                'required': f.value!,
                'app': appF.value!,
                'file': appF.file,
                'line': '${appF.line}',
                'pbx': _pbxproj(t),
              },
            ),
          );
        }
      }
    }

    // CocoaPods vs SwiftPM floors of the same plugin (Apple targets only).
    if (t == Target.iosDeployment || t == Target.macosDeployment) {
      final byPackage = <String, List<Finding>>{};
      for (final f in all.where((f) => f.resolved)) {
        byPackage.putIfAbsent(f.package!, () => []).add(f);
      }
      for (final name in byPackage.keys.toList()..sort()) {
        final list = byPackage[name]!..sort(_byHighest);
        Finding? pod, spm;
        for (final f in list) {
          if (f.source == Source.podspec) pod ??= f;
          if (f.source == Source.spm) spm ??= f;
        }
        if (pod != null && spm != null && pod.version! != spm.version!) {
          violations.add(
            Violation(
              ruleId: 'PF011',
              severity: 'note',
              messageKey: 'msg.PF011',
              fixKey: 'fix.darwinPath',
              target: t,
              package: name,
              file: spm.file,
              line: spm.line,
              args: {'package': name, 'pod': pod.value!, 'spm': spm.value!},
            ),
          );
        }
      }
    }
  }

  for (final f in appFindings) {
    if (!f.resolved && !unresolved.contains(f)) unresolved.add(f);
  }

  const order = {'error': 0, 'warning': 1, 'note': 2};
  violations.sort((a, b) {
    var c = a.ruleId.compareTo(b.ruleId);
    if (c != 0) return c;
    c = (order[a.severity] ?? 3).compareTo(order[b.severity] ?? 3);
    if (c != 0) return c;
    final av = a.required == null ? null : Version.tryParse(a.required!);
    final bv = b.required == null ? null : Version.tryParse(b.required!);
    if (av != null && bv != null && av != bv) return bv.compareTo(av);
    c = (a.package ?? '').compareTo(b.package ?? '');
    if (c != 0) return c;
    c = (a.file ?? a.appFile ?? '').compareTo(b.file ?? b.appFile ?? '');
    return c != 0
        ? c
        : (a.line ?? a.appLine ?? 0).compareTo(b.line ?? b.appLine ?? 0);
  });

  return ScanReport(
    pluginNames: pluginNames,
    findings: plugin,
    appFindings: appFindings,
    summaries: summaries,
    violations: violations,
    unresolved: unresolved,
    benign: benign,
  );
}
