# StrumSight Phase 1 — Algorithm Validation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Python harness that measures chord-recognition accuracy and — critically — **strum-direction (↓/↑) accuracy** on labeled guitar clips, producing the go/no-go number that decides whether the Live-first C++ build proceeds.

**Architecture:** A standalone `validation/` Python package (separate from the Flutter tree — it never ships to the phone; it validates the algorithm we will port to C++ in Phase 2). Pure functions per concern: `chords` (CQT→chroma→24 template match), `onsets` (onset times), `direction` (sub-band onset-order heuristic), `dataset` (clips + ground-truth labels), `evaluate` (run pipeline, compute metrics). Unit tests use **synthetic signals** so they pass with zero recordings; the accuracy report runs on real clips when present.

**Tech Stack:** Python 3, librosa, numpy, soundfile, pytest. No Flutter, no C++ yet.

---

## File Structure

```
validation/                     # NOT under lib/ — dev-only, gitignored data
├── requirements.txt
├── README.md
├── strumsight_val/
│   ├── __init__.py
│   ├── chords.py               # chroma templates + chord match
│   ├── onsets.py               # onset detection wrapper
│   ├── direction.py            # sub-band onset-order direction heuristic
│   ├── dataset.py              # load clip + label JSON
│   └── evaluate.py             # pipeline + accuracy metrics + CLI
├── tests/
│   ├── conftest.py             # synthetic-signal fixtures
│   ├── test_chords.py
│   ├── test_onsets.py
│   ├── test_direction.py
│   ├── test_dataset.py
│   └── test_evaluate.py
└── data/                       # real clips + labels (gitignored); one committed fixture
    └── .gitkeep
```

**Label schema** (`data/<clip>.json` beside `<clip>.wav`):
```json
{
  "audio": "clip01.wav",
  "bpm": 96,
  "events": [
    {"time": 0.50, "chord": "C",  "direction": "down"},
    {"time": 0.95, "chord": "C",  "direction": "up"},
    {"time": 1.40, "chord": "G",  "direction": "down"}
  ]
}
```

---

### Task 1: Scaffold the validation package

**Files:**
- Create: `validation/requirements.txt`
- Create: `validation/README.md`
- Create: `validation/strumsight_val/__init__.py`
- Create: `validation/tests/conftest.py`
- Create: `validation/data/.gitkeep`
- Modify: `.gitignore` (append validation data rule)

- [ ] **Step 1: Create `validation/requirements.txt`**

```
librosa==0.10.2.post1
numpy>=1.24,<2.0
soundfile>=0.12
pytest>=8.0
```

- [ ] **Step 2: Create `validation/strumsight_val/__init__.py`**

```python
"""StrumSight algorithm-validation harness (dev-only, not shipped)."""
```

- [ ] **Step 3: Create `validation/README.md`**

```markdown
# StrumSight — Phase 1 validation

Dev-only. Measures chord + strum-direction accuracy on labeled guitar clips
before we port the algorithm to C++ (Phase 2).

## Setup
    python -m venv .venv && source .venv/bin/activate
    pip install -r requirements.txt

## Run tests (synthetic signals, no clips needed)
    pytest -q

## Run accuracy report on real clips in data/
    python -m strumsight_val.evaluate data/

Record 5–10 clean guitar clips, hand-label ↓/↑ per strum in `<clip>.json`
(schema in the plan), drop both files in `data/`.
```

- [ ] **Step 4: Create `validation/tests/conftest.py`** (synthetic-signal fixtures reused across tests)

