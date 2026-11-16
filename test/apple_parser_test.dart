import 'package:pluginfloor/pluginfloor.dart';
import 'package:pluginfloor/src/apple_parser.dart';
import 'package:pluginfloor/src/package_resolver.dart';
import 'package:pluginfloor/src/scan.dart' show collectPluginFindings;
import 'package:test/test.dart';

/// (target, value, source, line)
typedef Row = (String, String?, String, int);

List<Row> rows(List<Finding> fs) => [
  for (final f in fs) (f.target.id, f.value, f.source.name, f.line),
];

void main() {
  group('podspec', () {
    test('platform-specific deployment targets and platform = :ios, x', () {
      const text = '''
Pod::Spec.new do |s|
  s.name = 'a'
  s.platform = :osx, '10.15'
  s.ios.deployment_target = '12.0'
  s.macos.deployment_target = "11.0"
end
''';
      expect(rows(parsePodspec(text, file: 'a.podspec', folder: 'ios')), [
        ('macos.deploymentTarget', '10.15', 'podspec', 3),
        ('ios.deploymentTarget', '12.0', 'podspec', 4),
        ('macos.deploymentTarget', '11.0', 'podspec', 5),
      ]);
    });

    test('a versionless platform line is ignored', () {
      const text = "s.platform = :ios\ns.ios.deployment_target = '13.0'\n";
      expect(rows(parsePodspec(text, file: 'a.podspec', folder: 'ios')), [
        ('ios.deploymentTarget', '13.0', 'podspec', 2),
      ]);
    });

    test('same-file duplicates merge into one finding (first line wins)', () {
      const text =
          "s.platform = :ios, '15.5'\ns.ios.deployment_target = '15.5'\n";
      final fs = parsePodspec(text, file: 'f.podspec', folder: 'ios');
      expect(rows(fs), [('ios.deploymentTarget', '15.5', 'podspec', 1)]);
    });

    test('different values in one file are both kept', () {
      const text =
          "s.ios.deployment_target = '12.0'\ns.platform = :ios, '13.0'\n";
      expect(
        parsePodspec(text, file: 'f.podspec', folder: 'ios'),
        hasLength(2),
      );
    });

    test('a plain deployment_target follows the folder; darwin means both', () {
      const text = "s.deployment_target = '12.0'\n";
      expect(rows(parsePodspec(text, file: 'x', folder: 'macos')), [
        ('macos.deploymentTarget', '12.0', 'podspec', 1),
      ]);
      expect(rows(parsePodspec(text, file: 'x', folder: 'darwin')), [
        ('ios.deploymentTarget', '12.0', 'podspec', 1),
        ('macos.deploymentTarget', '12.0', 'podspec', 1),
      ]);
    });

    test(
      'ruby expressions are unresolved, comments and other platforms ignored',
      () {
        const text =
            "# s.ios.deployment_target = '9.0'\ns.tvos.deployment_target = '9.0'\ns.ios.deployment_target = ios_version\n";
        final fs = parsePodspec(text, file: 'x', folder: 'ios');
        expect(rows(fs), [('ios.deploymentTarget', null, 'podspec', 3)]);
        expect(fs.single.resolved, isFalse);
      },
    );

    test('platforms hash form', () {
      const text = "s.platforms = { :ios => '12.0', :osx => '10.14' }\n";
      expect(rows(parsePodspec(text, file: 'x', folder: 'darwin')), [
        ('ios.deploymentTarget', '12.0', 'podspec', 1),
        ('macos.deploymentTarget', '10.14', 'podspec', 1),
      ]);
    });
  });

  group('Package.swift', () {
    test('string and enum forms', () {
      const text = '''
// swift-tools-version: 5.9
let package = Package(
    name: "x",
    platforms: [
        .iOS("13.0"),
        .macOS(.v10_15),
    ]
)
''';
      expect(rows(parsePackageSwift(text, file: 'P.swift')), [
        ('ios.deploymentTarget', '13.0', 'spm', 5),
        ('macos.deploymentTarget', '10.15', 'spm', 6),
      ]);
    });

    test('.iOS(.v13) and .iOS(.v15_5) become 13 and 15.5', () {
      const a = 'let p = Package(platforms: [.iOS(.v13)])\n';
      const b = 'let p = Package(platforms: [.iOS(.v15_5), .macOS(.v11)])\n';
      expect(parsePackageSwift(a, file: 'P').single.value, '13');
      expect(
        [for (final f in parsePackageSwift(b, file: 'P')) f.value],
        ['15.5', '11'],
      );
    });

    test('the platforms array can start after 700 lines', () {
      final text =
          '${'let filler = 1\n' * 700}let package = Package(\n    platforms: [\n        .iOS("14.0"),\n    ]\n)\n';
      final f = parsePackageSwift(text, file: 'P').single;
      expect((f.value, f.line), ('14.0', 703));
    });

    test('only entries inside platforms are read; comments ignored', () {
      const text =
          '// platforms: [.iOS("9.0")]\nlet x = Foo.iOS("1.0")\nlet p = Package(platforms: [.iOS("12.0")])\n';
      expect(rows(parsePackageSwift(text, file: 'P')), [
        ('ios.deploymentTarget', '12.0', 'spm', 3),
      ]);
    });

    test('non-literal entries are unresolved', () {
      final f = parsePackageSwift(
        'Package(platforms: [.iOS(minimumIOS)])',
        file: 'P',
      ).single;
      expect(f.resolved, isFalse);
    });
  });

  group('sample plugins (end to end)', () {
    PluginPackage pkg(String name) =>
        resolvePlugins('example/sample_app').firstWhere((p) => p.name == name);

    test('face_scan_commons has exactly one iOS finding', () {
      final fs = collectPluginFindings(pkg('face_scan_commons'));
      expect(rows(fs), [('ios.deploymentTarget', '15.5', 'podspec', 5)]);
      expect(fs.single.file, 'face_scan_commons/ios/face_scan_commons.podspec');
    });

    test('darwin/ values are assigned to both iOS and macOS', () {
      final fs = collectPluginFindings(pkg('snap_camera_darwin'));
      expect(
        fs.where((f) => f.target == Target.iosDeployment),
        hasLength(2),
      ); // podspec + spm
      expect(fs.where((f) => f.target == Target.macosDeployment), hasLength(2));
      expect(fs.every((f) => f.file.contains('/darwin/')), isTrue);
    });

    test('cloud_core: macOS podspec 10.15 and Package.swift 11.0', () {
      final fs = collectPluginFindings(
        pkg('cloud_core'),
      ).where((f) => f.target == Target.macosDeployment);
      expect(
        rows(fs.toList()),
        unorderedEquals([
          ('macos.deploymentTarget', '10.15', 'podspec', 5),
          ('macos.deploymentTarget', '11.0', 'spm', 7),
        ]),
      );
    });

    test('file_drop: .iOS(.v13) enum form', () {
      final fs = collectPluginFindings(
        pkg('file_drop'),
      ).where((f) => f.target == Target.iosDeployment);
      expect(rows(fs.toList()), [('ios.deploymentTarget', '13', 'spm', 7)]);
    });
  });
}
