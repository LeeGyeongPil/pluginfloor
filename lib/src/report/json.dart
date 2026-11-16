import 'dart:convert';

import '../i18n/messages.dart';
import '../info.dart';
import '../model.dart';

/// Language-independent JSON for a [Finding]; field names never change.
Map<String, Object?> findingJson(Finding f, {bool? benign}) => {
  'package': f.package,
  'target': f.target.id,
  'source': f.source.name,
  'expr': f.expr,
  'value': f.value,
  'resolved': f.resolved,
  if (f.assumed) 'assumed': true,
  if (f.reason != null) 'reason': f.reason,
  'file': f.file,
  'line': f.line,
  if (f.viaFile != null) 'via': {'file': f.viaFile, 'line': f.viaLine},
  if (benign != null) 'benign': benign,
};

Map<String, Object?> _location(String? file, int? line) =>
    file == null ? {} : {'file': file, 'line': line};

/// Renders the report as deterministic JSON (`schemaVersion` 1).
///
/// Only the `message` and `fix` strings depend on [lang]; rule IDs, field
/// names and values do not.
String renderJson(ScanReport r, Messages m) {
  final doc = <String, Object?>{
    'schemaVersion': 1,
    'tool': {'name': 'pluginfloor', 'version': packageVersion},
    'plugins': r.pluginNames,
    'targets': [
      for (final s in r.summaries)
        {
          'target': s.target.id,
          'app': s.app == null ? null : findingJson(s.app!),
          'highest': s.highest == null ? null : findingJson(s.highest!),
        },
    ],
    'violations': [
      for (final v in r.violations)
        {
          'ruleId': v.ruleId,
          'severity': v.severity,
          'target': v.target?.id,
          'package': v.package,
          'required': v.required,
          'app': v.appValue,
          'message': m.message(v),
          'fix': m.fix(v),
          'location': _location(v.file, v.line),
          'appLocation': _location(v.appFile, v.appLine),
        },
    ],
    'findings': [for (final f in r.findings) findingJson(f)],
    'unresolved': [
      for (final f in r.unresolved)
        findingJson(f, benign: r.benign.contains(f)),
    ],
  };
  return '${const JsonEncoder.withIndent('  ').convert(doc)}\n';
}
