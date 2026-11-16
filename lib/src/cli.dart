import 'dart:io';

import 'package:args/args.dart';

import 'compare.dart';
import 'i18n/messages.dart';
import 'info.dart';
import 'model.dart';
import 'report/json.dart';
import 'report/sarif.dart';
import 'report/table.dart';
import 'scan.dart';

ArgParser _buildParser(Messages m) {
  return ArgParser(usageLineLength: 100)
    ..addOption(
      'package-config',
      valueHelp: 'path',
      help: m.text('opt.packageConfig'),
    )
    ..addMultiOption(
      'assume',
      valueHelp: 'KEY=VALUE',
      help: m.text('opt.assume'),
    )
    ..addOption(
      'darwin-path',
      valueHelp: 'cocoapods|spm|both',
      help: m.text('opt.darwinPath'),
    )
    ..addOption(
      'format',
      valueHelp: 'table|json|sarif',
      help: m.text('opt.format'),
    )
    ..addOption('output', valueHelp: 'file', help: m.text('opt.output'))
    ..addFlag('all', negatable: false, help: m.text('opt.all'))
    ..addFlag('strict', negatable: false, help: m.text('opt.strict'))
    ..addOption('lang', valueHelp: 'en|ko', help: m.text('opt.lang'))
    ..addFlag('version', negatable: false, help: m.text('opt.version'))
    ..addFlag('help', abbr: 'h', negatable: false, help: m.text('opt.help'));
}

/// `--lang` is needed before the parser (and its help text) can be built.
String? _scanLang(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--lang' && i + 1 < args.length) return args[i + 1];
    if (a.startsWith('--lang=')) return a.substring('--lang='.length);
  }
  return null;
}

final RegExp _assumeRe = RegExp(r'^([^=\s]+)=(\d+(?:\.\d+)*)$');

/// Runs the command line tool and returns its exit code.
///
/// Exit codes: 0 no errors, 1 violations (or warnings with `--strict`),
/// 2 usage or input error. [env] is used for language detection.
int runCli(
  List<String> args, {
  Map<String, String> env = const {},
  required StringSink out,
  required StringSink err,
}) {
  Messages m = Messages.en;
  try {
    m = Messages.forLang(resolveLang(cliLang: _scanLang(args), env: env));
    return _run(args, m, out, err);
  } on PluginFloorException catch (e) {
    err.writeln('pluginfloor: ${m.text(e.key, e.args)}');
    return 2;
  }
}

int _run(List<String> args, Messages m, StringSink out, StringSink err) {
  final parser = _buildParser(m);
  final ArgResults res;
  try {
    res = parser.parse(args);
  } on FormatException catch (e) {
    throw PluginFloorException('error.usage', {'detail': e.message});
  }
  if (res.flag('help')) {
    out.writeln(m.text('help.usage'));
    out.writeln();
    out.writeln(m.text('help.summary'));
    out.writeln();
    out.writeln(parser.usage);
    out.writeln();
    out.writeln(m.text('help.exit'));
    return 0;
  }
  if (res.flag('version')) {
    out.writeln('pluginfloor $packageVersion');
    return 0;
  }

  final rest = [...res.rest];
  if (rest.isNotEmpty && rest.first == 'check') rest.removeAt(0);
  if (rest.length > 1) {
    throw PluginFloorException('error.usage', {
      'detail': 'Unexpected argument: ${rest[1]}',
    });
  }
  final appDir = rest.isEmpty ? '.' : rest.first;

  final format = res.option('format') ?? 'table';
  if (!const {'table', 'json', 'sarif'}.contains(format)) {
    throw PluginFloorException('error.badFormat', {'value': format});
  }
  final darwinArg = res.option('darwin-path') ?? 'both';
  final darwin = DarwinPath.tryParse(darwinArg);
  if (darwin == null) {
    throw PluginFloorException('error.badDarwinPath', {'value': darwinArg});
  }
  final assume = <String, String>{};
  for (final a in res.multiOption('assume')) {
    final match = _assumeRe.firstMatch(a);
    if (match == null) {
      throw PluginFloorException('error.badAssume', {'value': a});
    }
    assume[match[1]!] = match[2]!;
  }

  final report = scanApp(
    AppScanOptions(
      appDir: appDir,
      packageConfig: res.option('package-config'),
      assume: assume,
      darwinPath: darwin,
    ),
  );

  final text = switch (format) {
    'json' => renderJson(report, m),
    'sarif' => renderSarif(report, m),
    _ => renderTable(report, m, appLabel: appDir, all: res.flag('all')),
  };
  final output = res.option('output');
  if (output == null) {
    out.write(text);
  } else {
    try {
      File(output).writeAsStringSync(text);
    } on FileSystemException catch (e) {
      throw PluginFloorException('error.badOutput', {
        'path': output,
        'detail': e.message,
      });
    }
    out.writeln(
      m.text('table.wrote', {
        'path': output,
        'errors': '${report.count('error')}',
        'warnings': '${report.count('warning')}',
      }),
    );
  }
  return report.exitCode(strict: res.flag('strict'));
}
