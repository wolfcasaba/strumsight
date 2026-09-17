import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/import/audio_song_import_controller.dart';
import '../../application/import/song_import_effect.dart';
import '../../application/import/song_import_state.dart';
import '../../application/song_trainer_providers.dart';
import '../widgets/guitar_pro_conversion_guidance.dart';
import 'song_editor_screen.dart';
import 'song_import_preview_screen.dart';

/// Presentation owner of the picker effect; the controller retains no plugin
/// object and the adapter returns only an ImportSourceFile.
///
/// K3: the screen offers TWO sources. The notation path is unchanged; the
/// audio path runs its own operation (`AudioSongImportController`) and lands
/// the user in the EDITOR, never in practice — what it produces is a draft.
final class SongImportScreen extends ConsumerStatefulWidget {
  const SongImportScreen({super.key});

  @override
  ConsumerState<SongImportScreen> createState() => _SongImportScreenState();
}

final class _SongImportScreenState extends ConsumerState<SongImportScreen> {
  StreamSubscription<SongImportEffect>? _effects;
  StreamSubscription<SongImportEffect>? _audioEffects;
  AudioSongImportController? _audio;

  @override
  void initState() {
    super.initState();
    final controller = ref.read(songImportControllerProvider);
    _effects = controller.effects.listen((effect) async {
      if (effect is RequestFilePickerEffect) {
        final source = await ref
            .read(songFilePickerAdapterProvider)
            .pickSongFile();
        await controller.selectSource(source);
      }
    });
  }

  @override
  void dispose() {
    // Leaving the screen cancels the audio operation: a decode or analysis
    // still in flight is disowned, its result dropped, and no isolate is
    // kept alive by this route.
    _audio?.cancel();
    _effects?.cancel();
    _audioEffects?.cancel();
    super.dispose();
  }

  /// Subscribes to the audio controller's effects.
  ///
  /// Bound from `build`, not `initState`: the controller provider is
  /// auto-disposed, so the instance that survives is the one the build's
  /// `ref.watch` keeps alive. Binding earlier could subscribe to an instance
  /// that is thrown away before the first frame.
  void _bindAudio(AudioSongImportController controller) {
    if (identical(_audio, controller)) return;
    _audioEffects?.cancel();
    _audio = controller;
    _audioEffects = controller.effects.listen((effect) {
      if (effect is SongImportSucceededEffect) {
        _openEditor(effect.songId.value);
      }
    });
  }

  /// The draft lands in the EDITOR, never straight in practice.
  ///
  /// A `Navigator` push rather than a router push: this screen is reached
  /// imperatively from the Library's floating action button, so a GoRouter
  /// page would be inserted BELOW that imperative route and never become
  /// visible. The widget is the same one the `songTrainerEditor` route
  /// builds, and no route string is written here.
  void _openEditor(String songId) {
    if (!mounted) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => SongEditorScreen(songId: songId)),
    );
  }

  Future<void> _pickAudio() async {
    final controller = _audio ?? ref.read(audioSongImportControllerProvider);
    controller.beginSelection();
    final picker = ref.read(songFilePickerAdapterProvider);
    final source = await picker.pickAudioFile();
    await controller.selectSource(source);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final controller = ref.read(songImportControllerProvider);
    final state = ref.watch(songImportStateProvider).value ?? controller.state;
    final audioController = ref.watch(audioSongImportControllerProvider);
    _bindAudio(audioController);
    final audioState =
        ref.watch(audioSongImportStateProvider).value ?? audioController.state;
    if (state.phase == SongImportPhase.preview && state.preview != null) {
      return SongImportPreviewScreen(preview: state.preview!);
    }
    final sheetActive =
        state.phase != SongImportPhase.idle &&
        state.phase != SongImportPhase.failure &&
        state.phase != SongImportPhase.cancelled &&
        state.phase != SongImportPhase.success;
    final active = sheetActive || audioState.isActive;
    final audioFailed = audioState.phase == AudioSongImportPhase.failure;
    final sheetFailed = state.phase == SongImportPhase.failure;
    final failureCode = audioFailed
        ? audioState.failureCode
        : (sheetFailed ? state.failureCode : null);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.songImportTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SsSpacing.space6),
          child: Center(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (active) ...<Widget>[
                  // Indeterminate on purpose: neither the platform decoder
                  // nor the analyzer reports progress, and a percentage that
                  // is not measured would be a lie about how far along the
                  // import is.
                  const LinearProgressIndicator(
                    key: Key('song-import-progress'),
                  ),
                  const SizedBox(height: SsSpacing.space4),
                  Text(
                    _workingLabel(l10n, audioState),
                    style: typography.bodyMedium.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ] else ...<Widget>[
                  // A3(b)/A4: a failure phase is the blocking-error producer
                  // that never reaches the preview screen. It gets the SAME
                  // error icon + error color role + a distinct semantic label
                  // the fatal preview path uses (ImportWarningList), so the
                  // blocking case never reads like an ordinary warning, and
                  // no "continue anyway" affordance is offered next to it.
                  if (sheetFailed || audioFailed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: SsSpacing.space4),
                      child: Semantics(
                        label: l10n.songImportBlockingSemantic(
                          failureCode ?? l10n.songImportFailed,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(Icons.error_outline, color: colors.danger),
                            const SizedBox(width: SsSpacing.space2),
                            Flexible(
                              child: Text(
                                failureCode == null
                                    ? l10n.songImportFailed
                                    : l10n.songImportBlockingFailure(
                                        failureCode,
                                      ),
                                style: typography.bodyMedium.copyWith(
                                  color: colors.danger,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  SsButton(
                    onPressed: controller.requestSelection,
                    icon: Icons.upload_file_outlined,
                    label: l10n.songImportChooseFile,
                  ),
                  const SizedBox(height: SsSpacing.space4),
                  SsButton(
                    key: const Key('song-import-choose-audio'),
                    onPressed: _pickAudio,
                    variant: SsButtonVariant.secondary,
                    icon: Icons.audiotrack,
                    label: l10n.songImportChooseAudioFile,
                  ),
                  const SizedBox(height: SsSpacing.space2),
                  Text(
                    l10n.songImportAudioHint,
                    style: typography.bodyMedium.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
                if (active)
                  TextButton(
                    key: const Key('song-import-cancel'),
                    onPressed: () {
                      audioController.cancel();
                      unawaited(controller.cancel());
                    },
                    child: Text(l10n.songImportCancel),
                  ),
                if (!active) ...<Widget>[
                  const SizedBox(height: SsSpacing.space8),
                  const GuitarProConversionGuidance(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Names the stage the user is waiting on. The audio operation has three
  /// distinguishable ones; the notation flow keeps its single message.
  static String _workingLabel(
    AppLocalizations l10n,
    AudioSongImportState audio,
  ) {
    return switch (audio.phase) {
      AudioSongImportPhase.decoding => l10n.songImportAudioDecoding,
      AudioSongImportPhase.analyzing => l10n.songImportAudioAnalyzing,
      AudioSongImportPhase.saving => l10n.songImportAudioSaving,
      _ => l10n.songImportWorking,
    };
  }
}
