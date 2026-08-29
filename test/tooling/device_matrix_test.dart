// Device matrix + device lab gate (E12-R13).
//
// Follows the `test/tooling/repository_policy_test.dart` (ADR 0444) and
// `test/tooling/release_manifest_test.dart` (ADR 0447) pattern: a single
// gate test file with content-parameterized checker functions (ADR 0444 D6,
// so fixtures AND the real file share the same code path), a restricted
// hand-rolled YAML-subset reader (R3 — `package:yaml` is transitive-only on
// this tree, pubspec.lock:1261, and importing it would turn `flutter
// analyze` red via `depend_on_referenced_packages`), and — for the Python
// report generator — `Process.runSync('python3', …)` on temporary fixture
// directories, the ONLY external binary this file is allowed to invoke
// (R4, L110).
//
// L527 shapes the self-guard group (A8) below: a "no external process"
// guard that only greps its own source for `Process.run` is blind to
// `Process.start`, which does not share that prefix. This file legitimately
// spawns `python3` via `Process.runSync`, so A8 asserts the *set* of
// executables this file's `Process.(run|runSync|start)(...)` calls target
// is exactly `{python3}` — covering all three entry points with one regex,
// split across adjacent string literals so this file's own definition of
// the regex does not match itself.
//
// L546 shapes the A1 group: the brief's falsification matrix names a
// specific hibaosztály ("ram_gb: unknown" slips through) and the review
// checks the *direction* of the `expect`, not just that a cell with a
// matching name exists. The A1 group below walks the FULL placeholder list
// (`identifierPlaceholderValues`) against EVERY one of the eleven identifier
// fields, not one representative example.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _matrixPath = 'docs/testing/device-matrix.yaml';

// ---------------------------------------------------------------------------
// Closed dictionaries (R6, R7) — the schema's only source of truth for valid
// capability ids and required-suite element names. A value outside these
// sets is unknown, not a typo to route around.
// ---------------------------------------------------------------------------

/// SDD Ch12 §5.1 Core Learning Scope + §5.4 GA scope rule — the eleven
/// capabilities General Availability requires a release-blocking device for
/// (docs/sdd/12-release-roadmap-final-integration.md:259-311).
const List<String> gaScopeCapabilityIds = [
  'onboarding',
  'live_and_tuner',
  'practice_engine',
  'song_trainer_local',
  'audio_analysis_core',
  'progress_goals_streak',
  'storage_migration',
  'offline_operation',
  'localization_en_hu',
  'accessibility_minimum',
  'session_lifecycle_stability',
];

/// SDD Ch12 §5.2 Intelligent Coaching Scope ("preview") — informational,
/// never gates GA (docs/sdd/12-release-roadmap-final-integration.md:276-286).
const List<String> nonGaScopeCapabilityIds = [
  'computer_vision',
  'offline_ai',
  'ai_tutor',
];

/// SDD Ch12 §18.2 mandatory per-device measurements
/// (docs/sdd/12-release-roadmap-final-integration.md:1091-1105). Fourteen
/// entries — `local_ai_load_ttft` is a valid dictionary entry but, per §18.2
/// "ha támogatott" and the Offline AI `not_ga_scope` status (R6), no device
/// requires it today; device-lab.md §4 states this explicitly.
const List<String> requiredSuiteCatalogIds = [
  'install_and_update',
  'cold_start',
  'live_start_latency',
  'mic_release',
  'practice_soak_20min',
  'analyze_memory_peak',
  'camera_preview_and_thermal',
  'local_ai_load_ttft',
  'background_resume',
  'battery_saver',
  'airplane_mode',
  'low_storage',
  'text_scale_200',
  'screen_reader_path',
];

/// E12-R12's measured lesson (L546): placeholder identifier values, walked
/// as a full, exported list — not one representative example.
const List<String> identifierPlaceholderValues = [
  'unknown',
  'n/a',
  'tbd',
  '?',
  '',
  'pending',
];

/// The eleven identifier/provenance fields A1 requires present and
/// placeholder-free on every device (§5.4). `spec_provenance` was added by
/// the independent review's F2 finding (docs/reviews/e12-r13-review.md): the
/// measured source for `ram_gb`/`soc` is `vision-performance-benchmark.md`,
/// not `provenance` (which only carries the camera-spec source).
const List<String> identifierFieldNames = [
  'id',
  'name',
  'os',
  'api_level',
  'ram_gb',
  'abi',
  'soc',
  'release_blocking',
  'provenance',
  'spec_provenance',
];

/// SDD Ch12 §18.2 mandatory per-device measurements minus `local_ai_load_ttft`
/// (R7 — no device requires it today, Offline AI being `not_ga_scope`). This
/// is the thirteen-item dictionary every `release_blocking: true` device's
/// `required_suite` must fully cover (independent review F1 —
/// docs/reviews/e12-r13-review.md: an emptied or partial `required_suite`
/// on a blocking device must turn a cell red, not merely satisfy A2's
/// "capability has a blocking device" check with nothing behind it).
final List<String> mandatoryRequiredSuiteIds = requiredSuiteCatalogIds
    .where((id) => id != 'local_ai_load_ttft')
    .toList();

bool isPlaceholderValue(String raw) =>
    identifierPlaceholderValues.contains(raw.trim().toLowerCase());

// ---------------------------------------------------------------------------
// Restricted device-matrix YAML subset (R3, ADR 0444 D3 precedent).
// ---------------------------------------------------------------------------

/// One parsed `devices:` element.
final class DeviceEntry {
  const DeviceEntry({
    required this.id,
    required this.name,
    required this.os,
    required this.apiLevel,
    required this.ramGb,
    required this.abi,
    required this.soc,
    required this.cameraSpec,
    required this.cameraResult,
    required this.audioResult,
    required this.visionTier,
    required this.offlineAiTier,
    required this.coreSupport,
    required this.releaseBlocking,
    required this.requiredSuite,
    required this.provenance,
    required this.specProvenance,
    required this.lineNumber,
  });

  final String id;
  final String name;
  final String os;
  final String apiLevel;
  final String ramGb;
  final String abi;
  final String soc;
  final String cameraSpec;
  final String cameraResult;
  final String audioResult;
  final String visionTier;
  final String offlineAiTier;
  final String coreSupport;
  final String releaseBlocking;
  final List<String> requiredSuite;
  final String provenance;
  final String specProvenance;
  final int lineNumber;

  bool get releaseBlockingValue =>
      releaseBlocking.trim().toLowerCase() == 'true';

  /// The eleven A1 identifier fields, keyed by their YAML field name — kept
  /// as RAW strings (not parsed ints/bools) so a placeholder given to a
  /// numeric or boolean field is caught the exact same way a text field is.
  Map<String, String> get identifierFields => {
    'id': id,
    'name': name,
    'os': os,
    'api_level': apiLevel,
    'ram_gb': ramGb,
    'abi': abi,
    'soc': soc,
    'release_blocking': releaseBlocking,
    'provenance': provenance,
    'spec_provenance': specProvenance,
  };
}

/// One parsed `capabilities:` element.
final class CapabilityEntry {
  const CapabilityEntry({
    required this.id,
    required this.gaScope,
    required this.devices,
    required this.lineNumber,
  });

