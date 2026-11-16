/// All user-visible text lives in the two maps below (English and Korean).
///
/// Placeholders use `{name}`. Both maps must have exactly the same keys
/// (`test/i18n_test.dart` checks this).
library;

import '../model.dart';

/// Message table for one language.
class Messages {
  Messages._(this.lang, this._table);

  /// `en` or `ko`.
  final String lang;
  final Map<String, String> _table;

  /// English messages.
  static final Messages en = Messages._('en', _en);

  /// Korean messages.
  static final Messages ko = Messages._('ko', _ko);

  /// Message keys (identical for both languages).
  static Set<String> get keys => _en.keys.toSet();

  /// Raw key set of a table, used by the key-parity test.
  Set<String> get tableKeys => _table.keys.toSet();

  /// Returns the table for `en` or `ko`.
  static Messages forLang(String lang) => lang == 'ko' ? ko : en;

  /// Looks up [key] and fills `{placeholders}` from [args].
  String text(String key, [Map<String, String> args = const {}]) {
    var s = _table[key] ?? _en[key] ?? key;
    args.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }

  /// Localized message of a violation.
  String message(Violation v) => text(v.messageKey, _args(v));

  /// Localized fix hint of a violation, or null.
  String? fix(Violation v) =>
      v.fixKey == null ? null : text(v.fixKey!, _args(v));

  Map<String, String> _args(Violation v) => {
    ...v.args,
    if (v.target != null) 'what': text('target.${v.target!.id}'),
    if (v.args['reason'] != null)
      'reasonText': text('reason.${v.args['reason']}'),
  };
}

/// Picks `en` or `ko`: `--lang` > `PLUGINFLOOR_LANG` > `LC_ALL` >
/// `LC_MESSAGES` > `LANG`. Anything that does not start with `ko` is English.
String resolveLang({String? cliLang, Map<String, String> env = const {}}) {
  if (cliLang != null) {
    if (cliLang == 'en' || cliLang == 'ko') return cliLang;
    throw PluginFloorException('error.badLang', {'value': cliLang});
  }
  final own = (env['PLUGINFLOOR_LANG'] ?? '').trim().toLowerCase();
  if (own.startsWith('ko')) return 'ko';
  if (own.startsWith('en')) return 'en';
  for (final name in const ['LC_ALL', 'LC_MESSAGES', 'LANG']) {
    final v = (env[name] ?? '').trim().toLowerCase();
    if (v.isEmpty) continue;
    return v.startsWith('ko') ? 'ko' : 'en';
  }
  return 'en';
}

