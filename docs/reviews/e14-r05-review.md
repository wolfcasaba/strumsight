# E14-R05 — Review (Claude, orchestrátor/reviewer)

- **Kör:** `E14-R05` — Live signal quality analyzer
- **Branch:** `sonnet-impl/e14-r05-live-signal-quality-analyzer` @ `4697f6f4`
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Brief:** `docs/rounds/e14-r05-live-signal-quality-analyzer.md` (§0.0 R1–R7)
- **ADR:** `docs/adr/0507-live-signal-quality-analyzer-reuse-route-and-hysteresis.md` (D1–D10)
- **Dátum:** 2026-09-04

## 0. Mit mértem (nem bemondás)

| Mérés | Parancs | Eredmény |
|---|---|---|
| Scope-audit | `python3 tools/scope-audit.py --repo … --brief … --base 16edfb1f` | **OK** — 7 változott útvonal, mind az `allowed_paths`-on |
| Munkafa tisztaság | `git status --short` | üres (a jelzés `dirty_files=1` értéke a saját jelzésfájlra vonatkozott) |
| CI-terv | `tools/round-ci-plan.py --format json` | `dispatch=["full-gate.yml"]`, `router_ci_expected=true` |
| CI (exact-SHA) | `gh workflow run full-gate.yml` → run `33883143114` | headSha `4697f6f43fe6` == lokális HEAD |
| Eldobható próbateszt (A–D) | `flutter test test/zz_review_probe_test.dart` (a review után törölve) | lásd §2 |

## 1. Szerződés-ellenőrzés

| Kötés | Mérés | Verdikt |
|---|---|---|
| D1 — a matematika újrahasznosított, barrelen át | `import 'package:strumsight/features/audio_analysis/public.dart';` (`live_signal_quality_analyzer.dart:5`); `peakDbfs`/`rmsDbfs`/`clippedSampleRatio`/`tonalness` hívások | ✅ |
| Acceptance 6. — `signal_quality_math.dart` + `QualityThresholds` bájtra változatlan | `git diff --stat origin/main...HEAD` — az `audio_analysis` fa NEM szerepel | ✅ |
| §0.0 R7 / D10 — a snapshot a `LivePipeline` getterén megy, a `LiveFrame` érintetlen | a pipeline-diff 14 sor: mező + `addChunk` egy sor + getter + `reset` egy sor; `_buildFrame()` és `inputLevel` érintetlen | ✅ |
| D5 — az `unknown` valódi állapot | `unknown` fixture-cella + PROBE D (`reset()` → `SignalQualitySnapshot.unknown`) | ✅ |
| D6 — nincs hazug `0.0` | a puffer feltöltése előtt a TELJES snapshot `unknown` (minden mező `null`), nem részlegesen kitöltött | ✅ |
| Acceptance 1. — nyolc állapot fixture-mátrixa | 8 állapot + 2 extra `good` cella, `clipping`/`silence` determinisztikus (fix seed, `clippedSampleRatio == 1.0`) | ✅ |
| §6 numerikus hármas (`clippedSampleRatio` inkluzív) | 2/3000 → nem `clipping`, 3/3000 == 0.001 → `clipping`, 4/3000 → `clipping` | ✅ |
| Acceptance 2. + §7.1 falszifikáció | villogás-teszt `enterFrames=5`/`exitFrames=8` mellett zöld; `1`/`1` mellett PIROS (39 váltás, nyers kimenet a brief §10.3-ban) | ✅ |
| Acceptance 5. — CPU ≤ 5% | 304 ms vs 307 ms (median/3) ≈ 1,0% | ✅ (a mérés a box zajszintjén belül van, lásd M1) |
| D7 / ADR 0224 §4 — csak audióminőség | a `speechLike` kizárólag `tonalness ∈ (0.25, 0.5]`; nincs hangforrás-/személy-osztályozás, nyers audio nem hagyja el az objektumot | ✅ |

## 2. Eldobható próbateszt (legacy-referenciával szemben)

```
PROBE A live=-36.97735919606661 batch=-36.97735919606661     # noiseFloorDbfsForFrames-szel AZONOS
PROBE B live=0.5 perBlock=0.5 batchWholeStream=0.4 active=0.5 # blokk- vs. batch-granularitás
PROBE C before=good blocksUntilClipping=38 (3.53 s)           # gyártási késleltetés
PROBE D reset → SignalQualitySnapshot.unknown                 # zöld
```

A PROBE A a kör legkockázatosabb állítását igazolja: a saját
`_nearestRankPercentile` **bitre ugyanazt** adja, mint a
`SignalQualityMath.noiseFloorDbfsForFrames` ugyanazon a blokk-halmazon —
tehát az „azonos formula, csak nem számoljuk újra az `rmsDbfs`-t" indoklás
MÉRT, nem állított.

