import '../i18n/messages.dart';
import '../info.dart';
import '../model.dart';

String _loc(String file, int line) => '$file:$line';

/// Display width: Hangul and other wide characters take two columns.
int _width(String s) {
  var n = 0;
  for (final r in s.runes) {
    n +=
        (r >= 0x1100 && r <= 0x11FF) ||
            (r >= 0x2E80 && r <= 0xD7FF) ||
            (r >= 0xF900 && r <= 0xFAFF) ||
            (r >= 0xFE30 && r <= 0xFE6F) ||
            (r >= 0xFF00 && r <= 0xFF60) ||
            (r >= 0xFFE0 && r <= 0xFFE6)
        ? 2
        : 1;
  }
  return n;
}

String _pad(String s, int width) {
  final n = _width(s);
  return n >= width ? s : s + ' ' * (width - n);
}

/// Aligns [rows] into columns separated by two spaces (header is row 0).
List<String> _grid(List<List<String>> rows) {
  final cols = rows.first.length;
  final widths = [
    for (var c = 0; c < cols; c++)
      rows.map((r) => _width(r[c])).reduce((a, b) => a > b ? a : b),
  ];
  return [
    for (final r in rows)
      [
        for (var c = 0; c < cols; c++)
          c == cols - 1 ? r[c] : _pad(r[c], widths[c]),
      ].join('  '),
  ];
}

String _raisedBy(Finding f) => '${f.package} (${_loc(f.file, f.line)})';

/// Human-readable report: highest floors, findings with Fix hints, and (with
/// [all]) every plugin floor.
String renderTable(
  ScanReport r,
  Messages m, {
  required String appLabel,
  bool all = false,
}) {
  final b = StringBuffer();
  b.writeln(
    m.text(r.pluginNames.length == 1 ? 'table.title.one' : 'table.title', {
      'version': packageVersion,
      'plugins': '${r.pluginNames.length}',
      'app': appLabel,
    }),
  );
  b.writeln();

  b.writeln(m.text('table.floors'));
  final floors = <List<String>>[
    [
      m.text('table.col.target'),
      m.text('table.col.app'),
      m.text('table.col.required'),
      m.text('table.col.raisedBy'),
    ],
  ];
  for (final s in r.summaries) {
    floors.add([
      m.text('target.${s.target.id}'),
      s.app == null
          ? m.text('table.notFound')
          : s.app!.resolved
          ? s.app!.value!
          : m.text('table.unknown'),
      s.highest?.value ?? '-',
      s.highest == null ? '-' : _raisedBy(s.highest!),
    ]);
  }
  for (final line in _grid(floors)) {
    b.writeln('  $line');
  }
  b.writeln();

  b.writeln(m.text('table.findings'));
  if (r.violations.isEmpty) {
    b.writeln('  ${m.text('table.none')}');
  } else {
    final rows = <List<String>>[
      [
        m.text('table.col.rule'),
        m.text('table.col.level'),
        m.text('table.col.details'),
      ],
      for (final v in r.violations)
        [v.ruleId, m.text('sev.${v.severity}'), m.message(v)],
    ];
    final grid = _grid(rows);
    b.writeln('  ${grid.first}');
    for (var i = 0; i < r.violations.length; i++) {
      final v = r.violations[i];
      b.writeln('  ${grid[i + 1]}');
      if (v.file != null) b.writeln('    -> ${_loc(v.file!, v.line ?? 1)}');
      final fix = m.fix(v);
      if (fix != null) b.writeln('    ${m.text('table.fix', {'text': fix})}');
    }
  }
  b.writeln();
  b.writeln(
    m.text('table.counts', {
      'errors': '${r.count('error')}',
      'warnings': '${r.count('warning')}',
      'notes': '${r.count('note')}',
    }),
  );

  if (all) {
    b.writeln();
    b.writeln(m.text('table.all'));
    final rows = <List<String>>[
      [
        m.text('table.col.package'),
        m.text('table.col.target'),
        m.text('table.col.value'),
        m.text('table.col.source'),
        m.text('table.col.location'),
      ],
      for (final f in r.findings)
        [
          f.package ?? '',
          m.text('target.${f.target.id}'),
          f.resolved ? f.value! : '${m.text('table.unknown')} (${f.expr})',
          f.source.name,
          _loc(f.file, f.line),
        ],
    ];
    for (final line in _grid(rows)) {
      b.writeln('  $line');
    }
  }
  return b.toString();
}