  final String id;
  final String gaScope;
  final List<String> devices;
  final int lineNumber;

  bool get gaScopeValue => gaScope.trim().toLowerCase() == 'true';
}

/// A parsed `docs/testing/device-matrix.yaml` document.
final class DeviceMatrix {
  const DeviceMatrix({
    required this.schemaVersion,
    required this.devices,
    required this.capabilities,
    required this.requiredSuiteCatalog,
  });

  final int schemaVersion;
  final List<DeviceEntry> devices;
  final List<CapabilityEntry> capabilities;
  final List<String> requiredSuiteCatalog;
}

bool _isBlankOrComment(String line) {
  final trimmed = line.trim();
  return trimmed.isEmpty || trimmed.startsWith('#');
}

final _topLevelKeyLine = RegExp(r'^([a-zA-Z_]+):\s*(.*)$');
final _listElementHeader = RegExp(r'^ {2}- ([a-zA-Z_]+):\s*(.*)$');
final _fourSpaceKeyLine = RegExp(r'^ {4}([a-zA-Z_]+):\s*(.*)$');

List<String> _parseInlineList(
  String rest, {
  required String sourceLabel,
  required int lineNumber,
}) {
  final trimmed = rest.trim();
  if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) {
    throw FormatException(
      '$sourceLabel:$lineNumber: expected an inline "[a, b]" list, got: '
      '"$rest"',
    );
  }
  final inner = trimmed.substring(1, trimmed.length - 1).trim();
  if (inner.isEmpty) return const [];
  return inner.split(',').map((item) => item.trim()).toList();
}

const _deviceFieldKeys = {
  'id',
  'name',
  'os',
  'api_level',
  'ram_gb',
  'abi',
  'soc',
  'camera_spec',
  'camera_result',
  'audio_result',
  'vision_tier',
  'offline_ai_tier',
  'core_support',
  'release_blocking',
  'required_suite',
  'provenance',
  'spec_provenance',
};

const _capabilityFieldKeys = {'id', 'ga_scope', 'devices'};

int _parseDeviceElements(
  List<String> lines,
  int start,
  String sourceLabel,
  List<DeviceEntry> devices,
) {
  var i = start;
  while (i < lines.length) {
    if (_isBlankOrComment(lines[i])) {
      i++;
      continue;
    }
    if (!lines[i].startsWith('  -')) break;
    final header = _listElementHeader.firstMatch(lines[i]);
    if (header == null || header.group(1) != 'id') {
      throw FormatException(
        '$sourceLabel:${i + 1}: expected a device element "  - id: <value>", '
        'got: "${lines[i]}"',
      );
    }
    final elementLine = i + 1;
    final fields = <String, String>{'id': header.group(2)!.trim()};
    i++;
    while (i < lines.length && _fourSpaceKeyLine.hasMatch(lines[i])) {
      final match = _fourSpaceKeyLine.firstMatch(lines[i])!;
      final key = match.group(1)!;
      final lineNumber = i + 1;
      if (!_deviceFieldKeys.contains(key)) {
        throw FormatException(
          '$sourceLabel:$lineNumber: unsupported device field "$key"',
        );
      }
      fields[key] = match.group(2)!.trim();
      i++;
    }
    devices.add(
      DeviceEntry(
        id: fields['id'] ?? '',
        name: fields['name'] ?? '',
        os: fields['os'] ?? '',
        apiLevel: fields['api_level'] ?? '',
        ramGb: fields['ram_gb'] ?? '',
        abi: fields['abi'] ?? '',
        soc: fields['soc'] ?? '',
        cameraSpec: fields['camera_spec'] ?? '',
        cameraResult: fields['camera_result'] ?? '',
        audioResult: fields['audio_result'] ?? '',
        visionTier: fields['vision_tier'] ?? '',
        offlineAiTier: fields['offline_ai_tier'] ?? '',
        coreSupport: fields['core_support'] ?? '',
        releaseBlocking: fields['release_blocking'] ?? '',
        requiredSuite: fields['required_suite'] == null
            ? const []
            : _parseInlineList(
                fields['required_suite']!,
                sourceLabel: sourceLabel,
                lineNumber: elementLine,
              ),
        provenance: fields['provenance'] ?? '',
        specProvenance: fields['spec_provenance'] ?? '',
        lineNumber: elementLine,
      ),
    );
  }
  return i;
}

int _parseCapabilityElements(
  List<String> lines,
  int start,
  String sourceLabel,
  List<CapabilityEntry> capabilities,
) {
  var i = start;
  while (i < lines.length) {
    if (_isBlankOrComment(lines[i])) {
      i++;
      continue;
    }
    if (!lines[i].startsWith('  -')) break;
    final header = _listElementHeader.firstMatch(lines[i]);
    if (header == null || header.group(1) != 'id') {
      throw FormatException(
        '$sourceLabel:${i + 1}: expected a capability element '
        '"  - id: <value>", got: "${lines[i]}"',
      );
    }
    final elementLine = i + 1;
    final fields = <String, String>{'id': header.group(2)!.trim()};
    i++;
    while (i < lines.length && _fourSpaceKeyLine.hasMatch(lines[i])) {
      final match = _fourSpaceKeyLine.firstMatch(lines[i])!;
      final key = match.group(1)!;
      final lineNumber = i + 1;
      if (!_capabilityFieldKeys.contains(key)) {
        throw FormatException(
          '$sourceLabel:$lineNumber: unsupported capability field "$key"',
        );
      }
      fields[key] = match.group(2)!.trim();
      i++;
    }
    capabilities.add(
      CapabilityEntry(
        id: fields['id'] ?? '',
        gaScope: fields['ga_scope'] ?? '',
        devices: fields['devices'] == null
            ? const []
            : _parseInlineList(
                fields['devices']!,
                sourceLabel: sourceLabel,
                lineNumber: elementLine,
              ),
        lineNumber: elementLine,
      ),
    );
  }
  return i;
}

