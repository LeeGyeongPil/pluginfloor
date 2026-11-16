import 'dart:io';

import 'package:pluginfloor/src/cli.dart';

/// Result of an in-process CLI run.
class CliResult {
  CliResult(this.code, this.out, this.err);
  final int code;
  final String out;
  final String err;
}

/// Runs the CLI in-process with an empty environment (English) unless [env]
/// says otherwise.
CliResult cli(List<String> args, {Map<String, String> env = const {}}) {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = runCli(args, env: env, out: out, err: err);
  return CliResult(code, out.toString(), err.toString());
}

/// Writes [files] (relative path -> content) below [root].
void writeFiles(String root, Map<String, String> files) {
  files.forEach((rel, text) {
    final f = File('$root/$rel');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(text);
  });
}

/// Copies a directory tree.
void copyDir(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final e in from.listSync(followLinks: false)) {
    final name = e.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (e is Directory) {
      copyDir(e, Directory('${to.path}/$name'));
    } else if (e is File) {
      e.copySync('${to.path}/$name');
    }
  }
}

/// Copies `example/` (sample app + fake pub cache) into a fresh temp dir and
/// returns the temp root. Caller deletes it.
Directory copyExample() {
  final tmp = Directory.systemTemp.createTempSync('pluginfloor_');
  copyDir(Directory('example'), Directory('${tmp.path}/example'));
  return tmp;
}

/// Edits a file in place with a plain string replacement.
void replaceIn(String path, String from, String to) {
  final f = File(path);
  final text = f.readAsStringSync();
  if (!text.contains(from)) throw StateError('"$from" not found in $path');
  f.writeAsStringSync(text.replaceFirst(from, to));
}