```python
import numpy as np
import pytest

SR = 22050

def _note(freq, dur=0.5, sr=SR, amp=0.5):
    t = np.linspace(0, dur, int(sr * dur), endpoint=False)
    return amp * np.sin(2 * np.pi * freq * t).astype(np.float32)

@pytest.fixture
def sr():
    return SR

@pytest.fixture
def c_major_signal():
    """Sustained C major triad: C4 262, E4 330, G4 392 Hz."""
    sig = _note(262) + _note(330) + _note(392)
    return (sig / np.max(np.abs(sig))).astype(np.float32)

@pytest.fixture
def a_minor_signal():
    """Sustained A minor triad: A3 220, C4 262, E4 330 Hz."""
    sig = _note(220) + _note(262) + _note(330)
    return (sig / np.max(np.abs(sig))).astype(np.float32)

def make_strum(low_freq, high_freq, lead, sr=SR, gap=0.010, dur=0.4):
    """A strum where one band starts `gap` seconds before the other.
    lead='low'  -> bass enters first  (downstroke)
    lead='high' -> treble enters first (upstroke)
    """
    n = int(sr * dur)
    low = np.zeros(n, dtype=np.float32)
    high = np.zeros(n, dtype=np.float32)
    off = int(sr * gap)
    lo = _note(low_freq, dur - gap, sr)
    hi = _note(high_freq, dur - gap, sr)
    if lead == 'low':
        low[:len(lo)] += lo
        high[off:off + len(hi)] += hi
    else:
        high[:len(hi)] += hi
        low[off:off + len(lo)] += lo
    sig = low + high
    return (sig / np.max(np.abs(sig))).astype(np.float32)
```

- [ ] **Step 5: Create `validation/data/.gitkeep`** (empty file) and append to `.gitignore`

```
# StrumSight validation clips (real recordings — do not commit)
validation/data/*.wav
validation/data/*.m4a
validation/data/*.json
!validation/data/.gitkeep
validation/.venv/
```

- [ ] **Step 6: Commit**

```bash
git add validation/ .gitignore
git commit -m "chore(validation): scaffold Phase 1 Python harness"
```

---

### Task 2: Chord templates + matching

**Files:**
- Create: `validation/strumsight_val/chords.py`
- Test: `validation/tests/test_chords.py`

- [ ] **Step 1: Write the failing test**

```python
import numpy as np
from strumsight_val.chords import match_chord, PITCH_CLASSES

def test_c_major_signal_matches_C(c_major_signal, sr):
    assert match_chord(c_major_signal, sr) == "C"

def test_a_minor_signal_matches_Am(a_minor_signal, sr):
    assert match_chord(a_minor_signal, sr) == "Am"

def test_returns_valid_label(c_major_signal, sr):
    label = match_chord(c_major_signal, sr)
    root = label.rstrip("m")
    assert root in PITCH_CLASSES
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd validation && pytest tests/test_chords.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'strumsight_val.chords'`

- [ ] **Step 3: Write minimal implementation**

```python
"""Chord recognition: CQT chroma correlated against 24 maj/min templates."""
import numpy as np
import librosa

PITCH_CLASSES = ["C", "C#", "D", "D#", "E", "F",
                 "F#", "G", "G#", "A", "A#", "B"]

# Semitone offsets from the root for each quality.
_QUALITIES = {"": (0, 4, 7), "m": (0, 3, 7)}

def _build_templates():
    """Return (labels, matrix[24, 12]) unit-norm binary chroma templates."""
    labels, rows = [], []
    for quality, offsets in _QUALITIES.items():
        for root in range(12):
            vec = np.zeros(12, dtype=np.float32)
            for o in offsets:
                vec[(root + o) % 12] = 1.0
            vec /= np.linalg.norm(vec)
            labels.append(PITCH_CLASSES[root] + quality)
            rows.append(vec)
    return labels, np.stack(rows)

_LABELS, _TEMPLATES = _build_templates()

def chroma_vector(y, sr):
    """Mean CQT chroma over the whole segment, L2-normalised (12,)."""
    chroma = librosa.feature.chroma_cqt(y=y, sr=sr)
    v = chroma.mean(axis=1)
    n = np.linalg.norm(v)
    return v / n if n > 0 else v

def match_chord(y, sr):
    """Best-matching chord label for signal y."""
    v = chroma_vector(y, sr)
    scores = _TEMPLATES @ v          # cosine similarity (both unit-norm)
    return _LABELS[int(np.argmax(scores))]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd validation && pytest tests/test_chords.py -v`
