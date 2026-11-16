import 'dart:convert';
import 'dart:io';

import 'package:pluginfloor/src/info.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('sample app: table shows the violations with Fix hints, exit 1', () {
    final r = cli(['check', 'example/sample_app', '--lang', 'en']);
    expect(r.code, 1);
    for (final s in [
      'PF001',
      'PF003',
      'PF004',
      'PF010',
      'PF011',
      'perm_guard_android',
      'face_scan_commons',
      'cloud_core',
      'Fix:',
    ]) {
      expect(r.out, contains(s));
    }
    expect(r.out, contains('perm_guard_android/android/build.gradle.kts:11'));
    expect(
      r.out,
      contains('App android minSdk is 21 but perm_guard_android requires 24.'),
    );
    expect(
      r.out,
      contains(
        'Fix: set android minSdk to 24 in android/app/build.gradle.kts:11',
      ),
    );
    expect(r.out, contains('cloud_core/macos/cloud_core/Package.swift:7'));
    expect(r.err, isEmpty);
  });

  test('passing fixture app exits 0 and says so', () {
    final r = cli(['check', 'test/fixtures/ok_app']);
    expect(r.code, 0);
    expect(r.out, contains('No violations.'));
  });

  test('the check word is optional and the app directory defaults to .', () {
    final a = cli(['example/sample_app']);
    final b = cli(['check', 'example/sample_app']);
    expect(a.out, b.out);
    expect(a.code, 1);
  });

  test('--all lists every plugin floor', () {
    final r = cli(['example/sample_app', '--all']);
    expect(r.out, contains('All plugin floors'));
    expect(r.out, contains('file_drop/android/src/main/AndroidManifest.xml:4'));
    expect(r.out, contains('unknown (flutter.compileSdkVersion)'));
  });

  test('--assume and --darwin-path change the result', () {
    final r = cli([
      'example/sample_app',
      '--assume',
      'flutter.compileSdkVersion=35',
      '--darwin-path',
      'cocoapods',
    ]);
    expect(r.out, contains('PF002'));
    expect(r.out, isNot(contains('PF010')));
    expect(r.out, contains('cloud_core requires 10.15'));
  });

  test('--format json prints JSON on stdout', () {
    final r = cli(['example/sample_app', '--format', 'json']);
    expect(r.code, 1);
    expect((jsonDecode(r.out) as Map)['schemaVersion'], 1);
  });

  test('--output writes the report and keeps a one-line summary on stdout', () {
    final tmp = Directory.systemTemp.createTempSync('pf_out_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final file = '${tmp.path}/report.sarif';
    final r = cli([
      'example/sample_app',
      '--format',
      'sarif',
      '--output',
      file,
    ]);
    expect(r.code, 1);
    expect(r.out.trim().split('\n'), hasLength(1));
    expect(r.out, contains('Report written to $file'));
    expect(
      (jsonDecode(File(file).readAsStringSync()) as Map)['version'],
      '2.1.0',
    );
  });

  test('--version and --help', () {
    expect(cli(['--version']).out, 'pluginfloor $packageVersion\n');
    final help = cli(['--help']);
    expect(help.code, 0);
    expect(help.out, contains('--darwin-path'));
    expect(help.out, contains('Exit codes'));
  });

  test('pubspec.yaml version matches the version constant', () {
    final text = File('pubspec.yaml').readAsStringSync();
    expect(
      RegExp(r'^version: (\S+)', multiLine: true).firstMatch(text)![1],
      packageVersion,
    );
  });

  test(
    'the installed executable path: bin/pluginfloor.dart exits 1 on the sample app',
    () {
      final r = Process.runSync(
        Platform.resolvedExecutable,
        ['bin/pluginfloor.dart', 'check', 'example/sample_app', '--lang', 'en'],
        environment: {'PLUGINFLOOR_LANG': 'ko'}, // --lang must win
      );
      expect(r.exitCode, 1);
      expect(r.stdout, contains('PF001'));
      expect(r.stdout, contains('Fix:'));
    },
  );

  test('ko table columns start at the same display offset (wide Hangul)', () {
    final r = cli(['example/sample_app', '--lang', 'ko', '--all']);
    int w(String t) => t.runes.fold(0, (n, c) => n + (c >= 0x1100 ? 2 : 1));
    final lines = r.out.split('\n');
    final head = lines.indexWhere(
      (l) => l.contains('플러그인') && l.contains('위치'),
    );
    expect(head, greaterThan(0));
    // Offset of the last column (the location, no spaces inside it).
    int lastCol(String l) => w(l.substring(0, l.lastIndexOf(' ') + 1));
    final expected = lastCol(lines[head]);
    var checked = 0;
    for (final l in lines.skip(head + 1).where((l) => l.startsWith('  '))) {
      expect(lastCol(l), expected, reason: l);
      checked++;
    }
    expect(checked, greaterThan(3));
  });

  test('help text carries the localized defaults, no English leftovers', () {
    final ko = cli(['--lang', 'ko', '-h']).out;
    expect(ko, contains('기본: both'));
    expect(ko, contains('기본: table'));
    expect(ko, isNot(contains('defaults to')));
    expect(cli(['-h']).out, contains('default: both'));
  });

  test('singular plugin count in the title', () {
    expect(cli(['test/fixtures/ok_app']).out, contains('1 plugin scanned'));
    expect(
      cli(['test/fixtures/ok_app']).out,
      isNot(contains('1 plugins scanned')),
    );
  });

  test('SwiftPM-sourced Apple violations also point at project.pbxproj', () {
    final r = cli(['example/sample_app', '--darwin-path', 'spm']);
    expect(r.out, contains('Runner.xcodeproj/project.pbxproj'));
  });
}
