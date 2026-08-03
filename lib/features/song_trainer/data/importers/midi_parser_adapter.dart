import 'song_importer.dart';

abstract final class MidiParserFailureCode {
  static const String invalidHeader = 'songImport.midi.invalidHeader';
  static const String invalidChunk = 'songImport.midi.invalidChunk';
  static const String unsupportedFormat = 'songImport.midi.unsupportedFormat';
  static const String smpteUnsupported = 'songImport.midi.smpteUnsupported';
  static const String invalidEvent = 'songImport.midi.invalidEvent';
}

final class MidiFileData {
  const MidiFileData(this.format, this.ppq, this.tracks);
  final int format;
  final int ppq;
  final List<List<MidiEventData>> tracks;
}

final class MidiEventData {
  const MidiEventData({
    required this.tick,
    required this.track,
    required this.kind,
    this.channel,
    this.data = const <int>[],
  });
  final int tick;
  final int track;
  final int kind;
  final int? channel;
  final List<int> data;
}

final class MidiParseResult {
  const MidiParseResult.file(this.file) : failureCode = null, cancelled = false;
  const MidiParseResult.failure(this.failureCode)
    : file = null,
      cancelled = false;
  const MidiParseResult.cancelled()
    : file = null,
      failureCode = null,
      cancelled = true;
  final MidiFileData? file;
  final String? failureCode;
  final bool cancelled;
}

/// Narrow, observable SMF 0/1 PPQ decoder. It deliberately accepts no other
/// container or timing variant at the import trust boundary.
final class MidiParserAdapter {
  const MidiParserAdapter();

  MidiParseResult parse(List<int> bytes, CancellationToken cancellationToken) {
    try {
      if (bytes.length < 14 ||
          _ascii(bytes, 0) != 'MThd' ||
          _u32(bytes, 4) != 6) {
        return const MidiParseResult.failure(
          MidiParserFailureCode.invalidHeader,
        );
      }
      final format = _u16(bytes, 8);
      final count = _u16(bytes, 10);
      final division = _u16(bytes, 12);
      if (format > 1 || count == 0) {
        return const MidiParseResult.failure(
          MidiParserFailureCode.unsupportedFormat,
        );
      }
      if (division & 0x8000 != 0) {
        return const MidiParseResult.failure(
          MidiParserFailureCode.smpteUnsupported,
        );
      }
      if (division == 0) {
        return const MidiParseResult.failure(
          MidiParserFailureCode.invalidHeader,
        );
      }
      var offset = 14;
      final tracks = <List<MidiEventData>>[];
      for (var track = 0; track < count; track++) {
        if (cancellationToken.isCancelled) {
          return const MidiParseResult.cancelled();
        }
        if (offset + 8 > bytes.length || _ascii(bytes, offset) != 'MTrk') {
          return const MidiParseResult.failure(
            MidiParserFailureCode.invalidChunk,
          );
        }
        final length = _u32(bytes, offset + 4);
        offset += 8;
        if (length > bytes.length - offset) {
          return const MidiParseResult.failure(
            MidiParserFailureCode.invalidChunk,
          );
        }
        final parsed = _track(
          bytes.sublist(offset, offset + length),
          track,
          cancellationToken,
        );
        if (parsed == null) {
          return cancellationToken.isCancelled
              ? const MidiParseResult.cancelled()
              : const MidiParseResult.failure(
                  MidiParserFailureCode.invalidEvent,
                );
        }
        tracks.add(parsed);
        offset += length;
      }
      if (offset != bytes.length) {
        return const MidiParseResult.failure(
          MidiParserFailureCode.invalidChunk,
        );
      }
      return MidiParseResult.file(MidiFileData(format, division, tracks));
    } on RangeError {
      return const MidiParseResult.failure(MidiParserFailureCode.invalidChunk);
    }
  }

  List<MidiEventData>? _track(
    List<int> bytes,
    int track,
    CancellationToken token,
  ) {
    var offset = 0, tick = 0, running = -1;
    final events = <MidiEventData>[];
    while (offset < bytes.length) {
      if (token.isCancelled) return null;
      final delta = _vlq(bytes, offset);
      if (delta == null) return null;
      offset = delta.next;
      tick += delta.value;
      if (offset >= bytes.length) return null;
      var status = bytes[offset++];
      if (status < 0x80) {
        if (running < 0) return null;
        offset--;
        status = running;
      }
      if (status >= 0x80 && status <= 0xef) {
        running = status;
        final type = status & 0xf0;
        final needed = type == 0xc0 || type == 0xd0 ? 1 : 2;
        if (offset + needed > bytes.length) return null;
        final data = bytes.sublist(offset, offset + needed);
        offset += needed;
        events.add(
          MidiEventData(
            tick: tick,
            track: track,
            kind: type,
            channel: status & 0x0f,
            data: data,
          ),
        );
      } else if (status == 0xff) {
        running = -1;
        if (offset >= bytes.length) return null;
        final type = bytes[offset++];
        final length = _vlq(bytes, offset);
        if (length == null) return null;
        offset = length.next;
        if (length.value > bytes.length - offset) return null;
        final data = bytes.sublist(offset, offset + length.value);
        if (type == 0x51 &&
            data.length == 3 &&
            data[0] == 0 &&
            data[1] == 0 &&
            data[2] == 0) {
          return null;
        }
        events.add(
          MidiEventData(
            tick: tick,
            track: track,
            kind: 0x100 + type,
            data: data,
          ),
        );
        offset += length.value;
      } else if (status == 0xf0 || status == 0xf7) {
        running = -1;
        final length = _vlq(bytes, offset);
        if (length == null) return null;
        offset = length.next;
        if (length.value > bytes.length - offset) return null;
        offset += length.value;
      } else {
        return null;
      }
    }
    return events;
  }
}

final class _Vlq {
  const _Vlq(this.value, this.next);
  final int value;
  final int next;
}

_Vlq? _vlq(List<int> bytes, int offset) {
  var value = 0;
  for (var i = 0; i < 4; i++) {
    if (offset >= bytes.length) return null;
    final b = bytes[offset++];
    value = (value << 7) | (b & 0x7f);
    if (b & 0x80 == 0) return _Vlq(value, offset);
  }
  return null;
}

int _u16(List<int> b, int o) => (b[o] << 8) | b[o + 1];
int _u32(List<int> b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
String _ascii(List<int> b, int o) => String.fromCharCodes(b.sublist(o, o + 4));
