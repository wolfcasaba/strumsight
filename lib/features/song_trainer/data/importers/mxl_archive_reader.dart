import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'import_limits.dart';

abstract final class MxlImportFailureCode {
  static const String invalidArchive = 'songImport.mxl.invalidArchive';
  static const String invalidEntryPath = 'songImport.mxl.invalidEntryPath';
  static const String duplicateEntryPath = 'songImport.mxl.duplicateEntryPath';
  static const String symlink = 'songImport.mxl.symlink';
  static const String nestedArchive = 'songImport.mxl.nestedArchive';
  static const String invalidContainer = 'songImport.mxl.invalidContainer';
  static const String invalidRoot = 'songImport.mxl.invalidRoot';
}

final class MxlArchiveEntry {
  const MxlArchiveEntry(
    this.path,
    this.bytes, {
    this.isSymlink = false,
    int? byteLength,
  }) : byteLength = byteLength ?? bytes.length;

  final String path;
  final List<int> bytes;
  final bool isSymlink;
  final int byteLength;
}

final class MxlArchiveRead {
  const MxlArchiveRead.success(this.scoreBytes) : failureCode = null;
  const MxlArchiveRead.failure(this.failureCode) : scoreBytes = null;
  final List<int>? scoreBytes;
  final String? failureCode;
}

/// Validates every ZIP entry before selecting the MXL root score; never extracts to disk.
final class MxlArchiveReader {
  const MxlArchiveReader();

  MxlArchiveRead read(List<int> bytes, ImportLimits limits) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (_) {
      return const MxlArchiveRead.failure(MxlImportFailureCode.invalidArchive);
    }
    final entries = archive.files
        .map(
          (entry) => MxlArchiveEntry(
            entry.name,
            const <int>[],
            isSymlink: entry.isSymbolicLink,
            byteLength: entry.isFile ? entry.size : 0,
          ),
        )
        .toList(growable: false);
    final validation = validateEntryPaths(entries, limits);
    if (validation.failureCode != null) {
      return MxlArchiveRead.failure(validation.failureCode!);
    }
    final containerEntry = archive.files
        .where((entry) => _canonical(entry.name) == 'META-INF/container.xml')
        .firstOrNull;
    if (containerEntry == null) {
      return const MxlArchiveRead.failure(
        MxlImportFailureCode.invalidContainer,
      );
    }
    final rootPath = _rootPath(containerEntry.content);
    if (rootPath == null) {
      return const MxlArchiveRead.failure(
        MxlImportFailureCode.invalidContainer,
      );
    }
    final scoreEntry = archive.files
        .where((entry) => _canonical(entry.name) == rootPath)
        .firstOrNull;
    if (scoreEntry == null || !scoreEntry.name.toLowerCase().endsWith('.xml')) {
      return const MxlArchiveRead.failure(MxlImportFailureCode.invalidRoot);
    }
    return MxlArchiveRead.success(scoreEntry.content);
  }

  MxlArchiveRead validateEntryPaths(
    List<MxlArchiveEntry> entries,
    ImportLimits limits,
  ) {
    if (entries.length > limits.maxArchiveEntryCount) {
      return const MxlArchiveRead.failure(
        ImportLimitFailureCode.archiveEntryCountExceeded,
      );
    }
    var extracted = 0;
    final canonical = <String>{};
    for (final entry in entries) {
      final path = _canonical(entry.path);
      if (entry.isSymlink) {
        return const MxlArchiveRead.failure(MxlImportFailureCode.symlink);
      }
      if (!_isSafePath(entry.path) || path.isEmpty) {
        return const MxlArchiveRead.failure(
          MxlImportFailureCode.invalidEntryPath,
        );
      }
      if (!canonical.add(path)) {
        return const MxlArchiveRead.failure(
          MxlImportFailureCode.duplicateEntryPath,
        );
      }
      if (path.toLowerCase().endsWith('.mxl') ||
          path.toLowerCase().endsWith('.zip')) {
        return const MxlArchiveRead.failure(MxlImportFailureCode.nestedArchive);
      }
      extracted += entry.byteLength;
      if (extracted > limits.maxExtractedBytes) {
        return const MxlArchiveRead.failure(
          ImportLimitFailureCode.extractedBytesExceeded,
        );
      }
    }
    return const MxlArchiveRead.success(<int>[]);
  }
}

String? _rootPath(List<int> bytes) {
  final String raw;
  try {
    raw = utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    return null;
  }
  if (RegExp(r'<!DOCTYPE', caseSensitive: false).hasMatch(raw)) return null;
  try {
    final root = XmlDocument.parse(raw).rootElement;
    if (root.name.local != 'container') return null;
    final path = root
        .findAllElements('rootfile')
        .firstOrNull
        ?.getAttribute('full-path');
    return path == null || !_isSafePath(path) ? null : _canonical(path);
  } on XmlException {
    return null;
  }
}

bool _isSafePath(String path) =>
    !path.startsWith('/') &&
    !path.startsWith('\\') &&
    !RegExp(r'^[a-zA-Z]:').hasMatch(path) &&
    path
        .split(RegExp(r'[/\\]+'))
        .every((part) => part.isNotEmpty && part != '.' && part != '..');
String _canonical(String path) => path
    .replaceAll('\\', '/')
    .split('/')
    .where((part) => part.isNotEmpty && part != '.')
    .join('/');