Expected: PASS (3 passed)

- [ ] **Step 5: Commit**

```bash
git add validation/strumsight_val/chords.py validation/tests/test_chords.py
git commit -m "feat(validation): CQT chroma chord matching (24 maj/min templates)"
```

---

### Task 3: Onset detection wrapper

**Files:**
- Create: `validation/strumsight_val/onsets.py`
- Test: `validation/tests/test_onsets.py`

- [ ] **Step 1: Write the failing test**

```python
import numpy as np
from strumsight_val.onsets import detect_onsets

def test_detects_three_evenly_spaced_strums(sr):
    # three 0.3 s bursts with 0.2 s silence between -> onsets near 0.0, 0.5, 1.0
    burst = np.sin(2 * np.pi * 220 * np.linspace(0, 0.3, int(sr*0.3), endpoint=False)).astype(np.float32)
    sil = np.zeros(int(sr*0.2), dtype=np.float32)
    y = np.concatenate([burst, sil, burst, sil, burst]).astype(np.float32)
    onsets = detect_onsets(y, sr)
    assert len(onsets) >= 3
    # first onset near the start
    assert onsets[0] < 0.15

def test_silence_has_no_onsets(sr):
    y = np.zeros(sr, dtype=np.float32)
    assert detect_onsets(y, sr) == []
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd validation && pytest tests/test_onsets.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'strumsight_val.onsets'`

- [ ] **Step 3: Write minimal implementation**

```python
"""Onset detection wrapper (thin adapter over librosa; ported to aubio in C++)."""
import numpy as np
import librosa

def detect_onsets(y, sr):
    """Return a sorted list of onset times in seconds."""
    if not np.any(y):
        return []
    times = librosa.onset.onset_detect(
        y=y, sr=sr, units="time", backtrack=True
    )
    return sorted(float(t) for t in times)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd validation && pytest tests/test_onsets.py -v`
Expected: PASS (2 passed)

- [ ] **Step 5: Commit**

```bash
git add validation/strumsight_val/onsets.py validation/tests/test_onsets.py
git commit -m "feat(validation): onset detection wrapper"
```

---

### Task 4: Sub-band direction heuristic (the differentiator)

**Files:**
- Create: `validation/strumsight_val/direction.py`
- Test: `validation/tests/test_direction.py`

- [ ] **Step 1: Write the failing test**

```python
from strumsight_val.conftest_helpers import _import_make_strum
from strumsight_val.direction import strum_direction
from tests.conftest import make_strum   # noqa: E402

def test_bass_first_is_down(sr):
    y = make_strum(low_freq=110, high_freq=1760, lead="low", sr=sr)
    assert strum_direction(y, sr) == "down"

def test_treble_first_is_up(sr):
    y = make_strum(low_freq=110, high_freq=1760, lead="high", sr=sr)
    assert strum_direction(y, sr) == "up"
```

> Note: importing `make_strum` from `tests.conftest` requires running pytest from
> `validation/` with `rootdir` there; the `conftest_helpers` import line above is a
> deliberate failing stub removed in Step 3.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd validation && pytest tests/test_direction.py -v`
Expected: FAIL — `ModuleNotFoundError` for `strumsight_val.direction` / `conftest_helpers`

- [ ] **Step 3: Fix the test import and write the implementation**

Replace `validation/tests/test_direction.py` with:

```python
from strumsight_val.direction import strum_direction
from tests.conftest import make_strum

def test_bass_first_is_down(sr):
    y = make_strum(low_freq=110, high_freq=1760, lead="low", sr=sr)
    assert strum_direction(y, sr) == "down"

def test_treble_first_is_up(sr):
    y = make_strum(low_freq=110, high_freq=1760, lead="high", sr=sr)
    assert strum_direction(y, sr) == "up"
```

Create `validation/strumsight_val/direction.py`:

```python
"""Strum direction via sub-band onset order.

A downstroke hits the low (bass) strings first; an upstroke hits the high
(treble) strings first. We band-split the signal, take each band's energy
envelope, and compare the time each band first crosses a fraction of its peak.
Bass-first -> down, treble-first -> up.
"""
import numpy as np
import librosa

