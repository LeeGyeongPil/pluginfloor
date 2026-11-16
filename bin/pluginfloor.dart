import 'dart:io';

import 'package:pluginfloor/src/cli.dart';

void main(List<String> args) {
  exitCode = runCli(args, env: Platform.environment, out: stdout, err: stderr);
}
