import 'dart:io';

import 'import_limits.dart';

/// Failure raised when a temporary import path or its resource budget is unsafe.
final class ImportWorkspaceException implements Exception {
  const ImportWorkspaceException(this.code);

  final String code;
}

/// Operation-owned temporary directory constrained below an application root.
final class ImportWorkspace {
  ImportWorkspace._({required this._directory, required this.limits});

  final Directory _directory;
  final ImportLimits limits;
  var _writtenBytes = 0;
  Future<void>? _closeFuture;

  /// The path is intentionally available only to data-layer collaborators.
  String get path => _directory.path;

  /// Creates a new workspace under [root] for a single opaque operation ID.
  static Future<ImportWorkspace> open({
    required Directory root,
    required String operationId,
    required ImportLimits limits,
  }) async {
    if (!_isSafeOperationId(operationId)) {
      throw const ImportWorkspaceException('songImport.workspace.invalidPath');
    }
    await root.create(recursive: true);
    final rootPath = await root.resolveSymbolicLinks();
    final directory = Directory(
      '$rootPath${Platform.pathSeparator}$operationId',
    );
    await directory.create();
    final resolvedPath = await directory.resolveSymbolicLinks();
    if (!_isContained(rootPath, resolvedPath)) {
      await directory.delete(recursive: true);
      throw const ImportWorkspaceException('songImport.workspace.invalidPath');
    }
    return ImportWorkspace._(directory: directory, limits: limits);
  }

  /// Creates an empty file after resolving every parent beneath this workspace.
  Future<File> createFile(String relativePath) async {
    final file = await _resolveFile(relativePath);
    await file.parent.create(recursive: true);
    return file;
  }

  /// Writes bytes only when the operation-wide workspace budget permits it.
  Future<File> writeBytes(String relativePath, List<int> bytes) async {
    if (_writtenBytes + bytes.length > limits.maxWorkspaceBytes) {
      throw const ImportWorkspaceException(
        ImportLimitFailureCode.workspaceBytesExceeded,
      );
    }
    final file = await createFile(relativePath);
    await file.writeAsBytes(bytes, flush: true);
    _writtenBytes += bytes.length;
    return file;
  }

  /// Idempotently deletes all temporary operation contents.
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    if (await _directory.exists()) await _directory.delete(recursive: true);
  }

  Future<File> _resolveFile(String relativePath) async {
    final components = relativePath.split(Platform.pathSeparator);
    if (relativePath.isEmpty ||
        File(relativePath).isAbsolute ||
        components.any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw const ImportWorkspaceException('songImport.workspace.invalidPath');
    }

    var current = _directory;
    for (final component in components.take(components.length - 1)) {
      final next = Directory(
        '${current.path}${Platform.pathSeparator}$component',
      );
      final type = await FileSystemEntity.type(next.path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw const ImportWorkspaceException(
          'songImport.workspace.invalidPath',
        );
      }
      if (type == FileSystemEntityType.notFound) await next.create();
      if (!await next.exists()) {
        throw const ImportWorkspaceException(
          'songImport.workspace.invalidPath',
        );
      }
      current = next;
    }
    return File('${current.path}${Platform.pathSeparator}${components.last}');
  }

  static bool _isSafeOperationId(String value) =>
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);

  static bool _isContained(String rootPath, String candidatePath) =>
      candidatePath == rootPath ||
      candidatePath.startsWith('$rootPath${Platform.pathSeparator}');
}
