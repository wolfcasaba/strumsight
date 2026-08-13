/// Disk-backed, bounded cache for derived Audio Analysis results.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/cache/analysis_cache_key.dart';

/// LRU cache independent from the durable analysis-document repository.
final class AnalysisCache {
  AnalysisCache._({
    required this.directory,
    required this._clock,
    required this.maxEntries,
    required this.maxBytes,
  });

  /// Inclusive entry cap fixed by ADR 0248.
  static const int defaultMaxEntries = 20;

  /// Inclusive byte cap fixed by ADR 0248 (50 MiB).
  static const int defaultMaxBytes = 52428800;

  final Directory directory;
  final DateTime Function() _clock;
  final int maxEntries;
  final int maxBytes;
  final Map<String, Future<Uint8List>> _inFlight =
      <String, Future<Uint8List>>{};
  int _accessOrdinal = 0;

  /// Opens a self-contained cache directory. No analysis document is read or
  /// modified by this operation.
  static Future<AnalysisCache> openAtDirectory({
    required Directory directory,
    DateTime Function()? clock,
    int maxEntries = AnalysisCache.defaultMaxEntries,
    int maxBytes = AnalysisCache.defaultMaxBytes,
  }) async {
    if (maxEntries <= 0) throw ArgumentError.value(maxEntries, 'maxEntries');
    if (maxBytes <= 0) throw ArgumentError.value(maxBytes, 'maxBytes');
    await directory.create(recursive: true);
    final cache = AnalysisCache._(
      directory: directory,
      clock: clock ?? DateTime.now,
      maxEntries: maxEntries,
      maxBytes: maxBytes,
    );
    cache._accessOrdinal = await cache._largestAccessOrdinal();
    return cache;
  }

  /// Puts one derived result and applies both inclusive LRU caps.
  Future<void> put(
    AnalysisCacheKey key,
    Uint8List payload, {
    String? documentId,
  }) async {
    final entry = _CacheEntry(
      cacheId: key.cacheId,
      payload: payload,
      documentId: documentId,
      accessedAtMicros: _clock().microsecondsSinceEpoch,
      accessOrdinal: ++_accessOrdinal,
    );
    await fileFor(key).writeAsString(jsonEncode(entry.toJson()), flush: true);
    await _evictToLimits();
  }

  /// Returns a cached payload or null for a miss, including corrupt entries.
  Future<Uint8List?> get(AnalysisCacheKey key) async {
    final file = fileFor(key);
    if (!await file.exists()) return null;
    try {
      final entry = _CacheEntry.fromJson(jsonDecode(await file.readAsString()));
      if (entry.cacheId != key.cacheId) throw const FormatException('cache id');
      entry.accessedAtMicros = _clock().microsecondsSinceEpoch;
      entry.accessOrdinal = ++_accessOrdinal;
      await file.writeAsString(jsonEncode(entry.toJson()), flush: true);
      return entry.payload;
    } on FormatException {
      await _discard(file);
      return null;
    } on FileSystemException {
      await _discard(file);
      return null;
    }
  }

  /// Coalesces concurrent misses for the same complete cache key.
  Future<Uint8List> getOrCompute(
    AnalysisCacheKey key,
    Future<Uint8List> Function() compute,
  ) async {
    final cached = await get(key);
    if (cached != null) return cached;
    final id = key.cacheId;
    final pending = _inFlight[id];
    if (pending != null) return pending;
    final created = () async {
      try {
        final value = await compute();
        await put(key, value);
        return value;
      } finally {
        _inFlight.remove(id);
      }
    }();
    _inFlight[id] = created;
    return created;
  }

  /// Invalidates only cache entries associated with [documentId].
  Future<void> invalidate(String documentId) async {
    for (final record in await _readEntries()) {
      if (record.entry.documentId == documentId) await _discard(record.file);
    }
  }

  /// Removes all derived cache entries without touching saved sessions.
  Future<void> purge() async {
    for (final record in await _readEntries()) {
      await _discard(record.file);
    }
  }

  /// Number of valid cached entries, useful for deterministic diagnostics.
  Future<int> entryCount() async => (await _readEntries()).length;

  /// Total decoded payload bytes, not JSON/base64 container size.
  Future<int> totalBytes() async => (await _readEntries()).fold<int>(
    0,
    (total, record) => total + record.entry.payload.length,
  );

  /// The entry file name is derived solely from a complete cache key.
  File fileFor(AnalysisCacheKey key) =>
      File('${directory.path}/${key.cacheId}.json');

  Future<void> _evictToLimits() async {
    final records = await _readEntries();
    var bytes = records.fold<int>(
      0,
      (total, record) => total + record.entry.payload.length,
    );
    records.sort((left, right) => left.entry.compareAccess(right.entry));
    while (records.length > maxEntries || bytes > maxBytes) {
      final oldest = records.removeAt(0);
      bytes -= oldest.entry.payload.length;
      await _discard(oldest.file);
    }
  }

  Future<int> _largestAccessOrdinal() async {
    var largest = 0;
    for (final record in await _readEntries()) {
      if (record.entry.accessOrdinal > largest) {
        largest = record.entry.accessOrdinal;
      }
    }
    return largest;
  }

  Future<List<_CacheRecord>> _readEntries() async {
    final records = <_CacheRecord>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        records.add(
          _CacheRecord(
            entity,
            _CacheEntry.fromJson(jsonDecode(await entity.readAsString())),
          ),
        );
      } on FormatException {
        await _discard(entity);
      } on FileSystemException {
        await _discard(entity);
      }
    }
    return records;
  }

  Future<void> _discard(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A failed best-effort cleanup is still a cache miss for this caller.
    }
  }
}

final class _CacheRecord {
  const _CacheRecord(this.file, this.entry);

  final File file;
  final _CacheEntry entry;
}

final class _CacheEntry {
  _CacheEntry({
    required this.cacheId,
    required this.payload,
    required this.documentId,
    required this.accessedAtMicros,
    required this.accessOrdinal,
  });

  final String cacheId;
  final Uint8List payload;
  final String? documentId;
  int accessedAtMicros;
  int accessOrdinal;

  factory _CacheEntry.fromJson(Object? source) {
    if (source is! Map<String, Object?>) throw const FormatException('entry');
    final cacheId = source['cacheId'];
    final encodedPayload = source['payload'];
    final documentId = source['documentId'];
    final accessedAtMicros = source['accessedAtMicros'];
    final accessOrdinal = source['accessOrdinal'];
    if (cacheId is! String ||
        encodedPayload is! String ||
        documentId is! String && documentId != null ||
        accessedAtMicros is! int ||
        accessOrdinal is! int) {
      throw const FormatException('entry fields');
    }
    try {
      return _CacheEntry(
        cacheId: cacheId,
        payload: Uint8List.fromList(base64Decode(encodedPayload)),
        documentId: documentId as String?,
        accessedAtMicros: accessedAtMicros,
        accessOrdinal: accessOrdinal,
      );
    } on FormatException {
      throw const FormatException('payload');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'cacheId': cacheId,
    'payload': base64Encode(payload),
    'documentId': documentId,
    'accessedAtMicros': accessedAtMicros,
    'accessOrdinal': accessOrdinal,
  };

  int compareAccess(_CacheEntry other) {
    final byTime = accessedAtMicros.compareTo(other.accessedAtMicros);
    return byTime != 0 ? byTime : accessOrdinal.compareTo(other.accessOrdinal);
  }
}
