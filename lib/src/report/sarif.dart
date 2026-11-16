import 'dart:convert';

import '../i18n/messages.dart';
import '../info.dart';
import '../model.dart';

/// Rules this tool can emit (IDs PF005-PF009 are reserved).
const _implemented = [
  'PF001',
  'PF002',
  'PF003',
  'PF004',
  'PF010',
  'PF011',
  'PF012',
];

Map<String, Object?> _physical(String file, int? line) => {
  'physicalLocation': {
    'artifactLocation': {'uri': file},
    'region': {'startLine': line ?? 1},
  },
};

/// Renders SARIF 2.1.0. The primary location is the app file that has to
/// change; the plugin file that raises the floor is a related location.
String renderSarif(ScanReport r, Messages m) {
  final doc = <String, Object?>{
    r'$schema': 'https://json.schemastore.org/sarif-2.1.0.json',
    'version': '2.1.0',
    'runs': [
      {
        'tool': {
          'driver': {
            'name': 'pluginfloor',
            'version': packageVersion,
            'informationUri': 'https://github.com/LeeGyeongPil/pluginfloor',
            'rules': [
              for (final id in _implemented)
                {
                  'id': id,
                  'name': id,
                  'shortDescription': {'text': m.text('rule.$id')},
                },
            ],
          },
        },
        'results': [
          for (final v in r.violations)
            {
              'ruleId': v.ruleId,
              'ruleIndex': _implemented.indexOf(v.ruleId),
              'level': v.severity,
              'message': {'text': m.message(v)},
              'locations': [
                if (v.appFile != null)
                  _physical(v.appFile!, v.appLine)
                else if (v.file != null)
                  _physical(v.file!, v.line),
              ],
              if (v.appFile != null && v.file != null)
                'relatedLocations': [_physical(v.file!, v.line)],
            },
        ],
      },
    ],
  };
  return '${const JsonEncoder.withIndent('  ').convert(doc)}\n';
}
