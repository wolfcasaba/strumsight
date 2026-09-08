import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// One audio file the user chose, already read into memory.
///
/// The plugin's own `XFile` never leaves this boundary: the application layer
/// receives bytes plus a display name, so no platform object (and no
/// filesystem path) reaches application state or a persisted document.
final class PickedAudioFile {
  PickedAudioFile({required this.displayName, required List<int> bytes})
    : bytes = Uint8List.fromList(bytes);

  /// The file name as the OS reported it — display/provenance only.
  final String displayName;

  final Uint8List bytes;

  /// Lower-case extension without the dot, or null when the name carries
  /// none. Used to decide whether this build can decode the file at all.
  String? get extension {
    final separator = displayName.lastIndexOf('.');
    if (separator <= 0 || separator == displayName.length - 1) return null;
    return displayName.substring(separator + 1).toLowerCase();
  }
}

/// Platform boundary for choosing an audio file to ANALYSE.
///
/// Deliberately its own port, next to the Song Trainer's notation and
/// backing-audio pickers (`file_picker_adapter.dart`): one picker with one
/// accepted-type list can only be right for one flow, and the cross-feature
/// architecture rule forbids reaching into another feature's data layer. The
/// PLUGIN is the same one the app already ships (`file_selector`) — this
/// round adds no second picker dependency.
abstract interface class AnalysisAudioFilePicker {
  Future<PickedAudioFile?> pickAnalysisAudioFile();
}

/// Production adapter over `file_selector`.
final class PlatformAnalysisAudioFilePicker implements AnalysisAudioFilePicker {
  const PlatformAnalysisAudioFilePicker();

  /// The container formats the picker OFFERS. The list is deliberately wider
  /// than [decodableExtensions]: a user who taps "Import file" with an MP3 in
  /// hand must be able to select it and be told, in words, that this build
  /// cannot decode it — a picker that hides the file leaves the same user
  /// with no explanation at all.
  static const List<String> offeredExtensions = <String>[
    'wav',
    'mp3',
    'm4a',
    'aac',
    'ogg',
    'opus',
    'flac',
  ];

  /// What this build can actually turn into PCM, MEASURED against the shipped
  /// dependency set: `WavDecoder` (`lib/core/audio/codec/wav_decoder.dart`) is
  /// the only decoder in the tree, and the app ships no platform/compressed
  /// audio decoder (`audioplayers` plays, it does not expose PCM). Adding a
  /// compressed format here without a decoder behind it would turn an honest
  /// "cannot import" message into a silent failure.
  static const Set<String> decodableExtensions = <String>{'wav'};

  static const XTypeGroup _audioTypeGroup = XTypeGroup(
    label: 'StrumSight analysis audio',
    extensions: offeredExtensions,
  );

  @override
  Future<PickedAudioFile?> pickAnalysisAudioFile() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_audioTypeGroup],
    );
    if (file == null) return null;
    return PickedAudioFile(
      displayName: file.name,
      bytes: await file.readAsBytes(),
    );
  }
}
