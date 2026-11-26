import 'dart:convert';
import 'dart:io';

import 'package:pluginfloor/pluginfloor.dart';
import 'package:pluginfloor/src/package_resolver.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _kotlin = '''
class FlutterExtension {
    /** Sets the compileSdkVersion used by default in Flutter app projects. */
    val compileSdkVersion: Int = 35

    /** Sets the minSdkVersion used by default in Flutter app projects. */
    val minSdkVersion: Int = 21
}
''';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('pf_sdk_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Builds `<tmp>/app` (default template, `flutter.*` names) with one
  /// Android plugin that needs minSdk 24 / compileSdk 36, and a fake SDK in
  /// `<tmp>/sdk`. [kotlin] null means no FlutterExtension.kt, [withFlutter]
  /// false leaves the `flutter` package out of package_config.json.
  String makeApp({
    String? kotlin = _kotlin,
    bool withFlutter = true,
    String localProperties = '',
  }) {
    final packages = [
      {'name': 'needy', 'rootUri': '../../plugins/needy', 'packageUri': 'lib/'},
      if (withFlutter)
        {
          'name': 'flutter',
          'rootUri': '../../sdk/packages/flutter',
          'packageUri': 'lib/',
        },
    ];
    writeFiles(tmp.path, {
      'app/.dart_tool/package_config.json': jsonEncode({
        'configVersion': 2,
        'packages': packages,
      }),
      'app/pubspec.yaml': 'name: app\n',
      'app/android/app/build.gradle.kts':
          'android {\n    compileSdk = flutter.compileSdkVersion\n'
          '    defaultConfig {\n        minSdk = flutter.minSdkVersion\n'
          '    }\n}\n',
      if (localProperties.isNotEmpty)
        'app/android/local.properties': localProperties,
      'plugins/needy/pubspec.yaml':
          'name: needy\nflutter:\n  plugin:\n    platforms:\n'
          '      android:\n        package: a.b\n',
      'plugins/needy/android/build.gradle':
          'android {\n    compileSdk 36\n    defaultConfig {\n'
          '        minSdk 24\n    }\n}\n',
      'sdk/packages/flutter/pubspec.yaml': 'name: flutter\n',
      if (kotlin != null)
        'sdk/packages/flutter_tools/gradle/src/main/kotlin/'
                'FlutterExtension.kt':
            kotlin,
    });
    return '${tmp.path}/app';
  }

  ScanReport scan(String app, [Map<String, String> assume = const {}]) =>
      scanApp(AppScanOptions(appDir: app, assume: assume));

  List<String> rules(ScanReport r) => [
    for (final v in r.violations) '${v.ruleId}:${v.target?.name}',
  ];

  test('(a) names resolve from the SDK without any option', () {
    final app = makeApp();
    expect(readFlutterSdkDefaults(app), {
      'flutter.minSdkVersion': '21',
      'flutter.compileSdkVersion': '35',
    });
    final r = scan(app);
    expect(
      rules(r),
      unorderedEquals(['PF001:androidMinSdk', 'PF002:androidCompileSdk']),
    );
    expect(r.violations.where((v) => v.ruleId == 'PF010'), isEmpty);
  });

  test('(b) --assume beats the SDK value, local.properties beats the SDK', () {
    final app = makeApp();
    // Assumed 24/36 meets the plugin floors, the SDK's 21/35 would not.
    final ok = scan(app, {
      'flutter.minSdkVersion': '24',
      'flutter.compileSdkVersion': '36',
    });
    expect(ok.violations, isEmpty);

    final app2 = makeApp(
      localProperties:
          'flutter.minSdkVersion=24\nflutter.compileSdkVersion=36\n',
    );
    expect(scan(app2).violations, isEmpty);
    // --assume still wins over local.properties.
    final r = scan(app2, {'flutter.minSdkVersion': '19'});
    expect(rules(r), contains('PF001:androidMinSdk'));
  });

  group('(c) stays PF010 when it cannot be read', () {
    void expectUnknown(String app) {
      expect(readFlutterSdkDefaults(app), isEmpty);
      final r = scan(app);
      final pf010 = r.violations.where((v) => v.ruleId == 'PF010');
      expect(pf010, isNotEmpty);
      expect(r.violations.where((v) => v.ruleId == 'PF001'), isEmpty);
    }

    test('FlutterExtension.kt is missing', () {
      expectUnknown(makeApp(kotlin: null));
    });

    test('literal format differs', () {
      expectUnknown(
        makeApp(
          kotlin:
              'val minSdkVersion: Int = computeMin()\n'
              'val compileSdkVersion = 35\n',
        ),
      );
    });

    test('no flutter package in package_config.json', () {
      expectUnknown(makeApp(withFlutter: false));
    });

    test('only one literal readable resolves only that name', () {
      final app = makeApp(kotlin: 'val minSdkVersion: Int = 21\n');
      expect(readFlutterSdkDefaults(app), {'flutter.minSdkVersion': '21'});
    });
  });
}