const Map<String, String> _en = {
  // help
  'help.usage': 'Usage: pluginfloor [check] [app_dir] [options]',
  'help.summary':
      'Statically collects the Android minSdk/compileSdk and iOS/macOS '
      'deployment-target floors of every Flutter plugin and compares them '
      'with your app. No build tools or network needed.',
  'help.exit':
      'Exit codes: 0 no errors, 1 violations found (or warnings with --strict), '
      '2 usage or input error.',
  'opt.packageConfig':
      'Path to package_config.json (default: <app_dir>/.dart_tool/package_config.json).',
  'opt.assume':
      'Give a value to a name that cannot be resolved statically, e.g. '
      'flutter.minSdkVersion=21 (repeatable).',
  'opt.darwinPath':
      'Which Apple build path decides the floor: CocoaPods podspec, '
      'SwiftPM Package.swift, or the higher of both (default: both).',
  'opt.format': 'Report format (default: table).',
  'opt.output':
      'Write the report to this file (a one-line summary stays on stdout).',
  'opt.all': 'Also list every plugin floor, not only violations.',
  'opt.strict': 'Treat warnings (PF010, PF012) as failures (exit 1).',
  'opt.lang': 'Output language (default: PLUGINFLOOR_LANG, then LC_ALL/LANG).',
  'opt.version': 'Print the version.',
  'opt.help': 'Show this help.',
  // errors (exit code 2)
  'error.noAppDir': 'App directory not found: {path}',
  'error.noPackageConfig':
      'package_config.json not found at {path}. Run `flutter pub get` in the '
      'app first (or point to it with --package-config).',
  'error.badPackageConfig':
      'Cannot read {path}: {detail}. Run `flutter pub get` again to '
      'regenerate it.',
  'error.badFormat': "Invalid --format '{value}'. Use table, json or sarif.",
  'error.badDarwinPath':
      "Invalid --darwin-path '{value}'. Use cocoapods, spm or both.",
  'error.badAssume':
      "Invalid --assume '{value}'. Use KEY=VALUE with a numeric VALUE, for "
      'example flutter.minSdkVersion=21.',
  'error.badLang': "Invalid --lang '{value}'. Use en or ko.",
  'error.usage': '{detail}',
  'error.badOutput': 'Cannot write {path}: {detail}',
  // table report
  'table.title': 'pluginfloor {version} - {plugins} plugins scanned in {app}',
  'table.title.one':
      'pluginfloor {version} - {plugins} plugin scanned in {app}',
  'table.floors': 'Highest floor per target',
  'table.col.target': 'Target',
  'table.col.app': 'App',
  'table.col.required': 'Required',
  'table.col.raisedBy': 'Raised by',
  'table.findings': 'Findings',
  'table.col.rule': 'Rule',
  'table.col.level': 'Level',
  'table.col.details': 'Details',
  'table.none': 'No violations.',
  'table.counts': '{errors} error(s), {warnings} warning(s), {notes} note(s)',
  'table.all': 'All plugin floors',
  'table.col.package': 'Plugin',
  'table.col.value': 'Value',
  'table.col.source': 'Source',
  'table.col.location': 'Location',
  'table.unknown': 'unknown',
  'table.notFound': 'not found',
  'table.fix': 'Fix: {text}',
  'table.wrote':
      'Report written to {path} ({errors} error(s), {warnings} warning(s))',
  // labels
  'target.android.minSdk': 'android minSdk',
  'target.android.compileSdk': 'android compileSdk',
  'target.ios.deploymentTarget': 'iOS deployment target',
  'target.macos.deploymentTarget': 'macOS deployment target',
  'sev.error': 'error',
  'sev.warning': 'warning',
  'sev.note': 'note',
  'reason.flutter': 'set by the Flutter Gradle plugin at build time',
  'reason.rootProject': 'defined by the root Gradle project',
  'reason.ext': 'name not found in the Gradle files that could be read',
  'reason.expression': 'not a numeric literal',
  // rule messages
  'msg.violation': 'App {what} is {app} but {package} requires {required}.',
  'msg.PF010.plugin': '{package}: {what} is unknown ({expr} - {reasonText}).',
  'msg.PF010.app':
      'App {what} is unknown ({expr} - {reasonText}); plugin floors cannot be compared.',
  'msg.PF011':
      '{package}: {what} differs by build path - CocoaPods {pod}, SwiftPM {spm}.',
  'msg.PF012': 'App {what} was not found; plugin floors cannot be compared.',
  // fix hints
  'fix.raise': 'set {what} to {required} in {file}:{line}',
  'fix.raiseSpm':
      'set {what} to {required} in {file}:{line} and raise the Runner target in {pbx}',
  'fix.unresolved':
      'pass --assume {expr}=<number>, or set it in android/local.properties / the app file',
  'fix.unresolvedExpr':
      'write a plain number in the Gradle file, or pass --assume NAME=<number> for a named value',
  'fix.darwinPath':
      'choose the build path with --darwin-path cocoapods or --darwin-path spm',
  'fix.notFound': 'declare it in {hint}, or pass --assume',
  // rule titles (SARIF)
  'rule.PF001': 'Android minSdk below a plugin requirement',
  'rule.PF002': 'Android compileSdk below a plugin requirement',
  'rule.PF003': 'iOS deployment target below a plugin requirement',
  'rule.PF004': 'macOS deployment target below a plugin requirement',
  'rule.PF010': 'Value cannot be resolved statically',
  'rule.PF011': 'CocoaPods and SwiftPM floors differ',
  'rule.PF012': 'App value not found',
};

