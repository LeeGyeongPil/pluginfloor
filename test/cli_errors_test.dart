import 'dart:io';

import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('pf_err_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  void expectUsageError(CliResult r, String substring) {
    expect(r.code, 2);
    expect(r.out, isEmpty);
    expect(r.err, contains(substring));
    expect(r.err, isNot(contains('#0')));
    expect(r.err, isNot(contains('Exception')));
    expect(r.err, isNot(contains('StackTrace')));
  }

  test('missing package_config.json -> exit 2 with a flutter pub get hint', () {
    final r = cli([tmp.path]);
    expectUsageError(r, 'flutter pub get');
    expect(r.err, contains('package_config.json'));
  });

  test('missing app directory', () {
    expectUsageError(cli(['${tmp.path}/nope']), 'App directory not found');
  });

  test('invalid --format', () {
    final r = cli(['example/sample_app', '--format', 'xml']);
    expectUsageError(r, "Invalid --format 'xml'");
    expect(r.err, contains('table, json or sarif'));
  });

  test('malformed --assume values', () {
    for (final bad in ['foo', 'a=', '=1', 'a=b', 'a=1.x']) {
      expectUsageError(
        cli(['example/sample_app', '--assume', bad]),
        "Invalid --assume '$bad'",
      );
    }
  });

  test('invalid --darwin-path and --lang', () {
    expectUsageError(
      cli(['example/sample_app', '--darwin-path', 'xcode']),
      'Invalid --darwin-path',
    );
    expectUsageError(
      cli(['example/sample_app', '--lang', 'fr']),
      "Invalid --lang 'fr'",
    );
  });

  test('unknown option and extra arguments', () {
    expect(cli(['example/sample_app', '--nope']).code, 2);
    expect(cli(['a', 'b']).code, 2);
    expect(cli(['example/sample_app', '--format']).code, 2);
  });

  test('malformed package_config.json -> exit 2 without a stack trace', () {
    writeFiles(tmp.path, {
      '.dart_tool/package_config.json':
          '{"configVersion": 2, "packages": [oops',
    });
    final r = cli([tmp.path]);
    expectUsageError(r, 'Cannot read');
    expect(r.err, contains('flutter pub get'));
  });

  test('package_config.json without a packages list -> exit 2', () {
    writeFiles(tmp.path, {
      '.dart_tool/package_config.json': '{"configVersion": 2}',
    });
    expectUsageError(cli([tmp.path]), 'packages');
    writeFiles(tmp.path, {'.dart_tool/package_config.json': '[1,2]'});
    expectUsageError(cli([tmp.path]), 'Cannot read');
  });

  test('--output to an unwritable path -> exit 2', () {
    expectUsageError(
      cli(['example/sample_app', '--output', '${tmp.path}/no/such/dir/r.txt']),
      'Cannot write',
    );
  });

  test('--strict turns an app with only PF010 into exit 1', () {
    final relaxed = cli(['test/fixtures/warn_app']);
    expect(relaxed.code, 0);
    expect(relaxed.out, contains('PF010'));
    expect(relaxed.out, contains('1 warning(s)'));
    expect(relaxed.out, contains('0 error(s)'));
    final strict = cli(['test/fixtures/warn_app', '--strict']);
    expect(strict.code, 1);
  });

  test('--strict does not fail on notes alone', () {
    expect(cli(['test/fixtures/ok_app', '--strict']).code, 0);
  });

  test('an empty plugin list is fine', () {
    writeFiles(tmp.path, {
      'pubspec.yaml': 'name: bare\n',
      '.dart_tool/package_config.json':
          '{"configVersion":2,"packages":[{"name":"bare","rootUri":"../","packageUri":"lib/"}]}',
    });
    final r = cli([tmp.path]);
    expect(r.code, 0);
    expect(r.out, contains('0 plugins scanned'));
  });
}
