# Output schema

## Exit codes

| Code | Meaning |
|---|---|
| 0 | No errors (warnings and notes do not fail unless `--strict` turns warnings into failures) |
| 1 | At least one error (PF001-PF004), or a warning (PF010, PF012) with `--strict` |
| 2 | Usage or input error (missing or malformed `package_config.json`, bad option value, unwritable `--output`) |

## Rules

| ID | Severity | Meaning |
|---|---|---|
| PF001 | error | App `minSdk` is below a plugin's `minSdk` |
| PF002 | error | App `compileSdk` is below a plugin's `compileSdk` |
| PF003 | error | App iOS deployment target is below a plugin's |
| PF004 | error | App macOS deployment target is below a plugin's |
| PF010 | warning | A value cannot be resolved statically (`flutter.minSdkVersion`, `rootProject.ext.x`, Ruby expressions, ...). Plugin values that use the same expression as the app are not reported because they cannot exceed it |
| PF011 | note | A plugin's CocoaPods (podspec) and SwiftPM (`Package.swift`) floors differ |
| PF012 | warning | The app's own value was not found, so plugin floors cannot be compared |

One PF001-PF004 violation is reported per offending plugin (its highest value for that target).

## JSON (`--format json`)

```text
{
  "schemaVersion": 1,
  "tool": {"name", "version"},
  "plugins": ["name", ...],                 // sorted
  "targets": [{"target", "app": Finding|null, "highest": Finding|null}],
  "violations": [{"ruleId", "severity", "target", "package", "required", "app",
                  "message", "fix", "location": {"file","line"}, "appLocation": {"file","line"}}],
  "findings": [Finding],                    // every plugin-side value
  "unresolved": [Finding + "benign"]        // values that could not be resolved
}
Finding = {"package", "target", "source", "expr", "value", "resolved",
           "assumed"?, "reason"?, "file", "line", "via"?: {"file","line"}}
```

* `target` is one of `android.minSdk`, `android.compileSdk`, `ios.deploymentTarget`, `macos.deploymentTarget`.
* `source` is `gradle`, `manifest`, `podspec`, `spm` or `app`.
* `file` is app-relative for app values and `<package>/<path inside the package>` for plugin values. No absolute paths are ever written.
* Only `message` and `fix` depend on `--lang`; every other field is language independent.
* Output is deterministic: same inputs give byte-identical output.

## SARIF (`--format sarif`)

SARIF 2.1.0. `runs[0].tool.driver.rules` lists PF001-PF004, PF010-PF012. Each result has `ruleId`, `level` (`error`, `warning`, `note`), `message.text`, and `locations[0].physicalLocation` with `artifactLocation.uri` and `region.startLine`. For floor violations the primary location is the app file to change; the plugin file that raises the floor is in `relatedLocations`.
