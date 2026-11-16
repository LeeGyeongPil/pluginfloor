import 'dart:io';

import 'package:pluginfloor/pluginfloor.dart';
import 'package:test/test.dart';

import 'helpers.dart';

ScanReport scan(
  String dir, {
  Map<String, String> assume = const {},
  DarwinPath darwin = DarwinPath.both,
}) => scanApp(AppScanOptions(appDir: dir, assume: assume, darwinPath: darwin));

TargetSummary summary(ScanReport r, Target t) =>
    r.summaries.firstWhere((s) => s.target == t);

List<String> ids(ScanReport r, String rule) => [
  for (final v in r.violations)
    if (v.ruleId == rule)
      '${v.package ?? 'app'}:${v.appValue ?? ''}<${v.required ?? ''}',
];

void main() {
  group('sample app', () {
    late ScanReport report;
    setUpAll(() => report = scan('example/sample_app'));

    test('highest floors and what raises them', () {
      final min = summary(report, Target.androidMinSdk);
      expect(
        (min.app!.value, min.highest!.value, min.highest!.package),
        ('21', '24', 'perm_guard_android'),
      );
      final ios = summary(report, Target.iosDeployment);
      expect(
        (ios.app!.value, ios.highest!.value, ios.highest!.package),
        ('13.0', '15.5', 'face_scan_commons'),
      );
      final mac = summary(report, Target.macosDeployment);
      expect((mac.app!.value, mac.highest!.value), ('10.14', '11.0'));
    });

    test(
      'iOS app value falls back from the commented Podfile to project.pbxproj',
      () {
        final app = summary(report, Target.iosDeployment).app!;
        expect(
          (app.file, app.line, app.value),
          ('ios/Runner.xcodeproj/project.pbxproj', 7, '13.0'),
        );
      },
    );

    test(
      'violations: one PF001 per offending plugin, no PF002 while compileSdk is unknown',
      () {
        expect(ids(report, 'PF001'), [
          'perm_guard_android:21<24',
          'cloud_core:21<23',
        ]);
        expect(ids(report, 'PF002'), isEmpty);
        expect(ids(report, 'PF003'), ['face_scan_commons:13.0<15.5']);
        expect(ids(report, 'PF004'), ['cloud_core:10.14<11.0']);
      },
    );

    test(
      'PF010 for the app compileSdk; the plugin using the same expression is benign',
      () {
        final pf010 = report.violations
            .where((v) => v.ruleId == 'PF010')
            .toList();
        expect(pf010, hasLength(1));
        expect(pf010.single.args['expr'], 'flutter.compileSdkVersion');
        expect(pf010.single.appFile, 'android/app/build.gradle.kts');
        final unresolvedPlugins = report.unresolved.where(
          (f) => f.package != null,
        );
        expect(unresolvedPlugins.map((f) => f.package), [
          'snap_camera_android',
        ]);
        expect(report.benign.map((f) => f.package), ['snap_camera_android']);
      },
    );

    test('PF011 note for cloud_core', () {
      final v = report.violations.singleWhere((v) => v.ruleId == 'PF011');
      expect(
        (v.severity, v.package, v.args['pod'], v.args['spm']),
        ('note', 'cloud_core', '10.15', '11.0'),
      );
    });

    test('exit code is 1; strict makes no difference when errors exist', () {
      expect(report.exitCode(), 1);
      expect(report.exitCode(strict: true), 1);
    });
  });

  group('--assume', () {
    test('assuming flutter.compileSdkVersion=35 turns PF010 into PF002', () {
      final r = scan(
        'example/sample_app',
        assume: {'flutter.compileSdkVersion': '35'},
      );
      expect(r.violations.where((v) => v.ruleId == 'PF010'), isEmpty);
      expect(ids(r, 'PF002'), ['perm_guard_android:35<36']);
      final app = summary(r, Target.androidCompileSdk).app!;
      expect((app.value, app.assumed), ('35', true));
    });

    test('a value above the plugin floor gives no PF002', () {
      final r = scan(
        'example/sample_app',
        assume: {'flutter.compileSdkVersion': '36'},
      );
      expect(ids(r, 'PF002'), isEmpty);
    });
  });

  group('--darwin-path', () {
    test('macOS floor is 10.15 / 11.0 / 11.0 for cocoapods / spm / both', () {
      String floor(DarwinPath p) => summary(
        scan('example/sample_app', darwin: p),
        Target.macosDeployment,
      ).highest!.value!;
      expect(floor(DarwinPath.cocoapods), '10.15');
      expect(floor(DarwinPath.spm), '11.0');
      expect(floor(DarwinPath.both), '11.0');
    });

    test('cocoapods only: PF004 says 10.15 and points at the podspec', () {
      final r = scan('example/sample_app', darwin: DarwinPath.cocoapods);
      final v = r.violations.singleWhere((v) => v.ruleId == 'PF004');
      expect(
        (v.required, v.file),
        ('10.15', 'cloud_core/macos/cloud_core.podspec'),
      );
    });
  });

  group('app side edits', () {
    late Directory tmp;
    late String app;
    setUp(() {
      tmp = copyExample();
      app = '${tmp.path}/example/sample_app';
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test(
      'local.properties fills flutter.minSdkVersion; --assume wins over it',
      () {
        replaceIn(
          '$app/android/app/build.gradle.kts',
          'minSdk = 21',
          'minSdk = flutter.minSdkVersion',
        );
        writeFiles(app, {
          'android/local.properties':
              '## generated\nsdk.dir=/x\nflutter.minSdkVersion=25\n',
        });
        final fromProps = scan(app);
        final min = summary(fromProps, Target.androidMinSdk).app!;
        expect((min.value, min.assumed), ('25', true));
        expect(ids(fromProps, 'PF001'), isEmpty);

        final assumed = scan(app, assume: {'flutter.minSdkVersion': '21'});
        expect(summary(assumed, Target.androidMinSdk).app!.value, '21');
        expect(ids(assumed, 'PF001'), [
          'perm_guard_android:21<24',
          'cloud_core:21<23',
        ]);
      },
    );

    test('Podfile platform wins over project.pbxproj', () {
      writeFiles(app, {'ios/Podfile': "platform :ios, '16.0'\n"});
      final r = scan(app);
      final ios = summary(r, Target.iosDeployment).app!;
      expect((ios.value, ios.file, ios.line), ('16.0', 'ios/Podfile', 1));
      expect(ids(r, 'PF003'), isEmpty);
    });

    test('lowest IPHONEOS_DEPLOYMENT_TARGET of all configurations is used', () {
      replaceIn(
        '$app/ios/Runner.xcodeproj/project.pbxproj',
        'IPHONEOS_DEPLOYMENT_TARGET = 13.0;\n\t\t\t};\n\t\t\tname = Profile;',
        'IPHONEOS_DEPLOYMENT_TARGET = 12.0;\n\t\t\t};\n\t\t\tname = Profile;',
      );
      final ios = summary(scan(app), Target.iosDeployment).app!;
      expect((ios.value, ios.line), ('12.0', 21));
    });

    test('Podfile and pbxproj both missing -> PF012 warning, no PF003', () {
      File('$app/ios/Podfile').deleteSync();
      Directory('$app/ios/Runner.xcodeproj').deleteSync(recursive: true);
      final r = scan(app);
      final v = r.violations.singleWhere((v) => v.ruleId == 'PF012');
      expect((v.severity, v.target), ('warning', Target.iosDeployment));
      expect(ids(r, 'PF003'), isEmpty);
    });

    test('a platform folder the app does not have is skipped', () {
      Directory('$app/macos').deleteSync(recursive: true);
      final r = scan(app);
      expect(
        r.summaries.map((s) => s.target),
        isNot(contains(Target.macosDeployment)),
      );
      expect(ids(r, 'PF004'), isEmpty);
    });

    test('app value equal to the plugin floor is not a violation', () {
      replaceIn(
        '$app/android/app/build.gradle.kts',
        'minSdk = 21',
        'minSdk = 24',
      );
      expect(ids(scan(app), 'PF001'), isEmpty);
    });
  });
}
