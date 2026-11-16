/// Static Flutter plugin platform-floor audit.
///
/// The command line tool is the main product; this small API exists for tests
/// and reuse and is not stable before 1.0.
library;

export 'src/compare.dart' show DarwinPath;
export 'src/model.dart'
    show
        Finding,
        PluginFloorException,
        ScanReport,
        Source,
        Target,
        TargetSummary,
        Violation;
export 'src/scan.dart' show AppScanOptions, scanApp;
