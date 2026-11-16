import 'package:pluginfloor/pluginfloor.dart';
import 'package:pluginfloor/src/android_parser.dart';
import 'package:pluginfloor/src/package_resolver.dart';
import 'package:pluginfloor/src/scan.dart' show collectPluginFindings;
import 'package:test/test.dart';

/// (target, value, resolved, file, line) for compact assertions.
typedef Row = (String, String?, bool, String, int);

List<Row> rows(List<Finding> fs) => [
  for (final f in fs) (f.target.id, f.value, f.resolved, f.file, f.line),
];

void main() {
  group('Groovy forms', () {
    test('space, equals and call forms with exact line numbers', () {
      const text = '''
android {
    compileSdkVersion 34
    defaultConfig {
        minSdkVersion 21
    }
}
android {
    compileSdk = 35
    defaultConfig {
        minSdk 22
        minSdkVersion(23)
    }
}
''';
      expect(rows(parseGradle(text, file: 'p/build.gradle', package: 'p')), [
        ('android.compileSdk', '34', true, 'p/build.gradle', 2),
        ('android.minSdk', '21', true, 'p/build.gradle', 4),
        ('android.compileSdk', '35', true, 'p/build.gradle', 8),
        ('android.minSdk', '22', true, 'p/build.gradle', 10),
        ('android.minSdk', '23', true, 'p/build.gradle', 11),
      ]);
    });

    test('Kotlin DSL after blank lines reports the real line', () {
      const text =
          '\n\n\nandroid {\n\n    compileSdk = 36\n\n    defaultConfig { }\n    minSdk = 24\n}\n';
      expect(rows(parseGradle(text, file: 'k.kts')), [
        ('android.compileSdk', '36', true, 'k.kts', 6),
        ('android.minSdk', '24', true, 'k.kts', 9),
      ]);
    });

    test('comments are ignored but keep line numbers', () {
      const text = '''
// minSdkVersion 5
/* block
   minSdk = 6
*/
android {
    minSdkVersion 21 // trailing comment
}
''';
      expect(rows(parseGradle(text, file: 'c.gradle')), [
        ('android.minSdk', '21', true, 'c.gradle', 6),
      ]);
    });

    test('declarations after an opening brace on the same line', () {
      const text = 'android { defaultConfig { minSdkVersion 21 } }\n';
      expect(rows(parseGradle(text, file: 'o.gradle')), [
        ('android.minSdk', '21', true, 'o.gradle', 1),
      ]);
    });

    test('names that only look similar are not matched', () {
      const text =
          'android {\n  minSdkVersionFoo 5\n  targetSdk = 30\n  myminSdk = 3\n}\n';
      expect(parseGradle(text, file: 'x.gradle'), isEmpty);
    });
  });

  group('unresolved values stay unresolved', () {
    test('flutter.* and rootProject.ext.*', () {
      const text = '''
android {
    compileSdkVersion flutter.compileSdkVersion
    defaultConfig {
        minSdkVersion rootProject.ext.minSdkVersion
        minSdk = flutter.minSdkVersion
    }
}
''';
      final fs = parseGradle(text, file: 'u.gradle');
      expect(rows(fs), [
        ('android.compileSdk', null, false, 'u.gradle', 2),
        ('android.minSdk', null, false, 'u.gradle', 4),
        ('android.minSdk', null, false, 'u.gradle', 5),
      ]);
      expect(
        [for (final f in fs) f.reason],
        ['flutter', 'rootProject', 'flutter'],
      );
      expect(
        [for (final f in fs) f.expr],
        [
          'flutter.compileSdkVersion',
          'rootProject.ext.minSdkVersion',
          'flutter.minSdkVersion',
        ],
      );
    });

    test('unknown ext name without an apply-from file', () {
      final f = parseGradle('minSdk project.ext.minSdk\n', file: 'g').single;
      expect((f.resolved, f.reason), (false, 'ext'));
    });
  });

  group('ext values', () {
    test('one apply-from hop resolves the value with its source location', () {
      const gradle =
          'apply from: "local-config.gradle"\n\nandroid {\n  defaultConfig {\n    minSdk project.ext.minSdk\n  }\n}\n';
      const ext = '// shared\next {\n    minSdk = 23\n}\n';
      final asked = <String>[];
      final fs = parseGradle(
        gradle,
        file: 'cloud/android/build.gradle',
        package: 'cloud',
        readApply: (ref) {
          asked.add(ref);
          return (text: ext, displayPath: 'cloud/android/local-config.gradle');
        },
      );
      expect(asked, ['local-config.gradle']);
      expect(rows(fs), [
        ('android.minSdk', '23', true, 'cloud/android/local-config.gradle', 3),
      ]);
      expect(
        (fs.single.viaFile, fs.single.viaLine),
        ('cloud/android/build.gradle', 5),
      );
    });

    test('Kotlin apply(from = ...) form and ext.NAME = N form', () {
      const gradle =
          'apply(from = "vars.gradle.kts")\nandroid { minSdk = ext.floor }\n';
      final fs = parseGradle(
        gradle,
        file: 'k.kts',
        readApply: (ref) => (text: '\n\next.floor = 26\n', displayPath: ref),
      );
      expect(rows(fs), [('android.minSdk', '26', true, 'vars.gradle.kts', 3)]);
    });

    test('apply from: file("./x.gradle") form', () {
      final fs = parseGradle(
        'apply from: file("./local-config.gradle")\nminSdk = project.ext.minSdk\n',
        file: 'g',
        readApply: (ref) =>
            (text: 'ext {\n  minSdk = 21\n}\n', displayPath: ref),
      );
      expect(rows(fs), [
        ('android.minSdk', '21', true, './local-config.gradle', 2),
      ]);
    });

    test('a value defined in the same file resolves', () {
      const gradle =
          'def minSdkValue = 24\nandroid {\n  minSdkVersion minSdkValue\n}\n';
      expect(rows(parseGradle(gradle, file: 'd.gradle')), [
        ('android.minSdk', '24', true, 'd.gradle', 1),
      ]);
    });

    test(
      'only one hop: names defined by a second apply-from stay unresolved',
      () {
        const gradle = 'apply from: "a.gradle"\nminSdk project.ext.deep\n';
        final fs = parseGradle(
          gradle,
          file: 'g',
          readApply: (ref) => ref == 'a.gradle'
              ? (text: 'apply from: "b.gradle"\n', displayPath: 'a')
              : (text: 'ext { deep = 30 }\n', displayPath: 'b'),
        );
        expect(fs.single.resolved, isFalse);
      },
    );

    test('references with a variable part are not followed', () {
      var asked = 0;
      parseGradle(
        'apply from: "\$flutterRoot/x.gradle"\nminSdk 21\n',
        file: 'g',
        readApply: (ref) {
          asked++;
          return null;
        },
      );
      expect(asked, 0);
    });
  });

  group('AndroidManifest uses-sdk', () {
    test('value and line after blank lines, comments ignored', () {
      const xml = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">


    <!-- <uses-sdk android:minSdkVersion="28"/> -->
    <uses-sdk android:minSdkVersion="19"
        android:targetSdkVersion="33"/>
</manifest>
''';
      expect(
        rows(parseManifest(xml, file: 'm/AndroidManifest.xml', package: 'm')),
        [('android.minSdk', '19', true, 'm/AndroidManifest.xml', 5)],
      );
    });

    test('placeholders are unresolved', () {
      final f = parseManifest(
        '<uses-sdk android:minSdkVersion="\${minSdk}"/>',
        file: 'm',
      ).single;
      expect(f.resolved, isFalse);
    });
  });

  group('sample plugins (end to end)', () {
    PluginPackage pkg(String name) =>
        resolvePlugins('example/sample_app').firstWhere((p) => p.name == name);

    test('cloud_core resolves 23 through local-config.gradle', () {
      final fs = collectPluginFindings(
        pkg('cloud_core'),
      ).where((f) => f.target == Target.androidMinSdk).toList();
      expect(rows(fs), [
        (
          'android.minSdk',
          '23',
          true,
          'cloud_core/android/local-config.gradle',
          3,
        ),
      ]);
      expect(fs.single.viaFile, 'cloud_core/android/build.gradle');
    });

    test(
      'perm_guard_android: blank first line does not shift the line number',
      () {
        final fs = collectPluginFindings(pkg('perm_guard_android'));
        expect(rows(fs), [
          (
            'android.compileSdk',
            '36',
            true,
            'perm_guard_android/android/build.gradle.kts',
            8,
          ),
          (
            'android.minSdk',
            '24',
            true,
            'perm_guard_android/android/build.gradle.kts',
            11,
          ),
        ]);
      },
    );

    test('snap_camera_android keeps flutter.compileSdkVersion unresolved', () {
      final fs = collectPluginFindings(pkg('snap_camera_android'));
      expect(rows(fs), [
        (
          'android.compileSdk',
          null,
          false,
          'snap_camera_android/android/build.gradle',
          6,
        ),
        (
          'android.minSdk',
          '21',
          true,
          'snap_camera_android/android/build.gradle',
          9,
        ),
      ]);
    });

    test('file_drop reads uses-sdk from the manifest', () {
      final fs = collectPluginFindings(
        pkg('file_drop'),
      ).where((f) => f.target == Target.androidMinSdk);
      expect(rows(fs.toList()), [
        (
          'android.minSdk',
          '19',
          true,
          'file_drop/android/src/main/AndroidManifest.xml',
          4,
        ),
      ]);
    });
  });

  group('AGP block syntax', () {
    Map<String, (String?, int)> read(String text) => {
      for (final f in parseGradle(text, file: 'b.gradle'))
        f.target.id: (f.value, f.line),
    };

    test('multi-line and one-line blocks (Groovy and KTS)', () {
      const text = '''
android {
    compileSdk {
        version = release(36)
    }
    defaultConfig {
        minSdk { version = release(26) }
    }
}
''';
      final fs = parseGradle(text, file: 'b.gradle');
      expect(rows(fs), [
        ('android.compileSdk', '36', true, 'b.gradle', 3),
        ('android.minSdk', '26', true, 'b.gradle', 6),
      ]);
      expect(fs.first.expr, 'release(36)');
    });

    test('release(N) with a minorApiLevel tail and *Version names', () {
      const text = '''
android {
    compileSdkVersion = release(36) { minorApiLevel = 1 }
    compileSdk {
        version = release(35) {
            minorApiLevel = 1
        }
    }
    minSdk { version = release(24, 2) }
}
''';
      expect(rows(parseGradle(text, file: 'k.kts')), [
        ('android.compileSdk', '36', true, 'k.kts', 2),
        ('android.compileSdk', '35', true, 'k.kts', 4),
        ('android.minSdk', '24', true, 'k.kts', 8),
      ]);
    });

    test('unreadable block stays unresolved with the readable fragment', () {
      const text = '''
android {
    minSdk { version = release(flutter.minSdk) }
    compileSdk {
        somethingElse()
    }
}
''';
      final fs = parseGradle(text, file: 'b.gradle');
      expect(fs.map((f) => (f.value, f.reason)), [
        (null, 'flutter'),
        (null, 'expression'),
      ]);
      // release(<name>) is unwrapped so --assume NAME=<n> can resolve it.
      expect(fs.first.expr, 'flutter.minSdk');
      expect(fs.first.line, 2);
    });

    test('release(<ext name>) resolves through definitions', () {
      const text = 'def lo = 21\nandroid { minSdk { version = release(lo) } }\n';
      final fs = parseGradle(text, file: 'b.gradle');
      expect(fs.single.value, '21');
      expect(fs.single.expr, 'lo');
    });

    test('unclosed block with "{" at end of file does not throw', () {
      final fs = parseGradle('android {\n    compileSdk {', file: 'b.gradle');
      expect(fs.map((f) => f.reason), ['expression']);
    });

    test('unclosed block still reads the last character', () {
      final fs = parseGradle(
        'android {\n    compileSdk {\n        version = release(36)',
        file: 'b.gradle',
      );
      expect(fs.single.value, '36');
      expect(fs.single.line, 3);
    });

    test('values stay readable next to existing forms', () {
      expect(read('compileSdk = 35\nminSdk 21\ncompileSdkVersion(34)\n'), {
        'android.compileSdk': ('34', 3),
        'android.minSdk': ('21', 2),
      });
    });
  });
}