/// Parses the deliberately RESTRICTED device-matrix YAML subset (R3): a
/// `schema_version:` scalar, `devices:`/`capabilities:` 2-space-indented
/// block lists whose elements start `  - id: <value>` and carry 4-space
/// flat fields (an inline `[a, b]` list for `required_suite`/`devices`), and
/// a top-level inline `required_suite_catalog: [...]`. Anything else —
/// wrong indentation, an inline value on a block-list key, an unsupported
/// field name — fails with a `FormatException` naming the exact line, the
/// same fail-closed contract `repository_policy_test.dart`'s
/// `parseIssueForm` documents.
DeviceMatrix parseDeviceMatrix(String contents, {required String sourceLabel}) {
  final lines = contents.split('\n');
  int? schemaVersion;
  final devices = <DeviceEntry>[];
  final capabilities = <CapabilityEntry>[];
  List<String>? requiredSuiteCatalog;

  var i = 0;
  while (i < lines.length) {
    if (_isBlankOrComment(lines[i])) {
      i++;
      continue;
    }
    final match = _topLevelKeyLine.firstMatch(lines[i]);
    if (match == null) {
      throw FormatException(
        '$sourceLabel:${i + 1}: expected a top-level "key:" line, got: '
        '"${lines[i]}"',
      );
    }
    final key = match.group(1)!;
    final rest = match.group(2)!.trim();
    final lineNumber = i + 1;
    i++;
    switch (key) {
      case 'schema_version':
        schemaVersion = int.tryParse(rest);
        if (schemaVersion == null) {
          throw FormatException(
            '$sourceLabel:$lineNumber: "schema_version:" must be an '
            'integer, got: "$rest"',
          );
        }
      case 'devices':
        if (rest.isNotEmpty) {
          throw FormatException(
            '$sourceLabel:$lineNumber: "devices:" must start a block list, '
            'not an inline value: "$rest"',
          );
        }
        i = _parseDeviceElements(lines, i, sourceLabel, devices);
      case 'capabilities':
        if (rest.isNotEmpty) {
          throw FormatException(
            '$sourceLabel:$lineNumber: "capabilities:" must start a block '
            'list, not an inline value: "$rest"',
          );
        }
        i = _parseCapabilityElements(lines, i, sourceLabel, capabilities);
      case 'required_suite_catalog':
        requiredSuiteCatalog = _parseInlineList(
          rest,
          sourceLabel: sourceLabel,
          lineNumber: lineNumber,
        );
      default:
        throw FormatException(
          '$sourceLabel:$lineNumber: unsupported top-level key "$key"',
        );
    }
  }

  if (schemaVersion == null) {
    throw FormatException(
      '$sourceLabel: missing top-level "schema_version:" key',
    );
  }
  if (requiredSuiteCatalog == null) {
    throw FormatException(
      '$sourceLabel: missing top-level "required_suite_catalog:" key',
    );
  }

  return DeviceMatrix(
    schemaVersion: schemaVersion,
    devices: devices,
    capabilities: capabilities,
    requiredSuiteCatalog: requiredSuiteCatalog,
  );
}

// ---------------------------------------------------------------------------
// Content-parameterized checkers (ADR 0444 D6) — fixtures and the real file
// call the exact same functions.
// ---------------------------------------------------------------------------

/// A1 (§5.4, L546): every one of the eleven identifier fields, on every
/// device, must be present and not one of [identifierPlaceholderValues].
List<String> findPlaceholderIdentifierFields(List<DeviceEntry> devices) {
  final violations = <String>[];
  for (final device in devices) {
    device.identifierFields.forEach((fieldName, value) {
      if (isPlaceholderValue(value)) {
        violations.add('device:${device.lineNumber}.$fieldName');
      }
    });
  }
  return violations;
}

/// A2 (§5.1, §6.2): every GA-scope capability id must be declared AND
/// covered by at least one `release_blocking: true` device. A GA id entirely
/// absent from the matrix is also a violation — "declared with zero
/// coverage" and "never declared" are the same failure from the release's
/// point of view.
List<String> findGaCapabilitiesWithoutBlockingDevice(
  List<DeviceEntry> devices,
  List<CapabilityEntry> capabilities,
) {
  final blockingDeviceIds = devices
      .where((device) => device.releaseBlockingValue)
      .map((device) => device.id)
      .toSet();
  final byId = {
    for (final capability in capabilities) capability.id: capability,
  };
  final violations = <String>[];
  for (final gaId in gaScopeCapabilityIds) {
    final capability = byId[gaId];
    if (capability == null) {
      violations.add('$gaId: missing from device-matrix.yaml');
      continue;
    }
    final hasBlockingDevice = capability.devices.any(
      blockingDeviceIds.contains,
    );
    if (!hasBlockingDevice) {
      violations.add('$gaId: 0 release_blocking devices');
    }
  }
  return violations;
}

/// A3 (§5.2, Ch12 §18.3): a device missing an OPTIONAL (non-GA) capability
/// tier never becomes globally "unsupported" — `core_support` must stay
/// `supported` regardless of `offline_ai_tier`.
List<String> findDevicesWithInvalidCoreSupportForOptionalCapability(
  List<DeviceEntry> devices,
) {
  const optionalTierValues = {'not_ga_scope', 'unsupported'};
  final violations = <String>[];
  for (final device in devices) {
    final tier = device.offlineAiTier.trim().toLowerCase();
    if (optionalTierValues.contains(tier) &&
        device.coreSupport.trim().toLowerCase() != 'supported') {
      violations.add(
        'device:${device.lineNumber}: core_support must stay "supported" '
        'when offline_ai_tier is "$tier" (Ch12 §18.3)',
      );
    }
  }
  return violations;
}

final _provenancePattern = RegExp(r'^(.+\.md):(\d+)$');

/// Shared by [findInvalidProvenance] and [findInvalidSpecProvenance]: both
/// fields are `docs/manual-testing/<file>.md:<line>` references and share
/// the exact same fail-closed contract (the "invented device" risk, §9) —
/// only which field is read and how the violation names itself differ.
List<String> _findInvalidPathLineReference(
  List<DeviceEntry> devices, {
  required String Function(DeviceEntry device) fieldValue,
  required String fieldName,
  required bool Function(String path) fileExists,
  required int Function(String path) lineCount,
}) {
  final violations = <String>[];
  for (final device in devices) {
    final raw = fieldValue(device).trim();
    final match = _provenancePattern.firstMatch(raw);
    if (match == null) {
      violations.add(
        'device:${device.lineNumber}: $fieldName is not a "path:line" '
        'reference: "$raw"',
      );
      continue;
    }
    final path = match.group(1)!;
    final line = int.parse(match.group(2)!);
    if (!path.startsWith('docs/manual-testing/')) {
      violations.add(
        'device:${device.lineNumber}: $fieldName must point into '
        'docs/manual-testing/, got "$path"',
      );
      continue;
    }
    if (!fileExists(path)) {
      violations.add(
        'device:${device.lineNumber}: $fieldName file does not exist: '
        '"$path"',
      );
      continue;
    }
    final totalLines = lineCount(path);
    if (line < 1 || line > totalLines) {
      violations.add(
        'device:${device.lineNumber}: $fieldName line $line out of range '
        'for "$path" ($totalLines lines)',
      );
    }
  }
  return violations;
}

/// A5: every device's `provenance` must be a real
/// `docs/manual-testing/<file>.md:<line>` reference — an unparseable value,
/// a non-existent file, or an out-of-range line number is a violation (the
/// "invented device" risk, §9).
List<String> findInvalidProvenance(
  List<DeviceEntry> devices, {
  required bool Function(String path) fileExists,
  required int Function(String path) lineCount,
}) => _findInvalidPathLineReference(
  devices,
  fieldValue: (device) => device.provenance,
  fieldName: 'provenance',
  fileExists: fileExists,
  lineCount: lineCount,
);

/// A5 extension (independent review F2, docs/reviews/e12-r13-review.md): the
/// MEASURED source for `ram_gb`/`soc` is `vision-performance-benchmark.md`,
/// not `provenance` (which only carries the camera-spec source) — so
/// `spec_provenance` gets the exact same "real path:line" validation.
List<String> findInvalidSpecProvenance(
  List<DeviceEntry> devices, {
  required bool Function(String path) fileExists,
  required int Function(String path) lineCount,
}) => _findInvalidPathLineReference(
  devices,
  fieldValue: (device) => device.specProvenance,
  fieldName: 'spec_provenance',
  fileExists: fileExists,
  lineCount: lineCount,
);

