// Deterministic release manifest generator (ADR 0447 D1, D6).
//
// Follows the `tool/build_tutor_knowledge_manifest.dart` pattern (ADR 0063:
// generated manifest + checksum, no external state beyond declared inputs).
// The manifest is a PURE function of its declared inputs — app version/build
// number (parsed from `pubspec.yaml`), a short git SHA, a channel label, the
// ML model manifest and the tutor knowledge manifest, and an optional list
// of build artifacts to checksum. It contains NO generation timestamp
// anywhere (ADR 0447 D1) — the build time is CI artifact metadata, not
// manifest content.
//
// Determinism is enforced by [canonicalJsonBytes]: every JSON object's keys
// are written in ascending sort order regardless of the order the caller
// built the Dart map in, so two runs against the same inputs are
// byte-identical. Removing that sort step is the round's required
// real-mutation probe (brief §10) — it MUST turn the A1 gate cell red.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const int releaseManifestSchemaVersion = 1;

Future<void> main(List<String> arguments) async {
  String? outputPath;
  String? pubspecPath = 'pubspec.yaml';
  String? mlManifestPath = 'assets/ml/model_manifest.json';
  String? knowledgeManifestPath = 'assets/tutor_knowledge/manifest.json';
  String? gitSha;
  var channel = 'development';
  final artifactPaths = <String>[];

  var index = 0;
  while (index < arguments.length) {
    final arg = arguments[index];
    String requireValue(String flag) {
      if (index + 1 >= arguments.length) {
        throw ArgumentError('$flag requires a value');
      }
      index++;
      return arguments[index];
    }

    switch (arg) {
      case '--output':
        outputPath = requireValue(arg);
      case '--pubspec':
        pubspecPath = requireValue(arg);
      case '--ml-manifest':
        mlManifestPath = requireValue(arg);
      case '--knowledge-manifest':
        knowledgeManifestPath = requireValue(arg);
      case '--git-sha':
        gitSha = requireValue(arg);
      case '--channel':
        channel = requireValue(arg);
      case '--artifact':
        artifactPaths.add(requireValue(arg));
      default:
        stderr.writeln('Unknown argument: $arg');
        exitCode = 64;
        return;
    }
    index++;
  }

  if (outputPath == null) {
    stderr.writeln(
      'Usage: dart run tool/generate_release_manifest.dart --output '
      '<path> [--pubspec <path>] [--ml-manifest <path>] '
      '[--knowledge-manifest <path>] [--git-sha <sha>] [--channel <name>] '
      '[--artifact <path>]...',
    );
    exitCode = 64;
    return;
  }

  try {
    final pubspecContents = File(pubspecPath!).readAsStringSync();
    final appVersion = parsePubspecVersion(pubspecContents);

    final mlManifestFile = File(mlManifestPath!);
    final mlManifestBytes = mlManifestFile.readAsBytesSync();
    final mlManifest =
        jsonDecode(utf8.decode(mlManifestBytes)) as Map<String, Object?>;

    final knowledgeManifestFile = File(knowledgeManifestPath!);
    final knowledgeManifestBytes = knowledgeManifestFile.readAsBytesSync();
    final knowledgeManifest =
        jsonDecode(utf8.decode(knowledgeManifestBytes)) as Map<String, Object?>;

    final resolvedGitSha = gitSha ?? _resolveGitShortSha();

    final artifacts = <ArtifactChecksum>[
      for (final path in artifactPaths)
        ArtifactChecksum(
          name: path.split(Platform.pathSeparator).last,
          path: path,
          sha256: sha256.convert(File(path).readAsBytesSync()).toString(),
        ),
    ];

    final manifest = buildReleaseManifest(
      appVersion: appVersion.version,
      appBuildNumber: appVersion.buildNumber,
      shortSha: resolvedGitSha,
      channel: channel,
      mlManifest: mlManifest,
      mlManifestBytes: mlManifestBytes,
      knowledgeManifest: knowledgeManifest,
      knowledgeManifestBytes: knowledgeManifestBytes,
      artifacts: artifacts,
    );

    final output = File(outputPath);
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(canonicalJsonBytes(manifest));
    stdout.writeln('Release manifest written: $outputPath');
  } on ReleaseManifestException catch (error) {
    stderr.writeln('Release manifest generation failed: ${error.message}');
    exitCode = 1;
  } on Object catch (error, stackTrace) {
    stderr.writeln('Release manifest generation failed: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  }
}

/// Raised for any input the generator refuses to guess its way around.
final class ReleaseManifestException implements Exception {
  const ReleaseManifestException(this.message);

  final String message;

  @override
  String toString() => 'ReleaseManifestException($message)';
}

/// One checksummed build artifact (an APK, an SBOM, a notices bundle, ...).
final class ArtifactChecksum {
  const ArtifactChecksum({
    required this.name,
    required this.path,
    required this.sha256,
  });

  final String name;
  final String path;
  final String sha256;
}

/// `pubspec.yaml`'s `version: <version>+<buildNumber>` line, parsed with the
/// same shape `.github/workflows/release-apk.yml`'s "Read APK metadata from
/// pubspec" step enforces.
final class PubspecAppVersion {
  const PubspecAppVersion({required this.version, required this.buildNumber});

  final String version;
  final int buildNumber;
}

final _pubspecVersionLine = RegExp(
  r'^version:\s*([0-9A-Za-z][0-9A-Za-z._-]*)\+([0-9]+)\s*$',
  multiLine: true,
);

/// Parses the `version:` line out of a `pubspec.yaml`'s raw contents.
///
/// Throws [ReleaseManifestException] if the line is missing or does not
/// match the `<version>+<buildNumber>` shape — the same contract the
/// release workflow's metadata step already enforces.
PubspecAppVersion parsePubspecVersion(String pubspecContents) {
  for (final rawLine in pubspecContents.split('\n')) {
    final line = rawLine.trimRight();
    if (!line.startsWith('version:')) continue;
    final match = _pubspecVersionLine.firstMatch(line);
    if (match == null) {
      throw ReleaseManifestException(
        'pubspec.yaml version line does not match <version>+<buildNumber>: '
        '"$line"',
      );
    }
    return PubspecAppVersion(
      version: match.group(1)!,
      buildNumber: int.parse(match.group(2)!),
    );
  }
  throw const ReleaseManifestException(
    'pubspec.yaml has no top-level "version:" line',
  );
}

/// Builds the release manifest as a plain, JSON-encodable Dart object.
///
/// Pure function — no filesystem or process access. [mlManifest] and
/// [knowledgeManifest] are the already-decoded manifest documents;
/// [mlManifestBytes] and [knowledgeManifestBytes] are their raw file bytes
/// (hashed, not re-read from disk), so callers fully control the inputs —
/// this is what lets `test/tooling/release_manifest_test.dart` exercise it
/// against fixtures without touching the real tree.
///
/// ADR 0447 D6: neither the ML model package nor the tutor knowledge package
/// carries a package-level version field, so each is referenced by its
/// measured schema version, its manifest file's sha256, and its entry
/// count — never by an invented "package version".
Map<String, Object?> buildReleaseManifest({
  required String appVersion,
  required int appBuildNumber,
  required String shortSha,
  required String channel,
  required Map<String, Object?> mlManifest,
  required List<int> mlManifestBytes,
  required Map<String, Object?> knowledgeManifest,
  required List<int> knowledgeManifestBytes,
  List<ArtifactChecksum> artifacts = const [],
}) {
  final models = mlManifest['models'];
  if (models is! List) {
    throw const ReleaseManifestException(
      'ML model manifest is missing a "models" list',
    );
  }
  final mlSchemaVersion = mlManifest['schema_version'];
  if (mlSchemaVersion is! int) {
    throw const ReleaseManifestException(
      'ML model manifest is missing an integer "schema_version"',
    );
  }

  final documents = knowledgeManifest['documents'];
  if (documents is! List) {
    throw const ReleaseManifestException(
      'Tutor knowledge manifest is missing a "documents" list',
    );
  }
  final knowledgeSchemaVersion = knowledgeManifest['schemaVersion'];
  if (knowledgeSchemaVersion is! int) {
    throw const ReleaseManifestException(
      'Tutor knowledge manifest is missing an integer "schemaVersion"',
    );
  }

  final sortedArtifacts = [...artifacts]
    ..sort((left, right) => left.path.compareTo(right.path));

  return <String, Object?>{
    'schemaVersion': releaseManifestSchemaVersion,
    'app': <String, Object?>{
      'version': appVersion,
      'buildNumber': appBuildNumber,
      'shortSha': shortSha,
      'channel': channel,
    },
    'modelPackage': <String, Object?>{
      'schemaVersion': mlSchemaVersion,
      'manifestSha256': sha256.convert(mlManifestBytes).toString(),
      'modelCount': models.length,
    },
    'knowledgePackage': <String, Object?>{
      'schemaVersion': knowledgeSchemaVersion,
      'manifestSha256': sha256.convert(knowledgeManifestBytes).toString(),
      'documentCount': documents.length,
    },
    'artifacts': <Object?>[
      for (final artifact in sortedArtifacts)
        <String, Object?>{
          'name': artifact.name,
          'path': artifact.path,
          'sha256': artifact.sha256,
        },
    ],
  };
}

/// Encodes [value] as canonical JSON: object keys sorted ascending at every
/// nesting level, UTF-8, a single trailing `\n`. Two calls with equal
/// [value]s always produce identical bytes — this IS the determinism
/// contract (ADR 0447 D1), not merely an artifact of construction order.
List<int> canonicalJsonBytes(Object? value) {
  final buffer = StringBuffer();
  _writeCanonical(value, buffer);
  buffer.write('\n');
  return utf8.encode(buffer.toString());
}

void _writeCanonical(Object? value, StringBuffer buffer) {
  switch (value) {
    case null:
      buffer.write('null');
    case bool():
      buffer.write(value ? 'true' : 'false');
    case int():
      buffer.write(value.toString());
    case String():
      buffer.write(jsonEncode(value));
    case List():
      buffer.write('[');
      for (var i = 0; i < value.length; i++) {
        if (i > 0) buffer.write(',');
        _writeCanonical(value[i], buffer);
      }
      buffer.write(']');
    case Map<String, Object?>():
      final keys = value.keys.toList()..sort();
      buffer.write('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) buffer.write(',');
        buffer.write(jsonEncode(keys[i]));
        buffer.write(':');
        _writeCanonical(value[keys[i]], buffer);
      }
      buffer.write('}');
    default:
      throw ArgumentError(
        'canonicalJsonBytes: unsupported value type ${value.runtimeType}',
      );
  }
}

String _resolveGitShortSha() {
  final result = Process.runSync('git', ['rev-parse', '--short=7', 'HEAD']);
  if (result.exitCode != 0) {
    throw ReleaseManifestException(
      'could not resolve git short SHA: ${result.stderr}',
    );
  }
  return (result.stdout as String).trim();
}