LOW_MAX_HZ = 250.0     # bass strings region
HIGH_MIN_HZ = 1500.0   # treble region
_RISE_FRAC = 0.5       # envelope threshold as fraction of band peak

def _band_energy(y, sr, kind):
    S = np.abs(librosa.stft(y, n_fft=1024, hop_length=128))
    freqs = librosa.fft_frequencies(sr=sr, n_fft=1024)
    if kind == "low":
        mask = freqs <= LOW_MAX_HZ
    else:
        mask = freqs >= HIGH_MIN_HZ
    env = S[mask, :].sum(axis=0)
    return env, hop_times(len(env), sr, 128)

def hop_times(n_frames, sr, hop):
    return np.arange(n_frames) * hop / sr

def _first_rise_time(env, times):
    peak = env.max()
    if peak <= 0:
        return None
    idx = np.argmax(env >= _RISE_FRAC * peak)
    return float(times[idx])

def strum_direction(y, sr):
    """Return 'down', 'up', or 'unknown' for a single-strum signal."""
    low_env, low_t = _band_energy(y, sr, "low")
    high_env, high_t = _band_energy(y, sr, "high")
    t_low = _first_rise_time(low_env, low_t)
    t_high = _first_rise_time(high_env, high_t)
    if t_low is None or t_high is None:
        return "unknown"
    return "down" if t_low <= t_high else "up"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd validation && pytest tests/test_direction.py -v`
Expected: PASS (2 passed)

- [ ] **Step 5: Commit**

```bash
git add validation/strumsight_val/direction.py validation/tests/test_direction.py
git commit -m "feat(validation): sub-band onset-order strum-direction heuristic"
```

---

### Task 5: Dataset loader

**Files:**
- Create: `validation/strumsight_val/dataset.py`
- Test: `validation/tests/test_dataset.py`

- [ ] **Step 1: Write the failing test**

```python
import json, wave, struct, numpy as np
from pathlib import Path
from strumsight_val.dataset import load_clip, Clip

