# StrumSight — strum-direction ML pipeline

The audio-only heuristic (`lib/features/live/engine/dsp/strum_analyzer.dart`) is
maxed at ~88 % aggregate (round 60). The next jump to a trained CRNN
(**F1-any ~93 %, up-strum ~79 %**, arXiv 2508.07973) needs a directionally
**labeled dataset** — which no public source provides. This folder is the
pipeline to build it and train the model. Full spec: `docs/rag/chunks/018`.

## What runs where
- **Data pipeline** — `features.py`, `synth.py`, `prepare_dataset.py`,
  `test_pipeline.py`: **pure NumPy**, runs on any box (incl. the ARM64 dev VM).
  `python3 ml/test_pipeline.py` proves it end-to-end on synthetic data.
- **Model** — `train.py`: needs TensorFlow → run in CI or Colab (the ARM64 dev
  VM can't build the APK *or* run TF).

## Collect data (the key enabler)
The trick (how the ISMIR-2025 team labeled 94 h): wear **any Wear OS watch /
motion earbud on the strumming wrist** while recording — its accelerometer gives
free down/up labels aligned to the audio onsets. You never ship the watch; it's
a labeling tool.

Per take, drop two files in a folder (same basename):
```
take001.wav          # mono guitar audio, any sample rate
take001.accel.csv    # two columns: t_seconds,axis   (the swing axis, 200 Hz)
```
- **axis** = the wrist accelerometer channel that swings opposite ways for
  down vs up. Pick it once per rig; if labels come out inverted, negate it (a
  one-line flip in `prepare_dataset.py`).
- Record varied: tempos (60–160 BPM), chords, dynamics, guitars, rooms/mics,
  and both clean down/up *and* messy real strumming. Aim for thousands of
  onsets; up-strums are the scarce class — over-collect them.

## Build + train
```
python3 ml/test_pipeline.py                 # sanity (NumPy only)
python3 ml/prepare_dataset.py ./recordings dataset.npz
python3 ml/train.py dataset.npz strum_direction.tflite   # TF (CI/Colab)
```
Then augment with ±6-semitone pitch shift (gave +14 % rel. up-strum in the
paper) — add it in `prepare_dataset.py` before training.

## Deploy on device
`train.py` writes `strum_direction.tflite` + `norm.npz` (per-mel mean/std). To
wire it in:
1. Add `tflite_flutter` — **check win32 stays one major** (repo gotcha) and run
   inference in the existing DSP isolate.
2. Compute the SAME 16 kHz / 2048-win / 160-hop / 128-mel log-mel in Dart (the
   `StrumAnalyzer` already has the FFT), standardise with `norm.npz`, run the
   GRU **stateful** one 10 ms hop at a time.
3. Put it behind a flag with the heuristic as fallback; the acceptance gate is
   the real-guitar APK test, not synthetic accuracy.
