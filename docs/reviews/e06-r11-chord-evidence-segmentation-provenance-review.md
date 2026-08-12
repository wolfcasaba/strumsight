# E06-R11 — Review

Brief: `docs/rounds/e06-r11-chord-evidence-segmentation-provenance.md`
Diff: `git diff dd732c4f..0d350f7a` (pre-flight commit → implementer `done` head), branch `codex/e06-r11-chord-evidence-segmentation-provenance`
Reviewer: Claude (Sonnet 5) · Dátum: 2026-08-12
Verdikt: **APPROVED**

## Frissítés — dedikált security review + javító kör #1

A kötelező dedikált security review (risk=high,
`docs/reviews/e06-r11-chord-evidence-segmentation-provenance-security.md`)
**PASS with NOTEs**-t adott: 0 CRITICAL/BLOCKER/MAJOR, 1 MINOR (`ChordLabelCandidate`
assert-only validáció — release buildben ledobódna), 4 NOTE (mind latens,
bekötetlen jövőbeli-fogyasztóra vonatkozó follow-up, egyik sem blokkoló). A
MINOR-1-et egy tightly-scoped javító kör zárta (`f3f34b2f`): valódi
`ArgumentError` a két assert helyén (a `const` kulcsszó indokoltan
eltávolítva, Dart nyelvi korlát — a testvér `ChordFrameEvidence._`
konstruktor mintáját követve) + regressziós teszt. Saját re-verify: a
teljes `chord_segment_assembler_test.dart` 13/13 zöld izolált klónban
`f3f34b2f`-en. A 4 NOTE (O(S²) merge opt-in policyban, szanitálatlan
label→id interpoláció, pre-existing range-only confidence-check, codec
provenance-veszteség) szándékosan NEM ebben a körben javítandó — mind
explicit jövőbeli-fogyasztó-előtti hardening, a HANDOFF follow-up
szakaszába kerül.

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 (1 MINOR a security review-ból, FIXED) · NOTE: 2 (+ 4 a security review-ból, nem blokkoló)

