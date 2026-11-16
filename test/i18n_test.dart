import 'dart:convert';
import 'dart:io';

import 'package:pluginfloor/pluginfloor.dart';
import 'package:pluginfloor/src/i18n/messages.dart';
import 'package:pluginfloor/src/report/json.dart';
import 'package:pluginfloor/src/report/sarif.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Set<String> placeholders(String s) =>
    RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m[1]!).toSet();

final hangul = RegExp(r'[가-힣]');

void main() {
  group('message tables', () {
    test('English and Korean have exactly the same keys', () {
      expect(Messages.ko.tableKeys, Messages.en.tableKeys);
      expect(Messages.en.tableKeys, Messages.keys);
    });

    test('placeholders match between languages for every key', () {
      for (final k in Messages.keys) {
        expect(
          placeholders(Messages.ko.text(k)),
          placeholders(Messages.en.text(k)),
          reason: k,
        );
      }
    });

    test('Korean texts contain Hangul and English ones do not', () {
      for (final k in Messages.keys.where(
        (k) => !k.startsWith('error.usage'),
      )) {
        expect(hangul.hasMatch(Messages.en.text(k)), isFalse, reason: k);
      }
      expect(hangul.hasMatch(Messages.ko.text('table.none')), isTrue);
    });
  });

  group('language selection', () {
    test('--lang beats everything', () {
      expect(
        resolveLang(
          cliLang: 'en',
          env: {'PLUGINFLOOR_LANG': 'ko', 'LANG': 'ko_KR.UTF-8'},
        ),
        'en',
      );
      expect(resolveLang(cliLang: 'ko', env: {'PLUGINFLOOR_LANG': 'en'}), 'ko');
    });

    test('PLUGINFLOOR_LANG beats LC_ALL / LANG', () {
      expect(
        resolveLang(env: {'PLUGINFLOOR_LANG': 'ko', 'LANG': 'en_US.UTF-8'}),
        'ko',
      );
      expect(
        resolveLang(env: {'PLUGINFLOOR_LANG': 'en', 'LANG': 'ko_KR.UTF-8'}),
        'en',
      );
    });

    test('locale variables: LC_ALL > LC_MESSAGES > LANG', () {
      expect(resolveLang(env: {'LANG': 'ko_KR.UTF-8'}), 'ko');
      expect(
        resolveLang(env: {'LC_MESSAGES': 'ko_KR.UTF-8', 'LANG': 'en_US.UTF-8'}),
        'ko',
      );
      expect(
        resolveLang(
          env: {'LC_ALL': 'en_US.UTF-8', 'LC_MESSAGES': 'ko_KR.UTF-8'},
        ),
        'en',
      );
    });

    test('anything else is English', () {
      for (final env in [
        <String, String>{},
        {'LANG': 'fr_FR.UTF-8'},
        {'LANG': 'C'},
        {'LANG': ''},
        {'PLUGINFLOOR_LANG': 'xx'},
      ]) {
        expect(resolveLang(env: env), 'en', reason: '$env');
      }
    });

    test('an unsupported --lang is an error', () {
      expect(
        () => resolveLang(cliLang: 'fr'),
        throwsA(isA<PluginFloorException>()),
      );
    });
  });

  group('CLI output', () {
    test('--lang ko vs --lang en: help, headers, messages and Fix hints', () {
      final ko = cli(['example/sample_app', '--lang', 'ko']);
      final en = cli(['example/sample_app', '--lang', 'en']);
      expect(ko.code, 1);
      expect(en.code, 1);
      for (final s in ['PF001', 'PF003', 'PF004']) {
        expect(ko.out, contains(s));
        expect(en.out, contains(s));
      }
      expect(ko.out, contains('대상'));
      expect(ko.out, contains('필요'));
      expect(ko.out, contains('앱의 안드로이드 minSdk'));
      expect(ko.out, contains('수정:'));
      expect(ko.out, isNot(contains('Fix:')));
      expect(en.out, contains('Target'));
      expect(en.out, contains('Required'));
      expect(en.out, contains('Fix:'));
      expect(hangul.hasMatch(en.out), isFalse);
      final enHelp = cli(['--help', '--lang', 'en']);
      final koHelp = cli(['--help', '--lang', 'ko']);
      expect(enHelp.out, contains('Usage:'));
      expect(koHelp.out, contains('사용법:'));
      expect(hangul.hasMatch(enHelp.out), isFalse);
    });

    test('PLUGINFLOOR_LANG=ko and LANG=ko_KR.UTF-8 select Korean', () {
      expect(
        cli(['example/sample_app'], env: {'PLUGINFLOOR_LANG': 'ko'}).out,
        contains('수정:'),
      );
      expect(
        cli(['example/sample_app'], env: {'LANG': 'ko_KR.UTF-8'}).out,
        contains('수정:'),
      );
    });

    test(
      '--lang overrides the environment; other locales fall back to English',
      () {
        expect(
          cli(
            ['example/sample_app', '--lang', 'en'],
            env: {'PLUGINFLOOR_LANG': 'ko'},
          ).out,
          contains('Fix:'),
        );
        expect(
          cli(['example/sample_app'], env: {'LANG': 'de_DE.UTF-8'}).out,
          contains('Fix:'),
        );
      },
    );

    test('error messages are localized too (exit 2)', () {
      final r = cli(['example/sample_app', '--format', 'xml', '--lang', 'ko']);
      expect(r.code, 2);
      expect(r.err, contains('올바르지 않습니다'));
    });

    test(
      'the sample app command from the README prints Korean text with PF001',
      () {
        final r = Process.runSync(Platform.resolvedExecutable, [
          'bin/pluginfloor.dart',
          'check',
          'example/sample_app',
          '--lang',
          'ko',
        ]);
        expect(r.exitCode, 1);
        expect(r.stdout, contains('PF001'));
        expect(hangul.hasMatch(r.stdout as String), isTrue);
      },
    );
  });

  group('JSON and SARIF are language independent', () {
    final report = scanApp(AppScanOptions(appDir: 'example/sample_app'));

    Map<String, dynamic> j(Messages m) =>
        jsonDecode(renderJson(report, m)) as Map<String, dynamic>;

    test('rule IDs and field names are the same, only text differs', () {
      final en = j(Messages.en);
      final ko = j(Messages.ko);
      List<Map<String, dynamic>> v(Map<String, dynamic> d) =>
          (d['violations'] as List).cast<Map<String, dynamic>>();
      expect(v(ko).map((x) => x['ruleId']), v(en).map((x) => x['ruleId']));
      expect(v(ko).first.keys, v(en).first.keys);
      expect(ko['targets'], en['targets']);
      expect(ko['findings'], en['findings']);
      expect(v(ko).first['message'], isNot(v(en).first['message']));
      expect(hangul.hasMatch(v(ko).first['message'] as String), isTrue);
      expect(hangul.hasMatch(v(en).first['message'] as String), isFalse);
    });

    test('SARIF rule IDs and structure are the same in both languages', () {
      Map<String, dynamic> s(Messages m) =>
          jsonDecode(renderSarif(report, m)) as Map<String, dynamic>;
      List<Object?> ids(Map<String, dynamic> d) {
        final run = (d['runs'] as List).single as Map<String, dynamic>;
        return [for (final r in run['results'] as List) (r as Map)['ruleId']];
      }

      expect(ids(s(Messages.ko)), ids(s(Messages.en)));
      expect(s(Messages.ko).keys, s(Messages.en).keys);
    });
  });
}
