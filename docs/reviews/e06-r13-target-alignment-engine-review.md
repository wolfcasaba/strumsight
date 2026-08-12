# E06-R13 — Review

Brief: docs/rounds/e06-r13-target-alignment-engine.md
Diff: `git diff ce4b6b24...codex/e06-r13-target-alignment-engine`
Reviewer: Claude · Dátum: 2026-08-12
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 1 · NOTE: 2

Independens, izolált `/tmp/review-e06-r13` klónban futtatott gate: **ZÖLD**
(format, analyze, `test/features/audio_analysis`, `test/property`,
architecture, secrets, l10n — mind zöld, exit 0). Két valódi-sértés próbát
futtattam a `event_aligner.dart`-on (ideiglenes mutáció → piros teszt →
visszaállítás, l. F2/F3 alább) — mindkettő megerősítette, hogy a mércét adó
tesztek ténylegesen mérik az állított garanciákat, nem csak formálisan
zöldek.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Illesztés-mátrix, 9 cella | ✅ | `event_aligner_test.dart` — perfect/missing/extra/early-cluster/late-cluster/tie-break/direction/type/empty, mindegyik a teljes `AlignmentResult`-ot ellenőrzi |
| 2 | Monotonitás property | ✅ | `analysis_alignment_property_test.dart`, `PROPERTY_SEED`-vezérelt, 200 trial, mindkét index szigorúan növekvő — **valódi-sértés próbával megerősítve** (F2) |
| 3 | Tolerancia-küszöb hármas (124/125/126 ms @ 120 BPM) | ✅ | `tolerance_policy_test.dart:12-35` — 124 és 125 ms párosul, 126 ms missed+extra; `forBeatDuration(500ms)==125ms` közvetlen assert |
| 4 | Clamp-mátrix, 6 cella | ✅ | `tolerance_policy_test.dart:37-104` — 40 BPM (150 párosul/151 nem), 300 BPM (50/51), 400 BPM (40/41); mind `python3 -c`-vel egyező érték (a §10 handoff szerint) |
| 5 | Tie-break determinizmus, 100 futás | ✅ | `event_aligner_test.dart:102-121` — 100 iteráció, minden futás `expectedIndex=0`/`id='early'` |
| 6 | Bemenet-immutabilitás | ✅ (1 MINOR) | `event_aligner_test.dart:190-205` — l. F1 |
| 7 | Teljesítmény-korlát, 2000×2000 | ✅ | `event_aligner_test.dart:225-247` — 2000 matched pár, `maximumCandidateBandWidth<=3`, `scoreStateCount=2000`, mért idő a review-klónban **28-38 ms** (implementer: 29 ms) |
| 8 | Confidence hatása | ✅ | `event_aligner_test.dart:172-186` + kézzel levezetve (l. „Kód-ellenőrzés" alább): alacsony (0.1) vs magas (0.9) confidence azonos 100 ms távolságnál — a magasabb nyer |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.**

```
docs/adr/0231-target-alignment-engine-boundary.md          (orchestrátor pre-flight, nem implementer-scope)
docs/rounds/e06-r13-target-alignment-engine.md              (allowed_paths)
lib/features/audio_analysis/domain/target/*.dart (3 ÚJ)     (allowed_paths)
lib/features/audio_analysis/engine/alignment/*.dart (2 ÚJ)  (allowed_paths)
lib/features/audio_analysis/public.dart                     (allowed_paths, csak export-sorok)
test/features/audio_analysis/engine/*.dart (2 ÚJ)           (allowed_paths)
test/property/analysis_alignment_property_test.dart (ÚJ)    (allowed_paths)
```

A gépi scope-audit (`.codex-round-status`) is `scope_audit=ok`,
`scope_audit_changed=10`, bázis `c7cd64a0` (a pre-flight-commit) — pontosan
egyezik a fenti kézi listával. `lib/features/practice/**`,
`lib/features/song_trainer/**`, `lib/features/analyze/**` felé **nincs**
import vagy módosítás (`grep -rn "features/practice\|features/song_trainer\|features/analyze"` a négy új fájlon: 0 találat).

## Megállapítások

### F1 — MINOR — a dedikált immutabilitás-teszt csak a dobó ágat fedi

- **Fájl:** `test/features/audio_analysis/engine/event_aligner_test.dart:190-205`
- **Probléma:** a `does not mutate observed or expected input snapshots` teszt
  szándékosan rendezetlen bemenettel hívja az `align()`-t, ami
  `ArgumentError`-t dob — a bemenet-változatlanságot csak a DOBÓ ágon
  ellenőrzi. Egy SIKERES (nem dobó) hívás utáni közvetlen `observed`/`expected`
  változatlanság-assert nincs a névhez tartozó teszten belül.
- **Hatás:** a teszt neve többet ígér, mint amit közvetlenül mér.
  Valódi-sértés próbával ellenőriztem (`observed.sort(...)` beszúrása az
  `align()` végére, közvetlenül a sikeres ág elején, majd visszaállítva) — a
  mutációt a teljes suite **elkapta**, de NEM ez a dedikált teszt, hanem
  véletlenül a `one extra observed event has one extra penalty` (ID-eltolódás
  a rendezés miatt) és az `empty inputs` teszt (üres `const` lista `.sort()`-ja
  `UnsupportedError`-ral bukik). A termékkód maga (forrás-olvasással
  megerősítve: nincs `sort`/`[]=`/`add`/`removeAt` hívás az `observed`/
  `expected` paramétereken egyetlen ágon sem) **helyesen** nem mutál — ez
  tesztlefedettségi pontosítás, nem funkcionális hiba.
- **Kötelező javítás (opcionális, nem blokkoló):** a meglévő teszthez egy
  sikeres híváson mért `expect(observed, orderedEquals(observedBefore))`
  hozzáadása.
- **Ellenőrzés:** a fenti mutációs próba a jövőben is piros lenne, csak nem
  ezen a dedikált néven.
- **Státusz:** OPEN, follow-up — nem blokkolja a merge-et (a mögöttes
  viselkedés helyes, a gap kizárólag tesztnév-pontosság).

### F2 — Valódi-sértés próba — monotonitás (a brief §6.1 utolsó sora)

- **Fájl:** `lib/features/audio_analysis/engine/alignment/event_aligner.dart:64`
- **Próba:** `prefixBest.query(columnIndex - 1)` → `prefixBest.query(columnCount - 1)`
  (a monotonitási korlát eltávolítása — a DP a teljes eddigi legjobb utat
  nézné oszlop-pozíciótól függetlenül).
- **Eredmény:** `test/property/analysis_alignment_property_test.dart` **PIROS**
  az első trialon (`seed=42 trial=0 observed: Expected: a value greater than
  <1>, Actual: <1>`), és három másik matrix-teszt is elbukott (perfect-match,
  tie-break, confidence-verseny) — a monotonitás valóban a garantáló
  mechanizmus, nem díszlet.
- **Visszaállítva**, a review-klón `git diff --stat` üres a próba után.
- **Státusz:** NOTE — ez a brief kifejezett kérése volt, nem önálló lelet;
  itt dokumentálom a bizonyítékot.

### F3 — Kód-ellenőrzés — `totalCost` algebrai azonosság

- **Fájl:** `lib/features/audio_analysis/engine/alignment/event_aligner.dart:127-134`
- **Megfigyelés:** `totalCost = observed.length·extraPenalty + expected.length·missedPenalty − benefit`,
  ahol `benefit = Σ(missedPenalty+extraPenalty−cost_i)` a kiválasztott
  párokra. Behelyettesítve: `totalCost = Σcost_i + missedPenalty·|missed| +
  extraPenalty·|extra|` — pontosan az elvárt „teljes költség" definíció
  (matched-párok költsége + missed/extra büntetés), NEM csak a matched-párok
  összköltsége. Kézzel leellenőrizve a 9-cellás mátrix `totalCost`
  assertjeivel (pl. „one missing expected event" → `totalCost=1` = 1×
  `missedPenalty`) — egyezik.
- **Státusz:** NOTE, nem hiba — dokumentálva, mert a review-protokoll a
  „mérj, ne csak olvass" elvet kéri.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer, §10) | Ellenőrizve (saját /tmp klón) |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld | ✅ zöld |
| test test/features/audio_analysis | 14 teszt zöld | ✅ zöld (`event_aligner_test.dart` 14 + `tolerance_policy_test.dart` 3) |
| test test/property | zöld, 200 randomizált trial | ✅ zöld (teljes `test/property` suite, 81 teszt, `PROPERTY_SEED=42`) |
| architecture | — | ✅ zöld (12 allowlistelt eltérés, meglévő, nem a körtől) |
| secrets | — | ✅ zöld (2264 fájl, 0 lelet) |
| l10n | — | ✅ zöld (en→hu, 1019 üzenet) |
| 2000×2000 teljesítmény | 29 ms | ✅ 28-38 ms (review-klónban, két futtatás) |
| CI (teljes suite + property + APK) | — | Orchestrátor dolga a review után (§3.0) |

A `.codex-round-status` `gate_shape=ok` (nincs csonkoló `\|tail`/`&&` minta a
logban), `continuations=0` (egy fordulóban lezárt kör).

## Merge-döntés

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge.
**Nulla nyitott BLOCKER/MAJOR, 1 nem-blokkoló MINOR (follow-up), a helyi gate
teljes egészében zöld, saját kézzel megerősítve.** A biztonsági review
(risk=high, `docs/reviews/e06-r13-target-alignment-engine-security.md`)
külön fut; a CI-dispatch (`round-ci-plan.py`) és a végső merge ennek a
review-nak és a biztonsági review-nak az együttes zöld eredménye után
következik.