Két dispatch: az első (`stopped`, tiszta önjavítás — a `test/app` listán
kívüli editjét maga vonta vissza, `scope_audit=ok`) egy mért `allowed_paths`
rést tárt fel; az orchestrátor §0.0 mid-round revízióval zárta (lásd
`docs/rounds/...md` §0.0 pont 4), majd a második dispatch `done`-nal zárt.
Mindkét ok NEM implementer-hiba: (1) a scope-rés, (2) egy, az orchestrátor
saját munkapéldány-előkészítésének hiányzó `tools/prepare-flutter-
generated.sh` lépéséből eredő, 932 hamis analyze-hibát okozó l10n-hiány
(`docs/LESSONS.md` L222 ismert mintája) — mindkettőt az implementer korrekt
`blocked`/`stopped` jelzéssel jelentette, munkakód-módosítás nélkül.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | V1-paritás mátrix — hat fixture, darabszám+határ \|Δ\|≤1µs | ✅ | `chord_segment_assembler_test.dart` `V1 parity policy` csoport, 6 fixture (`C to G`, `C G Am F`, `ring-out overlap`, `fast transition`, `silence gap`, `all no-chord`), millimásodperc-pontos `_expectSegment` — saját mutáció (záróhatár `open.start`-ra rontása) 9/12 tesztet PIROSRA fogott, visszaállítás után zöld |
| 2 | No-chord viselkedés — default 1 szegmens nyitva marad; `closeOnNoChord=true` → 2 szegmens | ✅ | `V1 parity policy silence gap` (1 szegmens) + `closeOnNoChord closes a silence gap...` (2 szegmens) — mindkettő zöld, ellentétes policy-eredmény ugyanazon a fixture-ön |
| 3 | Minimum szegmenshossz küszöb hármas (199/200/201 ms, inkluzív határ) | ✅ | `minimum duration keeps the inclusive 200ms boundary...` — 3 cella (`length:199→count:2`, `200→3`, `201→3`); saját mutáció (`>=`→`>`) PONTOSAN ezt az 1 tesztet fogta pirosra (10 másik zöld maradt) |
| 4 | Záróhatár pontossága minden fixture-ön (\|Δ\|≤1µs) + property | ✅ | fenti unit-tesztek `segments.last.end` assertjei + property-teszt `segments.last.end == duration` |
| 5 | Nem-átfedő, hézagmentes property (`PROPERTY_SEED`) | ✅ | `analysis_chord_segment_property_test.dart`: 100 randomizált trial, monoton/nem-átfedő + `accountedMicroseconds == duration.inMicroseconds` invariáns; `PROPERTY_SEED` env-fallback 42 (HORIZON-konvenció) |
| 6 | Fusion flag-mátrix — OFF/ON-egyetért/ON-ellentmond (3 cella) | ✅ | `experimental fusion retains agreement and lowers confidence on disagreement`: OFF → `identical`-szintű DSP-lista visszaadás; ON+egyetért → `source==dsp`, változatlan; ON+ellentmond → `source==fused`, `confidence < dsp.confidence` (kézzel újraszámolva: 0.8×0.6=0.48<0.8 ✓), címke a magasabb súlyúé |
| 7 | Címke-normalizálás mátrix + idempotencia | ✅ | `chord_label_normalizer_test.dart` (Cmaj/CM→C, Cmin→Cm, Db→C#) + property idempotencia-teszt mindkét fájlban; kézi nyomkövetés (`Bbmin7`→`A#m7`→`A#m7`) megerősíti |
| 8 | Evidence-teljesség jelölés (`derived`, üres top-k) | ✅ | `ChordFrameEvidence._` konstruktor fail-fast, ha `derived` + nem-üres topK/topConfidence/noChordProbability egyszerre áll fenn; `derived evidence is preserved...` teszt |
| 9 | Flag-őr + V1 érintetlenség | ✅ | `feature_flags_test.dart` bővített enumeráció (5 flag) zöld; `git diff --stat` nem érinti `lib/features/analyze/**`/`lib/features/live/**` (saját `git diff --stat` + `scope-audit.py` is megerősíti); `test/features/analyze` gate-lépés önállóan ZÖLD |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.**

- Saját `python3 tools/scope-audit.py --repo /tmp/review-e06-r11 --brief docs/rounds/e06-r11-chord-evidence-segmentation-provenance.md --base dd732c4f` → `Legacy scope audit OK (dd732c4f..0d350f7a, 13 changed path(s), 0 generated/ignored)`.
- A 13 útvonal egyezik a §4 engedélyezett listával (a `test/app/feature_flags_test.dart` a mid-round §0.0 revízióval bővült be — lásd Összegzés).
- Tilos zóna (`lib/features/live/**`, `lib/features/analyze/**`, `assets/ml/**`, `docs/rag/**`): egyik sem szerepel a diffben, és a gate `test/features/analyze` lépése önállóan zöld (nem csak a diff hiánya, hanem a viselkedés-paritás is mérve).

## Megállapítások

### F1 — NOTE — Merge-ág (`extendTo`/`extendFrom`) nem viszi át az elnyelt szegmens frame-jeit a confidence-súlyozásba

- **Fájl:** `lib/features/audio_analysis/engine/harmony/chord_segment_assembler.dart:175-181`
- **Probléma:** amikor a `minimumSegment > 0` policy egy rövid szegmenst egy szomszédba olvaszt, az `extendTo`/`extendFrom` csak a BEFOGADÓ szegmens saját `_frames`-ét viszi tovább — az elnyelt (rövid) szegmens frame-jei elvesznek. A `toChordSegment()` súlyozása ettől nem esik szét (a befogadó utolsó/első frame-jének súlya a kiterjesztett határig nő), de az elnyelt span alatti tényleges evidence nem járul hozzá a confidence-hez.
- **Hatás:** ma **nincs éles hatás** — a default policy `minimumSegment=0` (V1-paritás, OD-02), ez az ág gyakorlatilag halott kód, amíg egy jövőbeli kör nem-nulla küszöböt nem kapcsol be. Egyetlen §6 acceptance sem vizsgálja a merge utáni confidence pontosságát (csak darabszámot/határt), tehát ez nem sérti a mai kontraktust.
- **Kötelező javítás:** nincs a jelen körben; ha egy jövőbeli kör éles nem-nulla `minimumSegment` policyt vezet be, `extendTo`/`extendFrom` egyesítse a két oldal `_frames` listáját is, ne csak a határt.
- **Ellenőrzés:** n/a (follow-up).
- **Státusz:** OPEN (nem blokkoló, jövőbeli körre jegyezve).

### F2 — NOTE — Az implementer egy R08-eredetű, szomszédos flag-enumerációs rést is zárt

- **Fájl:** `test/app/feature_flags_test.dart:33`
- **Probléma:** a `_audioAnalysisFlags` helper `analysisPreprocessingExperimentalEnabled` (E06-R08 flag) is hiányzott a felsorolásból — ez a rés a mai kör előtt is fennállt, nem R11 hozta be. Az implementer a mid-round engedélyezett fájlon belül ezt is pótolta, nem csak az új `analysisExperimentalFusionEnabled`-et.
- **Hatás:** pozitív mellékhatás (a flag-őr immár teljes), de dokumentálva legyen, hogy ez technikailag túlmutat a §0.0 pont 4 szűken vett indoklásán (csak az új flaget említette). Nem tekintem scope-sértésnek: ugyanazon a már engedélyezett fájlon belüli, közvetlenül szomszédos, egysoros bővítés, tesztben bizonyítva (`all five flags` név is frissült).
- **Kötelező javítás:** nincs — csak átláthatósági jegyzet.
- **Ellenőrzés:** `feature_flags_test.dart` diff, gate `test test/app` zöld.
- **Státusz:** OPEN (nem blokkoló, tájékoztató).

## Gate-bizonyíték ellenőrzése

Mind a kilenc lépés **saját kezűleg**, izolált `/tmp/review-e06-r11` klónban, `git clone --branch codex/e06-r11-chord-evidence-segmentation-provenance` után, `tools/prepare-flutter-generated.sh` + `tools/round-gate.sh test/features/audio_analysis test/property test/app test/features/analyze` paranccsal újrafuttatva:

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ (1301 fájl, 0 changed) |
| analyze | zöld | ✅ |
| test test/features/audio_analysis | zöld | ✅ |
| test test/property | zöld | ✅ (a 2 új property teszt is lefutott a többi property-teszttel együtt) |
| test test/app | zöld | ✅ (bővített flag-őr, 14/14 új assertion) |
| test test/features/analyze | zöld | ✅ — közvetlen bizonyíték a „V1 érintetlenség" kritériumra |
| architecture | zöld, 12 allowlisted deviation | ✅ — egyezik az E06-R09 óta mért bázisértékkel, nincs ÚJ allowlist-bejegyzés |
| secrets | zöld (2240 fájl, 0 lelet) | ✅ |
| l10n | zöld (en→hu, 1019 üzenet) | ✅ |
| CI (teljes suite + property + APK) | még nem futott | ⏳ orchestrátor dispatch-eli merge előtt |

Saját mutációs próbák (eldobható, ebben a klónban, mindkettő visszaállítva):
1. Záróhatár `clipDuration`→`open.start`: 9/12 assembler-teszt PIROS lett, beleértve a „záróhatár"-cellát → visszaállítva, zöld.
2. Minimum-küszöb `>=`→`>`: PONTOSAN az 1 küszöb-hármas teszt lett piros, a többi 10 zöld maradt → visszaállítva, zöld.

## Merge-döntés

ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → **merge engedélyezett**, a CI (teljes suite + randomizált property + APK, exact-SHA) zöld futása után.