/// R5: the MEASURED primary test device (Pixel 6a) must be present and
/// `release_blocking: true`. Returns `null` when satisfied.
String? findMissingMeasuredPrimaryDevice(List<DeviceEntry> devices) {
  final matches = devices.where((device) => device.name.trim() == 'Pixel 6a');
  if (matches.isEmpty) {
    return 'no device named "Pixel 6a" (the measured primary test device, '
        'R5) is present';
  }
  if (!matches.first.releaseBlockingValue) {
    return 'Pixel 6a must be release_blocking: true (R5)';
  }
  return null;
}

/// A7: every capability id must come from the closed GA/non-GA dictionaries,
/// with `ga_scope` matching the dictionary it belongs to — an id declared
/// with the wrong `ga_scope` (the "weaken the invariant" class) is a
/// violation, not just an id outside both dictionaries.
List<String> findUnknownCapabilityDeclarations(
  List<CapabilityEntry> capabilities,
) {
  final violations = <String>[];
  for (final capability in capabilities) {
    final isGa = gaScopeCapabilityIds.contains(capability.id);
    final isNonGa = nonGaScopeCapabilityIds.contains(capability.id);
    if (!isGa && !isNonGa) {
      violations.add('unknown capability id: "${capability.id}"');
      continue;
    }
    if (isGa && !capability.gaScopeValue) {
      violations.add(
        '${capability.id}: is a GA-scope dictionary id but declares '
        'ga_scope: false',
      );
    }
    if (isNonGa && capability.gaScopeValue) {
      violations.add(
        '${capability.id}: is a non-GA-scope dictionary id but declares '
        'ga_scope: true',
      );
    }
  }
  return violations;
}

/// A7: every device's `required_suite` entries must come from the closed
/// [requiredSuiteCatalogIds] dictionary.
List<String> findUnknownRequiredSuiteItems(List<DeviceEntry> devices) {
  final violations = <String>[];
  for (final device in devices) {
    for (final item in device.requiredSuite) {
      if (!requiredSuiteCatalogIds.contains(item)) {
        violations.add(
          'device:${device.lineNumber}: unknown required_suite item '
          '"$item"',
        );
      }
    }
  }
  return violations;
}

/// A1 extension (independent review F1, docs/reviews/e12-r13-review.md):
/// `required_suite` must be present and non-empty on EVERY device, blocking
/// or not — a device missing the field entirely and a device declaring it
/// as `[]` parse to the same empty list (§ R3's parser), so both count as
/// the same violation.
List<String> findEmptyRequiredSuiteField(List<DeviceEntry> devices) {
  final violations = <String>[];
  for (final device in devices) {
    if (device.requiredSuite.isEmpty) {
      violations.add('device:${device.lineNumber}.required_suite');
    }
  }
  return violations;
}

/// F1 (independent review MAJOR): a `release_blocking: true` device's
/// `required_suite` must cover every entry of [mandatoryRequiredSuiteIds].
/// A2 only checks that a GA capability has *a* blocking device — it says
/// nothing about whether that device's own mandatory measurement list is
/// intact. Without this cell, emptying a blocking device's `required_suite`
/// left every gate cell green (the exact failure the review measured:
/// `flutter test` at "+99: All tests passed!" and
/// `device_report.py --check` exiting 0 with zero recorded runs).
List<String> findBlockingDevicesWithIncompleteRequiredSuite(
  List<DeviceEntry> devices,
) {
  final violations = <String>[];
  for (final device in devices) {
    if (!device.releaseBlockingValue) continue;
    final present = device.requiredSuite.toSet();
    final missing = mandatoryRequiredSuiteIds
        .where((id) => !present.contains(id))
        .toList();
    if (missing.isNotEmpty) {
      violations.add(
        'device:${device.lineNumber} (${device.id}): required_suite is '
        'missing ${missing.length} mandatory item(s): ${missing.join(', ')}',
      );
    }
  }
  return violations;
}

// ---------------------------------------------------------------------------
// Fixture builders
// ---------------------------------------------------------------------------

const Map<String, String> _validDeviceFieldDefaults = {
  'id': 'fixture_device',
  'name': 'Fixture Device',
  'os': 'Android 14',
  'api_level': '34',
  'ram_gb': '6',
  'abi': 'arm64-v8a',
  'soc': 'Fixture SoC',
  'camera_spec': '12 MP, 30 fps, AF',
  'camera_result': 'pending',
  'audio_result': 'pending',
  'vision_tier': 'pending',
  'offline_ai_tier': 'not_ga_scope',
  'core_support': 'supported',
  'release_blocking': 'true',
  'required_suite':
      '[install_and_update, cold_start, live_start_latency, mic_release, '
      'practice_soak_20min, analyze_memory_peak, camera_preview_and_thermal, '
      'background_resume, battery_saver, airplane_mode, low_storage, '
      'text_scale_200, screen_reader_path]',
  'provenance': 'docs/manual-testing/vision-device-matrix.md:160',
  'spec_provenance': 'docs/manual-testing/vision-performance-benchmark.md:117',
};

/// Builds a minimal, otherwise-valid device-matrix document with a single
/// device (`fixture_device` unless overridden via `overrides['id']`) so
/// individual fixture-negative cells only need to name the ONE field under
/// test.
String fixtureDeviceMatrixYaml({
  Map<String, String> overrides = const {},
  Set<String> omit = const {},
  List<String> extraCapabilityLines = const [],
}) {
  final fields = Map<String, String>.from(_validDeviceFieldDefaults)
    ..addAll(overrides);
  for (final key in omit) {
    fields.remove(key);
  }
  final id = fields.remove('id') ?? 'fixture_device';
  final buffer = StringBuffer()
    ..writeln('schema_version: 1')
    ..writeln('devices:')
    ..writeln('  - id: $id');
  fields.forEach((key, value) => buffer.writeln('    $key: $value'));
  buffer.writeln('capabilities:');
  for (final line in extraCapabilityLines) {
    buffer.writeln(line);
  }
  buffer.writeln('required_suite_catalog: []');
  return buffer.toString();
}

