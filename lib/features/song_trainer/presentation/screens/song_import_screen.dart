import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/import/song_import_effect.dart';
import '../../application/import/song_import_state.dart';
import '../../application/song_trainer_providers.dart';
import '../widgets/guitar_pro_conversion_guidance.dart';
import 'song_import_preview_screen.dart';

/// Presentation owner of the picker effect; the controller retains no plugin
/// object and the adapter returns only an ImportSourceFile.
final class SongImportScreen extends ConsumerStatefulWidget {
  const SongImportScreen({super.key});

  @override
  ConsumerState<SongImportScreen> createState() => _SongImportScreenState();
}

final class _SongImportScreenState extends ConsumerState<SongImportScreen> {
  StreamSubscription<SongImportEffect>? _effects;

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
    _effects?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(songImportControllerProvider);
    final state = ref.watch(songImportStateProvider).value ?? controller.state;
    if (state.phase == SongImportPhase.preview && state.preview != null) {
      return SongImportPreviewScreen(preview: state.preview!);
    }
    final active =
        state.phase != SongImportPhase.idle &&
        state.phase != SongImportPhase.failure &&
        state.phase != SongImportPhase.cancelled &&
        state.phase != SongImportPhase.success;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.songImportTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (active) ...<Widget>[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(l10n.songImportWorking),
                ] else ...<Widget>[
                  // A3(b)/A4: SongImportPhase.failure is the blocking-error
                  // producer that never reaches the preview screen. It gets
                  // the SAME error icon + error color role + a distinct
                  // semantic label the fatal preview path uses
                  // (ImportWarningList), so the blocking case never reads
                  // like an ordinary warning, and no "continue anyway"
                  // affordance is offered next to it.
                  if (state.phase == SongImportPhase.failure)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Semantics(
                        label: l10n.songImportBlockingSemantic(
                          state.failureCode ?? l10n.songImportFailed,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(
                              Icons.error_outline,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                state.failureCode == null
                                    ? l10n.songImportFailed
                                    : l10n.songImportBlockingFailure(
                                        state.failureCode!,
                                      ),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: controller.requestSelection,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(l10n.songImportChooseFile),
                  ),
                ],
                if (active)
                  TextButton(
                    onPressed: controller.cancel,
                    child: Text(l10n.songImportCancel),
                  ),
                if (!active) ...<Widget>[
                  const SizedBox(height: 32),
                  const GuitarProConversionGuidance(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
