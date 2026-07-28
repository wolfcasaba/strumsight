# ADR 0003 — Pure-Dart DSP first, ML csak mért bizonyítékkal

**Státusz:** elfogadva (a r199 mérés által megerősítve; formalizálva E01-R01)

## Döntés

A valós idejű felismerés elsődleges útvonala a pure-Dart DSP pipeline
(FFT/chroma/Viterbi/onset — `docs/rag/chunks/` a paraméter-igazságforrás).
ML-komponens csak akkor válhat alapértelmezetté, ha VALÓS audión mért
kiértékelés igazolja, hogy jobb a DSP-nél; addig feature flag mögött marad.

## Kontextus — a döntő mérés

Round 199: a szintetikus adaton 0.99-et elérő chord-CRNN valós Bb full-band
felvételeken 36% majmin pontosságot ért el a DSP 56%-ával szemben (75 esemény,
független librosa referencia, `ml/chords/eval_real_sessions.py`). A synth→real
transfer kudarca korábban a strum-modellnél is megismétlődött. Ez a plan-korpusz
R-001 kockázatának mért megvalósulása.

## Következmények

- DSP-konstans/ML-súly csak akkor módosítható, ha a kör explicit kéri, fixture+
  property+parity+real-audio méréssel (AGENTS §9).
- A `docs/rag/chunks/` (mért igazság) ütközésnél felülírja a terv-korpuszt.
- Modellcsere gate: model card + checksum + manifest + honest-eval (Ch2 Kör 15.6).