const Map<String, String> _ko = {
  'help.usage': '사용법: pluginfloor [check] [앱_폴더] [옵션]',
  'help.summary':
      '모든 Flutter 플러그인이 요구하는 Android minSdk/compileSdk 와 iOS/macOS '
      '배포 대상 하한을 정적으로 모아 앱 설정과 비교합니다. 빌드 도구도 '
      '네트워크도 필요 없습니다.',
  'help.exit': '종료 코드: 0 오류 없음, 1 위반 발견(--strict 면 경고 포함), 2 사용법·입력 오류.',
  'opt.packageConfig':
      'package_config.json 경로(기본: <앱_폴더>/.dart_tool/package_config.json).',
  'opt.assume':
      '정적으로 풀 수 없는 이름에 값을 지정합니다. 예: '
      'flutter.minSdkVersion=21 (여러 번 지정 가능).',
  'opt.darwinPath':
      '하한을 정할 Apple 빌드 경로: CocoaPods podspec, SwiftPM Package.swift, '
      '또는 둘 중 높은 값(기본: both).',
  'opt.format': '보고서 형식(기본: table).',
  'opt.output': '보고서를 이 파일에 씁니다(표준 출력에는 한 줄 요약만).',
  'opt.all': '위반뿐 아니라 모든 플러그인의 하한을 나열합니다.',
  'opt.strict': '경고(PF010, PF012)도 실패로 처리합니다(종료 코드 1).',
  'opt.lang': '출력 언어(기본: PLUGINFLOOR_LANG, 그다음 LC_ALL/LANG).',
  'opt.version': '버전을 출력합니다.',
  'opt.help': '이 도움말을 표시합니다.',
  'error.noAppDir': '앱 폴더를 찾을 수 없습니다: {path}',
  'error.noPackageConfig':
      '{path} 에 package_config.json 이 없습니다. 먼저 앱에서 `flutter pub get` 을 '
      '실행하세요(또는 --package-config 로 경로를 지정).',
  'error.badPackageConfig':
      '{path} 을(를) 읽을 수 없습니다: {detail}. `flutter pub get` 을 다시 '
      '실행해 파일을 새로 만드세요.',
  'error.badFormat':
      "--format '{value}' 이(가) 올바르지 않습니다. table, json, sarif 중 하나를 쓰세요.",
  'error.badDarwinPath':
      "--darwin-path '{value}' 이(가) 올바르지 않습니다. cocoapods, spm, both 중 하나를 쓰세요.",
  'error.badAssume':
      "--assume '{value}' 이(가) 올바르지 않습니다. 숫자 VALUE 를 가진 KEY=VALUE 형식으로 "
      '쓰세요. 예: flutter.minSdkVersion=21.',
  'error.badLang': "--lang '{value}' 이(가) 올바르지 않습니다. en 또는 ko 를 쓰세요.",
  'error.usage': '{detail}',
  'error.badOutput': '{path} 에 쓸 수 없습니다: {detail}',
  'table.title': 'pluginfloor {version} - {app} 에서 플러그인 {plugins}개 검사',
  'table.title.one': 'pluginfloor {version} - {app} 에서 플러그인 {plugins}개 검사',
  'table.floors': '대상별 가장 높은 하한',
  'table.col.target': '대상',
  'table.col.app': '앱',
  'table.col.required': '필요',
  'table.col.raisedBy': '원인',
  'table.findings': '발견 사항',
  'table.col.rule': '규칙',
  'table.col.level': '수준',
  'table.col.details': '내용',
  'table.none': '위반이 없습니다.',
  'table.counts': '오류 {errors}건, 경고 {warnings}건, 참고 {notes}건',
  'table.all': '모든 플러그인 하한',
  'table.col.package': '플러그인',
  'table.col.value': '값',
  'table.col.source': '출처',
  'table.col.location': '위치',
  'table.unknown': '알 수 없음',
  'table.notFound': '찾지 못함',
  'table.fix': '수정: {text}',
  'table.wrote': '보고서를 {path} 에 썼습니다(오류 {errors}건, 경고 {warnings}건)',
  'target.android.minSdk': '안드로이드 minSdk',
  'target.android.compileSdk': '안드로이드 compileSdk',
  'target.ios.deploymentTarget': 'iOS 배포 대상',
  'target.macos.deploymentTarget': 'macOS 배포 대상',
  'sev.error': '오류',
  'sev.warning': '경고',
  'sev.note': '참고',
  'reason.flutter': '빌드 시 Flutter Gradle 플러그인이 정하는 값',
  'reason.rootProject': '루트 Gradle 프로젝트가 정의하는 값',
  'reason.ext': '읽을 수 있는 Gradle 파일에서 이름을 찾지 못함',
  'reason.expression': '숫자 리터럴이 아님',
  'msg.violation':
      '앱의 {what} 은(는) {app} 인데 {package} 은(는) {required} 이상이 필요합니다.',
  'msg.PF010.plugin': '{package}: {what} 을(를) 알 수 없습니다({expr} - {reasonText}).',
  'msg.PF010.app':
      '앱의 {what} 을(를) 알 수 없어({expr} - {reasonText}) 플러그인 하한과 비교할 수 없습니다.',
  'msg.PF011':
      '{package}: {what} 이(가) 빌드 경로마다 다릅니다 - CocoaPods {pod}, SwiftPM {spm}.',
  'msg.PF012': '앱의 {what} 을(를) 찾지 못해 플러그인 하한과 비교할 수 없습니다.',
  'fix.raise': '{file}:{line} 에서 {what} 을(를) {required} 이상으로 올리세요',
  'fix.raiseSpm':
      '{file}:{line} 에서 {what} 을(를) {required} 이상으로 올리고 {pbx} 의 Runner 타깃도 올리세요',
  'fix.unresolved':
      '--assume {expr}=<숫자> 를 주거나 android/local.properties·앱 파일에 값을 적으세요',
  'fix.unresolvedExpr':
      'Gradle 파일에 숫자를 직접 적거나, 이름이 있는 값이면 --assume 이름=<숫자> 를 주세요',
  'fix.darwinPath':
      '--darwin-path cocoapods 또는 --darwin-path spm 으로 빌드 경로를 고르세요',
  'fix.notFound': '{hint} 에 값을 선언하거나 --assume 을 주세요',
  'rule.PF001': 'Android minSdk 가 플러그인 요구보다 낮음',
  'rule.PF002': 'Android compileSdk 가 플러그인 요구보다 낮음',
  'rule.PF003': 'iOS 배포 대상이 플러그인 요구보다 낮음',
  'rule.PF004': 'macOS 배포 대상이 플러그인 요구보다 낮음',
  'rule.PF010': '값을 정적으로 풀 수 없음',
  'rule.PF011': 'CocoaPods 와 SwiftPM 하한이 다름',
  'rule.PF012': '앱 값을 찾지 못함',
};
