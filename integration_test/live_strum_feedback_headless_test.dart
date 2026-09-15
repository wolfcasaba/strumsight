// Headless on-device proof of the strum feedback chain (round strum-strings).
//
// The emulator has no usable microphone, so the REAL engine (isolate, DSP,
// CRNN, the shape-informed seam) is fed a real-guitar WAV through the
// capture-factory seam at real-time pace, and the Live screen is watched for
// the two per-strum signals: onsetSeq (the hit, onset-first) and strumSeq
// (the direction verdict). Screenshots are taken at the first hits.
//
// Run (device/emulator attached, WAV pushed to the device first):
//   adb push <8 s guitar excerpt>.wav /sdcard/Download/strumsight_probe.wav
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/live_strum_feedback_headless_test.dart \
//     -d emulator-5554
// Optional: --dart-define=STRUMSIGHT_PROBE_WAV=<device path>.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:strumsight/core/audio/capture/audio_capture.dart';
import 'package:strumsight/core/audio/codec/wav_decoder.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/core/widgets/strum_burst_overlay.dart';
import 'package:strumsight/features/live/model/live_frame.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../test/support/fake_audio.dart';
import '../test/support/preference_store.dart';

const _wavPath = String.fromEnvironment(
  'STRUMSIGHT_PROBE_WAV',
  defaultValue: '/sdcard/Download/strumsight_probe.wav',
);

/// Streams a decoded WAV into the engine in real time, 1024 samples a tick —
/// the same shape a phone mic delivers.
class FileAudioCapture implements AudioCapture {
  FileAudioCapture(this.pcm, this.sampleRate, {this.chunk = 1024});

  final List<double> pcm;
  final int sampleRate;
  final int chunk;
  Timer? _timer;
  int _pos = 0;

  bool get exhausted => _pos >= pcm.length;

  @override
  Future<int> start(void Function(List<double> chunk) onChunk) async {
    final period = Duration(microseconds: (chunk * 1e6 / sampleRate).round());
    _timer = Timer.periodic(period, (t) {
      if (_pos >= pcm.length) {
        t.cancel();
        return;
      }
      final end = math.min(_pos + chunk, pcm.length);
      onChunk(pcm.sublist(_pos, end));
      _pos = end;
    });
    return sampleRate;
  }

  @override
  Future<void> stop() async => _timer?.cancel();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real engine fed a guitar WAV: hits then directions on Live', (
    tester,
  ) async {
    final file = File(_wavPath);
    expect(file.existsSync(), isTrue, reason: 'push the probe WAV first');
    final decoded = WavDecoder.decode(file.readAsBytesSync());
    expect(decoded, isNotNull, reason: '16-bit PCM WAV expected');
    final (pcm, sr) = decoded!;
    final capture = FileAudioCapture(pcm, sr);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...preferenceOverrides(),
          ...fakeAudioOverrides(captureFactory: () => capture),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LiveScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LiveScreen)),
    );
    var maxOnset = 0, maxStrum = 0, overlaySeen = 0, shots = 0;
    double? firstOnsetLag; // engine-clock lag of the frame that reported it
    final directions = <String>[];
    final total = pcm.length / sr;
    final deadline = DateTime.now().add(
      Duration(milliseconds: (total * 1000).round() + 1500),
    );
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 50));
      final LiveFrame? f = container.read(liveFrameProvider).value;
      if (f == null) continue;
      if (f.onsetSeq > maxOnset) {
        maxOnset = f.onsetSeq;
        firstOnsetLag ??= f.engineTimeSec - f.latestOnsetTime;
        if (shots < 3) {
          await binding.takeScreenshot('live-hit-${++shots}');
        }
      }
      if (f.strumSeq > maxStrum) {
        maxStrum = f.strumSeq;
        directions.add(f.latestStrum?.isDown == true ? 'D' : 'U');
      }
      if (find.byKey(StrumBurstOverlay.overlayKey).evaluate().isNotEmpty) {
        overlaySeen++;
      }
    }

    // ignore: avoid_print
    print(
      'headless live probe: ${total.toStringAsFixed(1)} s of audio, '
      'onsets $maxOnset, strums $maxStrum ($directions), '
      'overlay frames $overlaySeen, first-onset report lag '
      '${((firstOnsetLag ?? -1) * 1000).toStringAsFixed(0)} ms',
    );
    expect(capture.exhausted, isTrue, reason: 'the whole clip was fed');
    expect(maxOnset, greaterThanOrEqualTo(3), reason: 'hits were heard');
    expect(maxStrum, greaterThanOrEqualTo(1), reason: 'a direction landed');
    expect(overlaySeen, greaterThan(0), reason: 'the strum spark fired');
  });
}
