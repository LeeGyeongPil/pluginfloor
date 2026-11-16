import 'dart:convert';
import 'dart:io';

import 'package:pluginfloor/pluginfloor.dart';
import 'package:pluginfloor/src/i18n/messages.dart';
import 'package:pluginfloor/src/report/json.dart';
import 'package:pluginfloor/src/report/sarif.dart';
import 'package:test/test.dart';

/// Run with `UPDATE_GOLDENS=1 dart test test/report_test.dart` to rewrite the
/// golden files after an intentional output change.
void expectGolden(String path, String actual) {
  final file = File(path);
  if (Platform.environment['UPDATE_GOLDENS'] == '1') {
    file.createSync(recursive: true);
    file.writeAsStringSync(actual);
  }
  expect(file.existsSync(), isTrue, reason: 'missing golden $path');
  expect(actual, file.readAsStringSync(), reason: 'output differs from $path');
}

ScanReport scan() => scanApp(AppScanOptions(appDir: 'example/sample_app'));

void main() {
  test('JSON equals the golden file', () {
    expectGolden(
      'test/goldens/sample_app.json',
      renderJson(scan(), Messages.en),
    );
  });

  test('SARIF equals the golden file', () {
    expectGolden(
      'test/goldens/sample_app.sarif',
      renderSarif(scan(), Messages.en),
    );
  });

  test('two runs are byte-identical', () {
    expect(renderJson(scan(), Messages.en), renderJson(scan(), Messages.en));
    expect(renderSarif(scan(), Messages.en), renderSarif(scan(), Messages.en));
  });

  test('no absolute paths and no machine-specific text', () {
    for (final text in [
      renderJson(scan(), Messages.en),
      renderSarif(scan(), Messages.en),
    ]) {
      expect(text, isNot(contains(Directory.current.path)));
      // Absolute home-style prefixes, assembled at runtime.
      expect(text, isNot(contains(['', 'Users', ''].join('/'))));
      expect(text, isNot(contains(['', 'Volumes', ''].join('/'))));
      expect(text, isNot(contains('file:///')));
    }
  });

  group('JSON structure', () {
    late Map<String, dynamic> doc;
    setUpAll(
      () => doc =
          jsonDecode(renderJson(scan(), Messages.en)) as Map<String, dynamic>,
    );

    test('schemaVersion 1 with violations, findings and unresolved', () {
      expect(doc['schemaVersion'], 1);
      expect(
        doc.keys,
        containsAll([
          'violations',
          'findings',
          'unresolved',
          'targets',
          'plugins',
        ]),
      );
    });

    test('every file in the report is relative', () {
      void check(Object? v) {
        if (v is Map) {
          v.forEach((k, x) {
            if (k == 'file') expect(x as String, isNot(startsWith('/')));
            check(x);
          });
        } else if (v is List) {
          v.forEach(check);
        }
      }

      check(doc);
    });

    test('unresolved list carries the benign flag', () {
      final un = (doc['unresolved'] as List).cast<Map<String, dynamic>>();
      expect(un.where((f) => f['benign'] == true).map((f) => f['package']), [
        'snap_camera_android',
      ]);
      expect(un.where((f) => f['benign'] == false).map((f) => f['package']), [
        null,
      ]);
    });

    test('violations carry rule id, severity, location and a Fix', () {
      final v = (doc['violations'] as List).cast<Map<String, dynamic>>();
      expect(v.map((x) => x['ruleId']), [
        'PF001',
        'PF001',
        'PF003',
        'PF004',
        'PF010',
        'PF011',
      ]);
      final first = v.first;
      expect(first['location'], {
        'file': 'perm_guard_android/android/build.gradle.kts',
        'line': 11,
      });
      expect(first['appLocation'], {
        'file': 'android/app/build.gradle.kts',
        'line': 11,
      });
      expect(first['fix'], contains('minSdk to 24'));
    });
  });

  group('SARIF structure', () {
    late Map<String, dynamic> doc;
    setUpAll(
      () => doc =
          jsonDecode(renderSarif(scan(), Messages.en)) as Map<String, dynamic>,
    );

    test('2.1.0 with rules in the PF001-PF012 range', () {
      expect(doc['version'], '2.1.0');
      final run = (doc['runs'] as List).single as Map<String, dynamic>;
      final rules = (((run['tool'] as Map)['driver'] as Map)['rules'] as List)
          .map((r) => (r as Map)['id'] as String)
          .toList();
      expect(rules, [
        'PF001',
        'PF002',
        'PF003',
        'PF004',
        'PF010',
        'PF011',
        'PF012',
      ]);
    });

    test('each result has uri and startLine and a valid rule index', () {
      final run = (doc['runs'] as List).single as Map<String, dynamic>;
      final rules = (((run['tool'] as Map)['driver'] as Map)['rules'] as List)
          .cast<Map<String, dynamic>>();
      final results = (run['results'] as List).cast<Map<String, dynamic>>();
      expect(results, isNotEmpty);
      for (final r in results) {
        expect(rules[r['ruleIndex'] as int]['id'], r['ruleId']);
        for (final loc
            in (r['locations'] as List).cast<Map<String, dynamic>>()) {
          final phys = loc['physicalLocation'] as Map<String, dynamic>;
          expect(
            ((phys['artifactLocation'] as Map)['uri'] as String),
            isNotEmpty,
          );
          expect(((phys['region'] as Map)['startLine'] as int), greaterThan(0));
        }
      }
      final first = results.first;
      expect(first['level'], 'error');
      final primary =
          ((first['locations'] as List).single as Map)['physicalLocation']
              as Map;
      expect(
        (primary['artifactLocation'] as Map)['uri'],
        'android/app/build.gradle.kts',
      );
      expect(first['relatedLocations'], isNotEmpty);
    });
  });
}
