import 'dart:convert';
import 'dart:io';

import 'package:pluginfloor/pluginfloor.dart';
import 'package:pluginfloor/src/package_resolver.dart';
import 'package:test/test.dart';

import 'helpers.dart';

String pluginPubspec(
  String name, {
  String platforms = 'android:\n        package: a.b\n',
}) => 'name: $name\nflutter:\n  plugin:\n    platforms:\n      $platforms';

void main() {
  test('sample app: exactly the plugin packages, federated ones included', () {
    final plugins = resolvePlugins('example/sample_app');
    expect(
      [for (final p in plugins) p.name],
      [
        'cloud_core',
        'face_scan_commons',
        'file_drop',
        'perm_guard_android',
        'snap_camera',
        'snap_camera_android',
        'snap_camera_darwin',
      ],
    );
  });

  test('plain packages and the app itself are ignored', () {
    final names = [
      for (final p in resolvePlugins('example/sample_app')) p.name,
    ];
    expect(names, isNot(contains('plain_utils')));
    expect(names, isNot(contains('sample_app')));
  });

  test('files under a plugin example/ folder never produce findings', () {
    final report = scanApp(AppScanOptions(appDir: 'example/sample_app'));
    expect(report.findings.where((f) => f.file.contains('/example/')), isEmpty);
    expect(
      report.findings.where((f) => f.file.startsWith('cloud_core/example')),
      isEmpty,
    );
    // the trap value is 30; the real cloud_core floor is 23
    expect(report.findings.where((f) => f.value == '30'), isEmpty);
  });

  group('rootUri forms', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('pf_resolver_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('relative, absolute and percent-encoded rootUri', () {
      final root = tmp.resolveSymbolicLinksSync();
      writeFiles(root, {
        'app/pubspec.yaml': 'name: app\n',
        'rel_plugin/pubspec.yaml': pluginPubspec('rel_plugin'),
        'abs_plugin/pubspec.yaml': pluginPubspec('abs_plugin'),
        // directory name contains a literal percent sign, as a mirror host
        // such as localhost:8765 does ("localhost%588765")
        'hosted/localhost%588765/enc_plugin-1.0.0/pubspec.yaml': pluginPubspec(
          'enc_plugin',
        ),
        'plain/pubspec.yaml': 'name: plain\n',
      });
      final config = {
        'configVersion': 2,
        'packages': [
          {
            'name': 'rel_plugin',
            'rootUri': '../../rel_plugin',
            'packageUri': 'lib/',
          },
          {
            'name': 'abs_plugin',
            'rootUri': Uri.directory('$root/abs_plugin').toString(),
            'packageUri': 'lib/',
          },
          {
            'name': 'enc_plugin',
            'rootUri': '../../hosted/localhost%25588765/enc_plugin-1.0.0',
            'packageUri': 'lib/',
          },
          {'name': 'plain', 'rootUri': '../../plain', 'packageUri': 'lib/'},
          {'name': 'app', 'rootUri': '../', 'packageUri': 'lib/'},
          {
            'name': 'gone',
            'rootUri': '../../does_not_exist',
            'packageUri': 'lib/',
          },
        ],
      };
      writeFiles(root, {
        'app/.dart_tool/package_config.json': jsonEncode(config),
      });
      final plugins = resolvePlugins('$root/app');
      expect(
        [for (final p in plugins) p.name],
        ['abs_plugin', 'enc_plugin', 'rel_plugin'],
      );
      expect(
        plugins.firstWhere((p) => p.name == 'enc_plugin').root,
        endsWith('localhost%588765/enc_plugin-1.0.0'),
      );
    });

    test(
      'an app that is itself a plugin is excluded; --package-config is honoured',
      () {
        final root = tmp.resolveSymbolicLinksSync();
        writeFiles(root, {
          'app/pubspec.yaml': pluginPubspec('app'),
          'elsewhere/package_config.json': jsonEncode({
            'configVersion': 2,
            'packages': [
              {'name': 'app', 'rootUri': '../app/', 'packageUri': 'lib/'},
            ],
          }),
        });
        expect(
          resolvePlugins(
            '$root/app',
            packageConfig: '$root/elsewhere/package_config.json',
          ),
          isEmpty,
        );
      },
    );

    test('a pubspec without a platforms map means every folder is scanned', () {
      final root = tmp.resolveSymbolicLinksSync();
      writeFiles(root, {
        'app/pubspec.yaml': 'name: app\n',
        'old/pubspec.yaml':
            'name: old\nflutter:\n  plugin:\n    androidPackage: a.b\n',
        'app/.dart_tool/package_config.json': jsonEncode({
          'configVersion': 2,
          'packages': [
            {'name': 'old', 'rootUri': '../../old', 'packageUri': 'lib/'},
          ],
        }),
      });
      final p = resolvePlugins('$root/app').single;
      expect(p.platforms, isNull);
      expect(p.declares('ios'), isTrue);
    });
  });
}
