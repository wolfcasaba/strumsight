# E14-R30 — Expected-chord prior szigorú izolációja: `RecognitionMode` + tie-break (ADR 0544)

- **Kör:** E14-R30 · **Csomag:** PKG-A · **ADR:** 0544
- **Ág:** `claude/laptop-apk-debug-prompt-kys4oa`
- **Környezet:** nincs Dart/Flutter SDK ezen a boxon → **lokális gate nem
  futtatható**; a mérce a session végi `full-gate.yml` + `build-apk.yml`.

## 1. Cél

Az expected-chord prior ma **additív bias** a Viterbi-trellisben, amit szabad
játékban csak egy képernyő-szintű konvenció tart távol. A kör ezt két,
gépileg ellenőrzött szerződésre cseréli:

1. **free módban a prior strukturálisan alkalmazhatatlan** (nincs hint-érték,
   amit alkalmazni lehetne);
2. **guided módban a prior dokumentált tie-breaker**, amely soha nem képes
   egy tiszta audio-győztest megfordítani.

## 2. Mért állapot (a kör előtt)

- `viterbi_chord_decoder.dart:96,108` — `_delta[s] = sim[s] + (s == _expectedIdx
  ? expectedPrior : 0)`; `expectedPrior = 0.05`, minden képkockán, halmozódva.
- `live_screen.dart:93` — `setExpectedChord(null)` belépéskor: **konvenció**.
- `RecognitionMode` a fán nem létezett.
- `chord_matcher.dart` (legacy sablon-illesztő) prior-mentes, és **nincs a Live
  úton** — a Live út NNLS → `ChordDictionary` → `ViterbiChordDecoder`.
- A round-137-es 0,05 érték indoklása állítás, nem mérés.

## 3. Scope

**Benne:** `RecognitionMode` + `ExpectedChordHint` típus; a dekóder
prior-mechanizmusának cseréje (trellis → kiolvasási tie-break); a mód
átvezetése a `LivePipeline` és a `RealStrumEngine` konstrukciós felületére; a
mód megjelenése a diagnosztikai/shadow felületeken; barrel-export.

**Kívül:** `live_screen.dart` / `learn_screen.dart` / `practice/**` (PKG-F);
`recognition_runtime_info.dart` (PKG-E); `evaluation/**` (PKG-B);
zászlók (PKG-D); ARB (orchestrátor). Ez a kör **nem** hangol DSP-küszöböt.

## 4. Érintett fájlok

| Fájl | Változás |
|---|---|
| `lib/features/live/domain/recognition/recognition_mode.dart` | **ÚJ** — enum + `ExpectedChordHint` |
| `lib/features/live/engine/dsp/viterbi_chord_decoder.dart` | tipizált `setExpected`; additív prior → kiolvasási tie-break; diagnosztikai getterek |
| `lib/features/live/engine/dsp/live_pipeline.dart` | `mode` konstrukciós paraméter; `setExpectedChord` a `forMode`-on át |
| `lib/features/live/engine/real_strum_engine.dart` | `mode` konstrukciós paraméter; hint-szűrés az izolátum-határ ELŐTT |
| `lib/features/live/engine/strum_engine.dart` | a `setExpectedChord` szerződésének dokumentálása |
| `lib/features/live/public.dart` | `recognition_mode.dart` export |
| `test/features/live/recognition_mode_isolation_test.dart` | **ÚJ** |
| `test/features/live/dsp/viterbi_decoder_test.dart` | API-frissítés + a régi viselkedést rögzítő cella cseréje |
| `docs/adr/0544-…md`, `docs/rag/chunks/012-…md` | doksi |

## 5. Kötött döntések

ADR 0544 D1–D5. Kiemelten: `RecognitionMode` **két** tagú (`lab` szándékosan
kimarad); az alapérték `free` (fail-closed); a tie-break sáv **0,05**, a
törölt `expectedPrior`-ból átvéve, **nem újrahangolva**.

## 6. Acceptance criteria

| # | Kritérium | Státusz |
|---|---|---|
| 1 | Free mód + tetszőleges (akár szándékosan ROSSZ, akár képkockánként újraküldött) prior → **bit-azonos** képkocka-folyam a prior nélkülihez | **PINNED-BY-TEST** — `recognition_mode_isolation_test.dart` (2 cella, teljes `LiveFrame`-aláírás összevetés) |
| 2 | Free módban hint nem is **építhető** | **PINNED-BY-TEST** — `forMode(free, …) == null` minden címkére; `allowsExpectedChordPrior` |
| 3 | Guided „wrong chord" eset **nem javul automatikusan helyesre** | **PINNED-BY-TEST** — tiszta G / zajos gyenge-tercű G elvárt C mellett; tartós maj7 evidencia `Cmaj7`-et ad |
| 4 | Guided prior valódi döntetlent eldönt (a mechanizmus él) | **PINNED-BY-TEST** — egzakt aug-döntetlen (Caug/Eaug/G#aug = 0,8228; a következő 0,6692) |
| 5 | A prior nem hagy nyomot a trellisben | **PINNED-BY-TEST** — hint törlése után képkockánként bit-azonos címke **és** confidence |
| 6 | A mód **minden exportban** rögzül | **PARTIAL** — `LivePipeline.mode`, `ChordLatchDiagnostics.mode`, shadow-seam `mode` igen; `RecognitionRuntimeInfo` + evaluation manifest **más csomag tulajdona** (patch a jelentésben) |
| 7 | Leakage-őr az evaluation úton | **NEM ITT** — `evaluation/**` = PKG-B; a jelentés kéri |
| 8 | A prior gyengülésének hatása a tanórai pontosságra | **NEEDS-MEASUREMENT** — nincs adat, ADR 0544 D3 kimondja |

## 7. Verifikáció

Lokálisan **nem futtatható** (nincs SDK). CI-ben:
`full-gate.yml` + `build-apk.yml`. Érintett tesztútvonalak:
`test/features/live/`, `test/features/live/dsp/`, `test/core/`.

## 8. Kockázatok

- **A guided viselkedés érdemben gyengül** (ADR 0544 D3): a maj↔maj7 tartós
  ambiguitást a prior már nem tartja meg. Ez szándékos, de **mérés nélkül nem
  tudjuk, hogy tanórán jobb-e**. Visszaút: a sávot mérés UTÁN lehet emelni —
  a mechanizmus (tie-break) akkor is helyes marad.
- A `setExpected` szignatúra-váltása minden hívót érint; a fán csak a dekóder
  saját tesztjei hívták közvetlenül (frissítve).

## 10. Handoff

- **PKG-F:** `live_screen.dart:93` konvenció-nullázása feleslegessé vált; a
  Live három módja `RecognitionMode`-ra képezhető (Free Play → `free`,
  Guided Pattern / Accuracy Check → `guided`). A motort **módonként kell
  megépíteni** (konstrukciós paraméter), nem setterrel váltani.
- **PKG-E:** `RecognitionRuntimeInfo` bővítési patch a PKG-A jelentésben.
- **PKG-B:** `audioOnly` vs `guidedPrior` metrika szétválasztása + leakage-őr
  az evaluation úton — a `RecognitionMode` típus készen áll a barrelben.
