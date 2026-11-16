import 'package:pluginfloor/src/version.dart';
import 'package:test/test.dart';

void main() {
  Version v(String s) => Version.tryParse(s)!;

  test('compares components as integers, not decimals', () {
    expect(v('10.15') > v('10.9'), isTrue);
    expect(v('10.9') < v('10.15'), isTrue);
    expect(v('15.5') > v('15'), isTrue);
    expect(v('11') > v('10.15'), isTrue);
  });

  test('missing components count as zero', () {
    expect(v('15') == v('15.0'), isTrue);
    expect(v('15.0.0').compareTo(v('15')), 0);
    expect(v('15').hashCode, v('15.0').hashCode);
  });

  test('keeps the original text', () {
    expect(v('13.0').toString(), '13.0');
  });

  test('rejects non-numeric text', () {
    for (final bad in [
      '',
      'flutter.minSdkVersion',
      '1..2',
      'v13',
      '10.',
      '-1',
    ]) {
      expect(Version.tryParse(bad), isNull, reason: bad);
      expect(Version.isLiteral(bad), isFalse, reason: bad);
    }
    expect(Version.isLiteral(' 21 '), isTrue);
  });
}