## 3. Leletek

### MINOR 1 — a gyártási `statsStride: 64` 3,5–6 s késleltetést ad, és a hiszterézis a gyártási ütemben gyorsítótárazott értékeket erősít meg

**Mérve:** PROBE C — klippelés kezdete után **38 blokk (3,53 s)** a megerősített
`clipping`-ig; a brief §10.5 legrosszabb esete ~5,95 s. A metrikák két
újraszámítás között változatlanok, így az `enterFrames=5` megerősítés ugyanazt
a gyorsítótárazott mérést ötször látja — a hiszterézis a gyártási ütemben nem
független megerősítéseket számol, hanem fix késleltetést ad.

**Miért NEM blokkoló:** (a) a kör kimondottan „elemzőt ad, nem UI-t" (brief §1),
és a snapshotot ma **egyetlen fogyasztó sem olvassa**; (b) a ritkítás a brief
§6 5. pontjának 5%-os CPU-kerete miatt MÉRTEN szükséges (a naiv változat ~70%);
(c) a D1 tiltja a saját, olcsóbb egy-menetes RMS/peak/clip implementációt, tehát
a ritkítás az egyetlen megmaradt kar; (d) az implementer NEM hallgatta el —
brief §10.5 és a chunk „Latency trade-off (disclosed, not hidden)" szakasza.

**Teendő a snapshotot UI-ba kötő körnek:** a `statsStride`-ot valós eszközön
(AOT) mért profil alapján kell újratárgyalni, nem ennek a boxnak a JIT
`flutter test` mérése alapján.

### MINOR 2 — a `silentRatio` mezőnek MÁS a granularitása, mint a batch azonos nevű mezőjének

**Mérve:** PROBE B — ugyanazon a jelen a Live `silentRatio` **0,5**, a batch
`SignalQualityMath.silentRatio` (2048/1024-es keretezés) **0,4**. A különbség
szándékos és a `docs/rag/chunks/live-signal-quality.md` „Why a separate
`LiveQualityThresholds`" szakasza dokumentálja (a Live a SAJÁT 4096-os
blokk-granularitásán aggregál). Mivel a két érték ugyanabba a
`SignalQualitySnapshot.silentRatio` szerződés-mezőbe kerülhet két különböző
úton, a mezőszintű doc-comment is mondhatná ki a granularitást.

**Nem blokkoló:** a szerződés-mező szemantikája („silent frames aránya") mindkét
úton igaz, a különbség dokumentált, és a batch oldal nem ír ebbe a mezőbe.

### NOTE 1 — `version: 'live-quality-v2'` az ELSŐ leszállított verzió neve

A hangolási iterációk nyoma. Nem hiba (a verzió-sztring szabad), de a
`live-quality-v1` várható lenne. Egy későbbi kör átnevezheti, ha zavaró.

### NOTE 2 — a `lib/features/live/public.dart` az `allowed_paths`-on van, de nem módosult

Az implementer indoklása (brief §10.7): a Live `engine/**` szándékosan NEM
exportált, a keresztfunkciós szerződés (`SignalQualitySnapshot`) pedig E14-R04
óta exportálva van. Ez **lista-szűkítés**, ami megengedett — a scope-audit zöld.

## 4. Amit külön kerestem, és NEM találtam

- **Saját DSP-matek** a `live/` fában: nincs — a `peakDbfs`/`rmsDbfs`/
  `clippedSampleRatio`/`tonalness` mind a barrelen át hívott
  `SignalQualityMath`. A `_nearestRankPercentile` és a `_standardDeviation`
  aggregáció (nem DSP), az előbbi mérten azonos a batch referenciával (PROBE A).
- **Küszöb-tágítás a villogás ellen** (D4 tiltása): nincs — a villogás-védelem
  kizárólag `enterFrames`/`exitFrames`.
- **`architectureAllowlist` bővítés / mély import**: nincs.
- **Hangforrás- vagy személy-osztályozás** (ADR 0224 §4): nincs; a `speechLike`
  egyetlen spektrális sáv, és a fixture is „spectral proxy only" néven fut.
- **Nyers audio kiszivárgása** (ADR 0224 §1): nincs log, nincs hálózat, nincs
  perzisztálás — az elemző csak származtatott metrikákat ad ki.

## 5. VÉGSŐ DÖNTÉS

**APPROVED** — nyitott BLOCKER/MAJOR lelet **nincs**. A két MINOR és a két NOTE
dokumentált, mért és nem blokkolja a merge-öt; a MINOR 1 teendője a snapshotot
UI-ba kötő körre száll át (a brief §10.5 és a chunk hordozza).

A merge feltétele változatlanul a zöld kapu a merge SHA-n: `full-gate.yml` +
`router-ci.yml` `success`.