void main() {
  group('parseDeviceMatrix — restricted YAML subset (R3)', () {
    test('parses a minimal, fully-formed document', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(),
        sourceLabel: 'fixture',
      );
      expect(matrix.schemaVersion, 1);
      expect(matrix.devices, hasLength(1));
      expect(matrix.devices.single.id, 'fixture_device');
      expect(matrix.capabilities, isEmpty);
    });

    test('parses inline lists, including an empty one', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(
          overrides: {'required_suite': '[install_and_update, cold_start]'},
          extraCapabilityLines: [
            '  - id: onboarding',
            '    ga_scope: true',
            '    devices: []',
          ],
        ),
        sourceLabel: 'fixture',
      );
      expect(matrix.devices.single.requiredSuite, [
        'install_and_update',
        'cold_start',
      ]);
      expect(matrix.capabilities.single.devices, isEmpty);
    });

    test('rejects an unsupported top-level key', () {
      expect(
        () => parseDeviceMatrix('unsupported: 1\n', sourceLabel: 'fixture'),
        throwsFormatException,
      );
    });

    test('rejects an unsupported device field', () {
      const fixture = '''
schema_version: 1
devices:
  - id: x
    made_up_field: 1
capabilities:
required_suite_catalog: []
''';
      expect(
        () => parseDeviceMatrix(fixture, sourceLabel: 'fixture'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('made_up_field'),
          ),
        ),
      );
    });

    test('rejects "devices:" written with an inline value', () {
      const fixture = '''
schema_version: 1
devices: []
capabilities:
required_suite_catalog: []
''';
      expect(
        () => parseDeviceMatrix(fixture, sourceLabel: 'fixture'),
        throwsFormatException,
      );
    });
  });

  group('A1 — device-matrix.yaml schema validity: eleven identifier '
      'fields, no placeholder value (§5.4, L546)', () {
    test('self-check: isPlaceholderValue is case-insensitive and does not '
        'flag a legitimate value', () {
      expect(isPlaceholderValue('UNKNOWN'), isTrue);
      expect(isPlaceholderValue('  '), isTrue);
      expect(isPlaceholderValue('arm64-v8a'), isFalse);
    });

    test('self-check: a fully populated fixture device has zero placeholder '
        'violations', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(),
        sourceLabel: 'fixture',
      );
      expect(findPlaceholderIdentifierFields(matrix.devices), isEmpty);
    });

    test('matrix row: a device missing the "abi" field entirely (not just '
        'empty) is flagged', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(omit: {'abi'}),
        sourceLabel: 'fixture',
      );
      final device = matrix.devices.single;
      expect(
        findPlaceholderIdentifierFields(matrix.devices),
        contains('device:${device.lineNumber}.abi'),
      );
    });

    for (final placeholder in identifierPlaceholderValues) {
      for (final field in identifierFieldNames) {
        test('matrix row: "$field" set to placeholder "$placeholder" is '
            'flagged (L546 — the full placeholder list, walked field by '
            'field, not one example)', () {
          final matrix = parseDeviceMatrix(
            fixtureDeviceMatrixYaml(overrides: {field: placeholder}),
            sourceLabel: 'fixture',
          );
          final device = matrix.devices.single;
          expect(
            findPlaceholderIdentifierFields(matrix.devices),
            contains('device:${device.lineNumber}.$field'),
          );
        });
      }
    }

    test('the real device-matrix.yaml has all eleven identifier fields on '
        'every device, none of them a placeholder value', () {
      final matrix = parseDeviceMatrix(
        File(_matrixPath).readAsStringSync(),
        sourceLabel: _matrixPath,
      );
      expect(matrix.devices, isNotEmpty);
      expect(findPlaceholderIdentifierFields(matrix.devices), isEmpty);
    });

    test('matrix row: a release_blocking device with required_suite: [] is '
        'flagged as missing the field, not silently accepted (independent '
        'review F1)', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(overrides: {'required_suite': '[]'}),
        sourceLabel: 'fixture',
      );
      final device = matrix.devices.single;
      expect(
        findEmptyRequiredSuiteField(matrix.devices),
        contains('device:${device.lineNumber}.required_suite'),
      );
    });

    test('matrix row: a non-blocking device with required_suite: [] is '
        'flagged too — the field is mandatory regardless of '
        'release_blocking (independent review F1)', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(
          overrides: {'release_blocking': 'false', 'required_suite': '[]'},
        ),
        sourceLabel: 'fixture',
      );
      final device = matrix.devices.single;
      expect(
        findEmptyRequiredSuiteField(matrix.devices),
        contains('device:${device.lineNumber}.required_suite'),
      );
    });

    test('self-check: a fully populated fixture device has a non-empty '
        'required_suite', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(),
        sourceLabel: 'fixture',
      );
      expect(findEmptyRequiredSuiteField(matrix.devices), isEmpty);
    });

    test('the real device-matrix.yaml: every device has a non-empty '
        'required_suite', () {
      final matrix = parseDeviceMatrix(
        File(_matrixPath).readAsStringSync(),
        sourceLabel: _matrixPath,
      );
      expect(findEmptyRequiredSuiteField(matrix.devices), isEmpty);
    });
  });

  group('A2 — every GA-scope capability has at least one release_blocking '
      'device (§5.1, §6.2 numeric threshold)', () {
    String fixtureWithBlockingDeviceCount(int blockingDeviceCount) {
      final buffer = StringBuffer()
        ..writeln('schema_version: 1')
        ..writeln('devices:');
      for (var index = 0; index < 2; index++) {
        final blocking = index < blockingDeviceCount;
        buffer
          ..writeln('  - id: device_$index')
          ..writeln('    name: Device $index')
          ..writeln('    os: Android 14')
          ..writeln('    api_level: 34')
          ..writeln('    ram_gb: 6')
          ..writeln('    abi: arm64-v8a')
          ..writeln('    soc: Fixture SoC')
          ..writeln('    release_blocking: $blocking')
          ..writeln(
            '    provenance: docs/manual-testing/vision-device-matrix.md:160',
          );
      }
      buffer.writeln('capabilities:');
      for (final gaId in gaScopeCapabilityIds) {
        buffer
          ..writeln('  - id: $gaId')
          ..writeln('    ga_scope: true')
          ..writeln('    devices: [device_0, device_1]');
      }
      buffer.writeln('required_suite_catalog: []');
      return buffer.toString();
    }

    test('threshold cell: 0 release_blocking devices covering a GA '
        'capability is flagged', () {
      final matrix = parseDeviceMatrix(
        fixtureWithBlockingDeviceCount(0),
        sourceLabel: 'fixture',
      );
      expect(
        findGaCapabilitiesWithoutBlockingDevice(
          matrix.devices,
          matrix.capabilities,
        ),
        contains('onboarding: 0 release_blocking devices'),
      );
    });

    test('threshold cell: 1 release_blocking device covering a GA '
        'capability is clean', () {
      final matrix = parseDeviceMatrix(
        fixtureWithBlockingDeviceCount(1),
        sourceLabel: 'fixture',
      );
      expect(
        findGaCapabilitiesWithoutBlockingDevice(
          matrix.devices,
          matrix.capabilities,
        ),
        isEmpty,
      );
    });

    test('threshold cell: 2 release_blocking devices covering a GA '
        'capability is clean', () {
      final matrix = parseDeviceMatrix(
        fixtureWithBlockingDeviceCount(2),
        sourceLabel: 'fixture',
      );
      expect(
        findGaCapabilitiesWithoutBlockingDevice(
          matrix.devices,
          matrix.capabilities,
        ),
        isEmpty,
      );
    });

    test('matrix row: a GA capability entirely missing from '
        'device-matrix.yaml is flagged as missing, not silently accepted', () {
      const fixture = '''
schema_version: 1
devices:
  - id: device_0
    name: Device 0
    os: Android 14
    api_level: 34
    ram_gb: 6
    abi: arm64-v8a
    soc: Fixture SoC
    release_blocking: true
    provenance: docs/manual-testing/vision-device-matrix.md:160
capabilities:
required_suite_catalog: []
''';
      final matrix = parseDeviceMatrix(fixture, sourceLabel: 'fixture');
      expect(
        findGaCapabilitiesWithoutBlockingDevice(
          matrix.devices,
          matrix.capabilities,
        ),
        contains('onboarding: missing from device-matrix.yaml'),
      );
    });

    test('the real device-matrix.yaml: all eleven GA-scope capabilities '
        'have at least one release_blocking device', () {
      final matrix = parseDeviceMatrix(
        File(_matrixPath).readAsStringSync(),
        sourceLabel: _matrixPath,
      );
      expect(
        findGaCapabilitiesWithoutBlockingDevice(
          matrix.devices,
          matrix.capabilities,
        ),
        isEmpty,
      );
    });
  });

  group('F1 — a release_blocking device\'s required_suite must cover the '
      'full mandatory dictionary (independent review MAJOR, '
      'docs/reviews/e12-r13-review.md)', () {
    test('fixture row: a release_blocking device with required_suite: [] '
        'is flagged, naming the device', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(overrides: {'required_suite': '[]'}),
        sourceLabel: 'fixture',
      );
      expect(
        findBlockingDevicesWithIncompleteRequiredSuite(matrix.devices),
        contains(contains('fixture_device')),
      );
    });

    test('fixture row: a release_blocking device missing one of the '
        'thirteen mandatory required_suite items is flagged', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(
          overrides: {
            // Every mandatoryRequiredSuiteIds entry except the last one.
            'required_suite':
                '[install_and_update, cold_start, live_start_latency, '
                'mic_release, practice_soak_20min, analyze_memory_peak, '
                'camera_preview_and_thermal, background_resume, '
                'battery_saver, airplane_mode, low_storage, text_scale_200]',
          },
        ),
        sourceLabel: 'fixture',
      );
      final violations = findBlockingDevicesWithIncompleteRequiredSuite(
        matrix.devices,
      );
      expect(violations, isNotEmpty);
      expect(violations.single, contains('screen_reader_path'));
    });

    test('self-check: a release_blocking device with the full thirteen-item '
        'mandatory suite is clean', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(),
        sourceLabel: 'fixture',
      );
      expect(
        findBlockingDevicesWithIncompleteRequiredSuite(matrix.devices),
        isEmpty,
      );
    });

    test('self-check: a non-blocking device is never checked against the '
        'mandatory dictionary, even with an empty required_suite', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(
          overrides: {'release_blocking': 'false', 'required_suite': '[]'},
        ),
        sourceLabel: 'fixture',
      );
      expect(
        findBlockingDevicesWithIncompleteRequiredSuite(matrix.devices),
        isEmpty,
      );
    });

    test('self-check: mandatoryRequiredSuiteIds is the fourteen-entry '
        'catalog minus local_ai_load_ttft (thirteen entries, R7)', () {
      expect(mandatoryRequiredSuiteIds, hasLength(13));
      expect(mandatoryRequiredSuiteIds, isNot(contains('local_ai_load_ttft')));
    });

    test('the real device-matrix.yaml: both release_blocking devices '
        '(Pixel 6a, Pixel 7) carry exactly the thirteen-item mandatory '
        'required_suite', () {
      final matrix = parseDeviceMatrix(
        File(_matrixPath).readAsStringSync(),
        sourceLabel: _matrixPath,
      );
      expect(
        findBlockingDevicesWithIncompleteRequiredSuite(matrix.devices),
        isEmpty,
      );
      final blockingDevices = matrix.devices.where(
        (device) => device.releaseBlockingValue,
      );
      expect(blockingDevices, hasLength(2));
      for (final device in blockingDevices) {
        expect(
          device.requiredSuite.toSet(),
          mandatoryRequiredSuiteIds.toSet(),
          reason:
              '${device.id} required_suite must be exactly the '
              'thirteen-item mandatory dictionary',
        );
      }
    });
  });

  group('A3 — an optional (non-GA) capability tier never demotes a device '
      'to globally unsupported (§5.2, Ch12 §18.3)', () {
    test('matrix row: offline_ai_tier: not_ga_scope with core_support: '
        'unsupported is flagged', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(
          overrides: {
            'offline_ai_tier': 'not_ga_scope',
            'core_support': 'unsupported',
          },
        ),
        sourceLabel: 'fixture',
      );
      expect(
        findDevicesWithInvalidCoreSupportForOptionalCapability(matrix.devices),
        isNotEmpty,
      );
    });

    test('matrix row: offline_ai_tier: unsupported with core_support: '
        'unsupported is flagged too', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(
          overrides: {
            'offline_ai_tier': 'unsupported',
            'core_support': 'unsupported',
          },
        ),
        sourceLabel: 'fixture',
      );
      expect(
        findDevicesWithInvalidCoreSupportForOptionalCapability(matrix.devices),
        isNotEmpty,
      );
    });

    test('self-check: offline_ai_tier: not_ga_scope with core_support: '
        'supported is clean', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(),
        sourceLabel: 'fixture',
      );
      expect(
        findDevicesWithInvalidCoreSupportForOptionalCapability(matrix.devices),
        isEmpty,
      );
    });

    test('the real device-matrix.yaml: every device keeps core_support: '
        'supported regardless of offline_ai_tier', () {
      final matrix = parseDeviceMatrix(
        File(_matrixPath).readAsStringSync(),
        sourceLabel: _matrixPath,
      );
      expect(
        findDevicesWithInvalidCoreSupportForOptionalCapability(matrix.devices),
        isEmpty,
      );
    });
  });

  group('A5 — provenance references are real; the measured primary test '
      'device is present (R5, §9 invented-device risk)', () {
    bool realFileExists(String path) => File(path).existsSync();
    int realLineCount(String path) => File(path).readAsLinesSync().length;

    test('matrix row: a provenance value that is not a "path:line" '
        'reference is flagged', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(overrides: {'provenance': 'trust me'}),
        sourceLabel: 'fixture',
      );
      expect(
        findInvalidProvenance(
          matrix.devices,
          fileExists: realFileExists,
          lineCount: realLineCount,
        ),
        isNotEmpty,
      );
    });

    test('matrix row: a provenance value pointing at a non-existent '
        'manual-testing file is flagged', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(
          overrides: {'provenance': 'docs/manual-testing/does-not-exist.md:1'},
        ),
        sourceLabel: 'fixture',
      );
      expect(
        findInvalidProvenance(
          matrix.devices,
          fileExists: realFileExists,
          lineCount: realLineCount,
        ),
        isNotEmpty,
      );
    });

    test('matrix row: a provenance line number beyond the end of the file '
        'is flagged', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(
          overrides: {
            'provenance': 'docs/manual-testing/vision-device-matrix.md:999999',
          },
        ),
        sourceLabel: 'fixture',
      );
      expect(
        findInvalidProvenance(
          matrix.devices,
          fileExists: realFileExists,
          lineCount: realLineCount,
        ),
        isNotEmpty,
      );
    });

    test('self-check: a well-formed, real provenance reference is clean', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(),
        sourceLabel: 'fixture',
      );
      expect(
        findInvalidProvenance(
          matrix.devices,
          fileExists: realFileExists,
          lineCount: realLineCount,
        ),
        isEmpty,
      );
    });

    test('matrix row: a fixture without a device named "Pixel 6a" is '
        'flagged as missing the measured primary device', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(),
        sourceLabel: 'fixture',
      );
      expect(findMissingMeasuredPrimaryDevice(matrix.devices), isNotNull);
    });

    test('the real device-matrix.yaml: every provenance reference points at '
        'an existing docs/manual-testing/ file and an in-range line', () {
      final matrix = parseDeviceMatrix(
        File(_matrixPath).readAsStringSync(),
        sourceLabel: _matrixPath,
      );
      expect(
        findInvalidProvenance(
          matrix.devices,
          fileExists: realFileExists,
          lineCount: realLineCount,
        ),
        isEmpty,
      );
    });

    test('the real device-matrix.yaml names Pixel 6a as release_blocking: '
        'true (R5, the measured elsődleges teszteszköz)', () {
      final matrix = parseDeviceMatrix(
        File(_matrixPath).readAsStringSync(),
        sourceLabel: _matrixPath,
      );
      expect(findMissingMeasuredPrimaryDevice(matrix.devices), isNull);
    });

    test('matrix row: a spec_provenance value that is not a "path:line" '
        'reference is flagged (independent review F2 — ram_gb/soc source, '
        'docs/reviews/e12-r13-review.md)', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(overrides: {'spec_provenance': 'trust me'}),
        sourceLabel: 'fixture',
      );
      expect(
        findInvalidSpecProvenance(
          matrix.devices,
          fileExists: realFileExists,
          lineCount: realLineCount,
        ),
        isNotEmpty,
      );
    });

    test('matrix row: a spec_provenance value pointing at a non-existent '
        'manual-testing file is flagged', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(
          overrides: {
            'spec_provenance': 'docs/manual-testing/does-not-exist.md:1',
          },
        ),
        sourceLabel: 'fixture',
      );
      expect(
        findInvalidSpecProvenance(
          matrix.devices,
          fileExists: realFileExists,
          lineCount: realLineCount,
        ),
        isNotEmpty,
      );
    });

    test('matrix row: a spec_provenance line number beyond the end of the '
        'file is flagged', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(
          overrides: {
            'spec_provenance':
                'docs/manual-testing/vision-performance-benchmark.md:999999',
          },
        ),
        sourceLabel: 'fixture',
      );
      expect(
        findInvalidSpecProvenance(
          matrix.devices,
          fileExists: realFileExists,
          lineCount: realLineCount,
        ),
        isNotEmpty,
      );
    });

    test('self-check: a well-formed, real spec_provenance reference is '
        'clean', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(),
        sourceLabel: 'fixture',
      );
      expect(
        findInvalidSpecProvenance(
          matrix.devices,
          fileExists: realFileExists,
          lineCount: realLineCount,
        ),
        isEmpty,
      );
    });

    test('the real device-matrix.yaml: every spec_provenance reference '
        'points at an existing docs/manual-testing/ file and an in-range '
        'line', () {
      final matrix = parseDeviceMatrix(
        File(_matrixPath).readAsStringSync(),
        sourceLabel: _matrixPath,
      );
      expect(
        findInvalidSpecProvenance(
          matrix.devices,
          fileExists: realFileExists,
          lineCount: realLineCount,
        ),
        isEmpty,
      );
    });
  });

  group('A6 — device-lab.md references all six docs/manual-testing '
      'documents (R1) and rewrites none of them', () {
    const requiredDocs = [
      'analysis-eval-matrix.md',
      'gov-05-shipping-device-run.md',
      'practice-engine-device-matrix.md',
      'vision-camera-spike-runbook.md',
      'vision-device-matrix.md',
      'vision-performance-benchmark.md',
    ];

    test('the real device-lab.md mentions every one of the six documents', () {
      final content = File('docs/testing/device-lab.md').readAsStringSync();
      for (final doc in requiredDocs) {
        expect(
          content,
          contains(doc),
          reason: 'device-lab.md must reference $doc',
        );
      }
    });

    test('self-check: the required-docs list above actually has six '
        'entries (R1 — it used to be four)', () {
      expect(requiredDocs, hasLength(6));
    });
  });

  group('A7 — required_suite and capability identifiers come from the '
      'measured closed dictionaries (R6, R7)', () {
    test('matrix row: an unknown capability id is flagged', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(
          extraCapabilityLines: [
            '  - id: made_up_capability',
            '    ga_scope: true',
            '    devices: [fixture_device]',
          ],
        ),
        sourceLabel: 'fixture',
      );
      expect(
        findUnknownCapabilityDeclarations(matrix.capabilities),
        isNotEmpty,
      );
    });

    test('matrix row: a GA-dictionary id declared with ga_scope: false is '
        'flagged (the "weaken the invariant so it fits" class, §6.1)', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(
          extraCapabilityLines: [
            '  - id: onboarding',
            '    ga_scope: false',
            '    devices: [fixture_device]',
          ],
        ),
        sourceLabel: 'fixture',
      );
      expect(
        findUnknownCapabilityDeclarations(matrix.capabilities),
        isNotEmpty,
      );
    });

    test('matrix row: a non-GA-dictionary id declared with ga_scope: true '
        'is flagged', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(
          extraCapabilityLines: [
            '  - id: computer_vision',
            '    ga_scope: true',
            '    devices: [fixture_device]',
          ],
        ),
        sourceLabel: 'fixture',
      );
      expect(
        findUnknownCapabilityDeclarations(matrix.capabilities),
        isNotEmpty,
      );
    });

    test('matrix row: an unknown required_suite element is flagged', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(
          overrides: {'required_suite': '[made_up_suite_item]'},
        ),
        sourceLabel: 'fixture',
      );
      expect(findUnknownRequiredSuiteItems(matrix.devices), isNotEmpty);
    });

    test('self-check: a fixture using only dictionary ids/items is clean', () {
      final matrix = parseDeviceMatrix(
        fixtureDeviceMatrixYaml(
          overrides: {'required_suite': '[install_and_update]'},
          extraCapabilityLines: [
            '  - id: onboarding',
            '    ga_scope: true',
            '    devices: [fixture_device]',
          ],
        ),
        sourceLabel: 'fixture',
      );
      expect(findUnknownCapabilityDeclarations(matrix.capabilities), isEmpty);
      expect(findUnknownRequiredSuiteItems(matrix.devices), isEmpty);
    });

    test('the real device-matrix.yaml: every capability id and '
        'required_suite element comes from the closed dictionaries', () {
      final matrix = parseDeviceMatrix(
        File(_matrixPath).readAsStringSync(),
        sourceLabel: _matrixPath,
      );
      expect(findUnknownCapabilityDeclarations(matrix.capabilities), isEmpty);
      expect(findUnknownRequiredSuiteItems(matrix.devices), isEmpty);
    });

    test('the real device-matrix.yaml declares all eleven GA-scope and all '
        'three non-GA-scope capability ids, no more, no fewer', () {
      final matrix = parseDeviceMatrix(
        File(_matrixPath).readAsStringSync(),
        sourceLabel: _matrixPath,
      );
      final ids = matrix.capabilities.map((c) => c.id).toSet();
      expect(ids, {...gaScopeCapabilityIds, ...nonGaScopeCapabilityIds});
    });

    test('local_ai_load_ttft is a valid suite-dictionary entry but no '
        'device requires it today (R7 — Offline AI is not_ga_scope)', () {
      final matrix = parseDeviceMatrix(
        File(_matrixPath).readAsStringSync(),
        sourceLabel: _matrixPath,
      );
      expect(requiredSuiteCatalogIds, contains('local_ai_load_ttft'));
      for (final device in matrix.devices) {
        expect(device.requiredSuite, isNot(contains('local_ai_load_ttft')));
      }
    });
  });

  group('A4 — tool/device_report.py --check: non-zero on missing mandatory '
      'runs, zero on a complete result set (R4)', () {
    late Directory fixtureRoot;

    setUp(() {
      fixtureRoot = Directory.systemTemp.createTempSync(
        'strumsight_device_report_',
      );
    });
    tearDown(() => fixtureRoot.deleteSync(recursive: true));

    String writeFixtureMatrix() {
      final file = File('${fixtureRoot.path}/matrix.yaml')
        ..writeAsStringSync('''
devices:
  - id: fixture_device
    name: Fixture Device
    release_blocking: true
    required_suite: [suite_a, suite_b]
  - id: fixture_recommended
    name: Fixture Recommended
    release_blocking: false
    required_suite: [suite_a]
capabilities: []
''');
      return file.path;
    }

    test('no --results file: every mandatory run is missing, non-zero '
        'exit, names each one', () {
      final matrixPath = writeFixtureMatrix();
      final result = Process.runSync('python3', [
        'tool/device_report.py',
        '--matrix',
        matrixPath,
        '--check',
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stdout.toString(), contains('fixture_device:suite_a'));
      expect(result.stdout.toString(), contains('fixture_device:suite_b'));
    });

    test('a --results file recording every mandatory run — even as '
        '"pending" — is a zero exit (pending is a valid recorded state, '
        '§5.4)', () {
      final matrixPath = writeFixtureMatrix();
      final resultsFile = File('${fixtureRoot.path}/results.yaml')
        ..writeAsStringSync('''
runs:
  fixture_device:
    suite_a: pending
    suite_b: pass
''');
      final result = Process.runSync('python3', [
        'tool/device_report.py',
        '--matrix',
        matrixPath,
        '--results',
        resultsFile.path,
        '--check',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    });

    test('threshold cell: one recorded, one missing mandatory run is still '
        'a non-zero exit, naming only the missing one', () {
      final matrixPath = writeFixtureMatrix();
      final resultsFile = File('${fixtureRoot.path}/results.yaml')
        ..writeAsStringSync('''
runs:
  fixture_device:
    suite_a: pass
''');
      final result = Process.runSync('python3', [
        'tool/device_report.py',
        '--matrix',
        matrixPath,
        '--results',
        resultsFile.path,
        '--check',
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stdout.toString(), contains('fixture_device:suite_b'));
      expect(
        result.stdout.toString(),
        isNot(contains('fixture_device:suite_a')),
      );
    });

    test('matrix row: a recommended (non-blocking) device is never counted '
        'as a mandatory run', () {
      final matrixPath = writeFixtureMatrix();
      final result = Process.runSync('python3', [
        'tool/device_report.py',
        '--matrix',
        matrixPath,
        '--check',
      ]);
      expect(result.stdout.toString(), isNot(contains('fixture_recommended')));
    });

    test('matrix row: a release_blocking device with required_suite: [] is '
        'a --check failure, not a clean "every run recorded" result '
        '(independent review F1, docs/reviews/e12-r13-review.md)', () {
      final file = File('${fixtureRoot.path}/matrix.yaml')
        ..writeAsStringSync('''
devices:
  - id: fixture_device
    name: Fixture Device
    release_blocking: true
    required_suite: []
capabilities: []
''');
      final result = Process.runSync('python3', [
        'tool/device_report.py',
        '--matrix',
        file.path,
        '--check',
      ]);
      expect(result.exitCode, isNot(0));
      expect(
        result.stdout.toString(),
        contains('fixture_device: required_suite is empty'),
      );
    });

    test('--report on the real matrix runs cleanly and lists every device', () {
      final result = Process.runSync('python3', [
        'tool/device_report.py',
        '--matrix',
        _matrixPath,
        '--report',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout.toString(), contains('Pixel 6a'));
      expect(result.stdout.toString(), contains('Devices: 4'));
    });

    test('the §7 command: the real matrix, --check, with no results file '
        'is a non-zero exit today (no result fixture exists yet)', () {
      final result = Process.runSync('python3', [
        'tool/device_report.py',
        '--matrix',
        _matrixPath,
        '--check',
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stdout.toString(), contains('missing mandatory run'));
    });

    test('neither --check nor --report given is a usage error, not a '
        'silent success', () {
      final matrixPath = writeFixtureMatrix();
      final result = Process.runSync('python3', [
        'tool/device_report.py',
        '--matrix',
        matrixPath,
      ]);
      expect(result.exitCode, isNot(0));
    });
  });

  // No skip path anywhere in this file: if python3 is missing, the
  // `Process.runSync` calls above (group A4) throw `ProcessException` the
  // first time a test calls one, which fails that test — exactly the
  // "PIROS, not skip" contract the self-check below measures directly.
  group('A8 — this gate never relies on an unguaranteed or forbidden '
      'binary (L110, L527)', () {
    test('this file does not import the transitive-only yaml package', () {
      final source = File(
        'test/tooling/device_matrix_test.dart',
      ).readAsStringSync();
      expect(
        RegExp(r"^import\s+'package:yaml", multiLine: true).hasMatch(source),
        isFalse,
      );
    });

    test('every external process this file spawns — through any dart:io '
        'Process.run/.runSync/.start entry point (L527: a guard naming only '
        'one prefix is blind to the others) — targets python3 only, never '
        'rg/grep/jq/gh/git', () {
      final source = File(
        'test/tooling/device_matrix_test.dart',
      ).readAsStringSync();
      final executables = _processCallExecutable
          .allMatches(source)
          .map((match) => match.group(1)!)
          .toSet();
      expect(executables, isNotEmpty, reason: 'this file must call python3');
      expect(executables, {'python3'});
    });

    test('self-check: python3 is on PATH in this environment — if it is '
        'not, the calls above throw ProcessException and this whole file '
        'turns red, never a silent skip', () {
      final result = Process.runSync('python3', ['--version']);
      expect(result.exitCode, 0);
    });
  });
}

// Built via adjacent string-literal concatenation so this constant's own
// definition text never spells out the executable-call pattern it searches
// for as one contiguous run of characters — otherwise the A8 self-scan
// above would match its own regex source. A single regex covers all THREE
// `dart:io` external-process entry points (`run`, `runSync`, `start`) in one
// alternation — the exact gap L527 measured (a guard that only recognized
// the `Process.run` prefix let `Process.start` straight through).
final _processCallExecutable = RegExp(
  'Process'
  r'''\.(?:run|runSync|start)\(\s*['"]([^'"\n]+)['"]''',
);