def _write_wav(path, y, sr=22050):
    y16 = (np.clip(y, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes(y16.tobytes())

def test_load_clip_reads_audio_and_labels(tmp_path):
    sr = 22050
    y = (0.3 * np.sin(2*np.pi*220*np.linspace(0,1,sr,endpoint=False))).astype(np.float32)
    _write_wav(tmp_path/"clip01.wav", y, sr)
    (tmp_path/"clip01.json").write_text(json.dumps({
        "audio": "clip01.wav", "bpm": 96,
        "events": [{"time": 0.5, "chord": "C", "direction": "down"}],
    }))
    clip = load_clip(tmp_path/"clip01.json")
    assert isinstance(clip, Clip)
    assert clip.sr == sr
    assert len(clip.y) == sr
    assert clip.events[0].chord == "C"
    assert clip.events[0].direction == "down"
    assert clip.events[0].time == 0.5
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd validation && pytest tests/test_dataset.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'strumsight_val.dataset'`

- [ ] **Step 3: Write minimal implementation**

```python
"""Load a labeled clip: audio (via librosa) + ground-truth events (JSON)."""
import json
from dataclasses import dataclass
from pathlib import Path
from typing import List
import librosa

@dataclass
class Event:
    time: float
    chord: str
    direction: str   # "down" | "up"

@dataclass
class Clip:
    name: str
    y: "list"
    sr: int
    bpm: float
    events: List[Event]

def load_clip(label_path) -> Clip:
    label_path = Path(label_path)
    meta = json.loads(label_path.read_text())
    audio_path = label_path.parent / meta["audio"]
    y, sr = librosa.load(str(audio_path), sr=None, mono=True)
    events = [Event(float(e["time"]), e["chord"], e["direction"])
              for e in meta["events"]]
    return Clip(name=label_path.stem, y=y, sr=int(sr),
                bpm=float(meta.get("bpm", 0)), events=events)

def iter_clips(folder) -> List[Clip]:
    folder = Path(folder)
    return [load_clip(p) for p in sorted(folder.glob("*.json"))]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd validation && pytest tests/test_dataset.py -v`
Expected: PASS (1 passed)

- [ ] **Step 5: Commit**

```bash
git add validation/strumsight_val/dataset.py validation/tests/test_dataset.py
git commit -m "feat(validation): labeled-clip dataset loader"
```

---

### Task 6: Evaluation harness + metrics + CLI

**Files:**
- Create: `validation/strumsight_val/evaluate.py`
- Test: `validation/tests/test_evaluate.py`

- [ ] **Step 1: Write the failing test**

```python
from strumsight_val.evaluate import score_events, Metrics
from strumsight_val.dataset import Event

def test_perfect_match_scores_100():
    truth = [Event(0.5, "C", "down"), Event(1.0, "G", "up")]
    pred  = [Event(0.51, "C", "down"), Event(0.99, "G", "up")]
    m = score_events(truth, pred, tol=0.1)
    assert isinstance(m, Metrics)
    assert m.chord_acc == 1.0
    assert m.direction_acc == 1.0
    assert m.matched == 2

def test_direction_error_lowers_only_direction_acc():
    truth = [Event(0.5, "C", "down")]
    pred  = [Event(0.5, "C", "up")]
    m = score_events(truth, pred, tol=0.1)
    assert m.chord_acc == 1.0
    assert m.direction_acc == 0.0

def test_unmatched_prediction_not_counted():
    truth = [Event(0.5, "C", "down")]
    pred  = [Event(5.0, "C", "down")]   # outside tolerance
    m = score_events(truth, pred, tol=0.1)
    assert m.matched == 0
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd validation && pytest tests/test_evaluate.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'strumsight_val.evaluate'`

- [ ] **Step 3: Write minimal implementation**

```python
"""Run the pipeline on labeled clips and report chord + direction accuracy."""
import sys
from dataclasses import dataclass
from typing import List
import numpy as np

from .dataset import Event, iter_clips
from .onsets import detect_onsets
from .chords import match_chord
from .direction import strum_direction

@dataclass
class Metrics:
    matched: int
    total_truth: int
    chord_acc: float
    direction_acc: float

def score_events(truth: List[Event], pred: List[Event], tol=0.08) -> Metrics:
    """Greedy nearest-time match of predictions to ground truth within `tol`."""
    used = [False] * len(pred)
    chord_ok = dir_ok = matched = 0
    for t in truth:
        best, best_dt = None, tol
        for i, p in enumerate(pred):
            if used[i]:
                continue
            dt = abs(p.time - t.time)
            if dt <= best_dt:
                best, best_dt = i, dt
        if best is not None:
            used[best] = True
            matched += 1
            if pred[best].chord == t.chord:
                chord_ok += 1
            if pred[best].direction == t.direction:
                dir_ok += 1
    denom = matched if matched else 1
    return Metrics(matched=matched, total_truth=len(truth),
                   chord_acc=chord_ok / denom, direction_acc=dir_ok / denom)

def analyze_clip(clip) -> List[Event]:
    """Predict events from audio: onset -> chord (window after onset) -> direction."""
    y, sr = np.asarray(clip.y), clip.sr
    onsets = detect_onsets(y, sr)
    preds = []
    win = int(0.30 * sr)
    for t in onsets:
        s = int(t * sr)
        seg = y[s:s + win]
        if len(seg) < win // 2:
            continue
        chord = match_chord(seg, sr)
        direction = strum_direction(seg, sr)
        preds.append(Event(time=t, chord=chord, direction=direction))
    return preds

def main(folder):
    clips = iter_clips(folder)
    if not clips:
        print(f"No labeled clips in {folder}/ — record + label some first.")
        return
    agg_matched = agg_truth = 0
    c_sum = d_sum = 0.0
    for clip in clips:
        pred = analyze_clip(clip)
        m = score_events(clip.events, pred)
        agg_matched += m.matched
        agg_truth += m.total_truth
        c_sum += m.chord_acc * m.matched
        d_sum += m.direction_acc * m.matched
        print(f"{clip.name:20s}  matched {m.matched}/{m.total_truth}  "
              f"chord {m.chord_acc:5.1%}  DIRECTION {m.direction_acc:5.1%}")
    denom = agg_matched if agg_matched else 1
    print("-" * 60)
    print(f"{'OVERALL':20s}  matched {agg_matched}/{agg_truth}  "
          f"chord {c_sum/denom:5.1%}  DIRECTION {d_sum/denom:5.1%}")
    print("\nGO/NO-GO: if DIRECTION accuracy is too low here, ship Analyze "
          "(look-ahead) first instead of Live — see the design spec.")

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "data")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd validation && pytest tests/test_evaluate.py -v`
Expected: PASS (3 passed)

- [ ] **Step 5: Run the full suite**

Run: `cd validation && pytest -q`
Expected: all tests pass (chords, onsets, direction, dataset, evaluate).

- [ ] **Step 6: Commit**

```bash
git add validation/strumsight_val/evaluate.py validation/tests/test_evaluate.py
git commit -m "feat(validation): evaluation harness + chord/direction metrics + CLI"
```

---

### Task 7: Record, label, and measure (the go/no-go gate)

**Files:** none (produces `validation/data/*` locally, gitignored).

- [ ] **Step 1: Record 5–10 clean guitar clips** (phone or interface), ~10–20 s each, one chord progression per clip, varied down/up strums.

- [ ] **Step 2: Hand-label each clip** — create `<clip>.json` beside each `<clip>.wav` using the schema at the top of this plan (`time`, `chord`, `direction` per strum). Convert `.m4a` to `.wav` if needed: `ffmpeg -i clip.m4a clip.wav` (dev box only).

- [ ] **Step 3: Run the accuracy report**

Run: `cd validation && python -m strumsight_val.evaluate data/`
Expected: a per-clip + OVERALL table with **chord** and **DIRECTION** accuracy.

- [ ] **Step 4: Record the go/no-go decision** in the spec

Append the measured OVERALL direction accuracy to `docs/superpowers/specs/2026-07-05-strumsight-design.md` under §8, and decide:
- Direction accuracy strong (say ≥ ~80% on your clips) → proceed to Phase 2 (C++ core), Live-first.
- Direction accuracy weak → either tune the heuristic (band edges `LOW_MAX_HZ`/`HIGH_MIN_HZ`, `_RISE_FRAC`, onset window) and re-measure, or fall back to Analyze-first (look-ahead tolerates more compute).

- [ ] **Step 5: Commit the decision**

```bash
git add docs/superpowers/specs/2026-07-05-strumsight-design.md
git commit -m "docs(spec): record Phase 1 go/no-go direction-accuracy result"
```

---

## Self-Review

**Spec coverage:** Phase 1 of the spec's build order (§5) is fully covered — chord match (Task 2), onset (Task 3), sub-band direction heuristic (Task 4), dataset (Task 5), accuracy measurement incl. the up-strum weak-point risk from §8 (Tasks 6–7). Phases 2–4 (C++ core, native audio/FFI, Live UI) are intentionally **out of this plan** — they get their own plans once Task 7 produces the accuracy numbers their design depends on.

**Placeholder scan:** no TBD/TODO; every code step shows complete, runnable code; every command has an expected result.

**Type consistency:** `Event(time, chord, direction)` and `Clip(name, y, sr, bpm, events)` are defined in Task 5 and used identically in Tasks 6–7; `match_chord(y, sr)`, `detect_onsets(y, sr)`, `strum_direction(y, sr)`, `score_events(truth, pred, tol)`, `Metrics(matched, total_truth, chord_acc, direction_acc)` are consistent across tasks.

**Known follow-ups (not blockers):** librosa pin may need a minor bump for the box's Python; the direction heuristic thresholds are expected to need tuning on real clips (that IS the Task 7 experiment).
