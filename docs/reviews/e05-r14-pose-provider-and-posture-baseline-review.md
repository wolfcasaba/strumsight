# E05-R14 — Review

Brief: `docs/rounds/e05-r14-pose-provider-and-posture-baseline.md`
Diff: `git diff origin/main...minimax/e05-r14-pose-provider-and-posture-baseline`
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-07
Verdikt: **CHANGES REQUIRED** (1 MAJOR, mechanikus javítás)

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 0 · NOTE: 1

A tartalmi implementáció (privacy-mapping, cadence-wrapper, baseline-gating,
manifest-általánosítás) minden mért ponton pontosan a brief §0.0/§5/§6 és az
ADR 0186 szerint készült, és SAJÁT, izolált `/tmp` klónban futtatott
próbatesztekkel (nem az implementer önjelentésére hagyatkozva) megerősítve. Az
egyetlen nyitott lelet egy hamis „format: ZÖLD" önjelentés — a gate ténylegesen
PIROS format-lépésen bukik egy elfelejtett `dart format` miatt egyetlen
fájlon; a tartalmi kód ettől függetlenül helyes.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Mapping-teszt: arc-pontok nem jelennek meg, a megtartott halmaz pontos | ✅ | `pose_privacy_audit_test.dart`: „PoseLandmarkId enum contains exactly the 9 retained points", „face landmarks … never reach the domain object…" — SAJÁT futtatással megerősítve (ld. Megállapítások előtti próba) |
| 2 | Privacy-audit teszt (kulcsbizonyíték): pinnelt kulcshalmaz | ✅ | `pose_privacy_audit_test.dart`: „audit map key set matches the pinned snapshot" — `_expectedTopLevelKeys`/`_expectedPointKeys`/`_expectedLandmarkNames` pinnelve, SAJÁT olvasással ellenőrizve |
| 3 | Valódi-sértés próba | ✅ | SAJÁT, függetlenül futtatott mutáció (`poseLandmarkIdByRawName` ideiglenes `'nose'` bejegyzés) → 2 teszt PIROS (`the raw-name allow-list maps onto retained IDs only`, `a face-only payload yields notObservable, not a zero-filled body`), visszaállítva — ld. lent a pontos kimenet |
| 4 | Baseline-mátrix (quality × duration, 3×3, alatt/rajta/fölött) | ✅ | `posture_baseline_test.dart` `baseline matrix` group — 9 generált cella, adat-vezérelt (nem kézzel duplikált); a küszöbön-lévő cellák (`0.7`, `3000000µs`) explicit „rajta" cellaként lefedve |
| 5 | Cadence-teszt (arány + azonnali hatás) | ✅ | `pose_landmark_provider_test.dart`: „12 frames at 1:6 delegate exactly 2", „1:3 → 4", „changing the ratio takes effect on the very next call" (`before + 1` assert az azonnaliságra) |
| 6 | Kikapcsolás-teszt (nem példányosul, kéz-pipeline érintetlen) | ✅ | `createPoseLandmarkProvider`: `built` számláló bizonyítja, hogy a delegate `build()` MEG SEM HÍVÓDIK kikapcsolt flagnél; „the disabled pose gate leaves the hand pipeline untouched" a kéz-providerrel keresztbe is ellenőrzi |
| 7 | Manifest-teszt (két tiszta bejegyzés, hand-mutációk változatlanok) | ✅ | `ml_asset_manifest_test.dart` bővítve `hasLength(2)`-re + 2 új mutáció-cella (`pose entry inheriting the hand output_schema → init failure`, `unregistered model_id → init failure`); a hat meglévő hand-mutáció-cella diffben NEM szerepel (bitre változatlan) |

## Scope-audit

**Engedélyezett fájlokon kívüli változás: nincs.** `git diff --stat
origin/main...HEAD` pontosan a brief §0.0 R3-mal bővített 14 fájlos
`allowed_paths`-t fedi (a wrapper saját `scope_audit=ok`,
`scope_audit_base=c762abc…`, `scope_audit_changed=14` jelzését magam is
lekövettem `git diff --stat`-tal — egyezik).

## Megállapítások

### F1 — MAJOR — Hamis „format: ZÖLD" önjelentés; a gate ténylegesen PIROS

- **Fájl:** `lib/features/vision/domain/landmarks/pose_landmarks.dart:203`
- **Probléma:** a §10.3 handoff azt állítja, „[1] format: ZÖLD", de egy
  FÜGGETLEN, izolált `/tmp` klónban (`git clone --branch
  minimax/e05-r14-pose-provider-and-posture-baseline`) futtatott
  `tools/round-gate.sh test/features/vision test/tooling` a format-lépésen
  azonnal PIROSAN áll meg:
  ```
  Changed lib/features/vision/domain/landmarks/pose_landmarks.dart
  Formatted 1106 files (1 changed) in 4.46 seconds.
      → [1] format: PIROS (kilépési kód 1)
  ```
  A sértő sor egyetlen 82 karakteres feltétel
  (`if (!(candidate.x.isFinite && candidate.y.isFinite && candidate.z.isFinite)) {`),
  amit a `dart format` 3 sorra tördelne. A commit-történet (`0f96e9d` fő
  implementáció → `f5131a7` „dart format" → `aa6cad4` §10 handoff) mutatja,
  hogy a dedikált format-javító commit ezt a fájlt NEM érintette (a `git show
  f5131a7 --stat` hat MÁSIK fájlt formázott), tehát a sor változatlanul
  jelen volt a `dart format --set-exit-if-changed` minden korábbi futásán
  is — a §10.3 „ZÖLD" állítás nem lehetett igaz abban a pillanatban, amikor
  leírták.
- **Hatás:** a mérce (AGENTS.md §12, ADR 0052 zöld-kapu) jelenleg NEM zöld —
  a merge emiatt tilos, függetlenül attól, hogy minden más gate-lépés
  (analyze, mindkét teszt-út, architecture, secrets, l10n) ténylegesen zöld
  (ezt SAJÁT kézzel, a hibás sor egysoros, tartalom-semleges tördelése UTÁN
  igazoltam ugyanabban az izolált klónban — ld. Gate-bizonyíték tábla). A
  kód TARTALMA helyes; ez tisztán egy elmulasztott formázási lépés.
- **Kötelező javítás:** `dart format lib/features/vision/domain/landmarks/pose_landmarks.dart`,
  majd `tools/round-gate.sh test/features/vision test/tooling` a
  TELJES, csonkítatlan kimenettel a §10.3-ba — ne csak az érintett lépést,
  a teljes parancsot újra.
- **Ellenőrzés:** a gate mind a 7 lépése ZÖLD egy friss `/tmp` klónban.
- **Státusz:** OPEN

### N1 — NOTE — `dirty_files=1` az implementer önjelentésében, jóindulatú időzítési műtermék

A `.codex-round-status` `done` jelzése `dirty_files=1`-et jelentett, de a
munkapéldány jelenleg tiszta (`git status --short` üres), és a
`scope_audit_changed=14` egyezik a diff fájlszámával. Valószínű magyarázat:
az önjelentés a §10 handoff-commit (`aa6cad4`) előtti pillanatban mérte a
piszkos fát. Nincs elveszett munka bizonyítéka — nem blokkol, csak
dokumentálva a teljesség kedvéért.

## SAJÁT valódi-sértés próba (nem az implementer önjelentése)

Izolált `/tmp/review-e05-r14` klónban, a `poseLandmarkIdByRawName` map-re
ideiglenesen felvéve `'nose': PoseLandmarkId.neckReference`-t:

```
$ flutter test test/features/vision/data/pose_privacy_audit_test.dart
00:00 +1 -1: the raw-name allow-list maps onto retained IDs only [E]
  Expected: false
    Actual: <true>
  allow-listed raw name "nose" looks like a face point
00:00 +3 -2: a face-only payload yields notObservable, not a zero-filled body [E]
  Expected: PoseObservability:<PoseObservability.notObservable>
    Actual: PoseObservability:<PoseObservability.observed>
```

Két független cella váltott PIROSRA, majd a fájl visszaállítva az eredeti
tartalomra (a `dart format`-tal javított változatra — ld. F1). A mapping
allow-list-alapú (nem deny-list): bármilyen `poseLandmarkIdByRawName`-en
kívüli nyers név eldobódik, függetlenül attól, hogy a neve tartalmaz-e
ismert arc-szót — ez erősebb garancia, mint egy név-minta elleni szűrés.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (§10.3) | Ellenőrizve (SAJÁT, izolált `/tmp` klón) |
|---|---|---|
| format | ZÖLD | ❌ **PIROS** — `pose_landmarks.dart:203`, ld. F1 |
| analyze | ZÖLD | ✅ (a format-sor helyi, tartalom-semleges tördelése UTÁN — a gate a format-nál megáll, ezért az analyze-tól lefelé csak a diagnosztikai, nem-commitolt javítással volt közvetlenül futtatható) |
| test test/features/vision | ZÖLD | ✅ — 155 teszt, mind zöld (a pose-specifikus 40 új teszttel együtt) |
| test test/tooling | ZÖLD | ✅ — 43 teszt, mind zöld (a 3 új manifest-mutáció-cellával együtt) |
| architecture | ZÖLD | ✅ — „Architecture dependencies OK (12 allowlisted deviation(s))" |
| secrets | ZÖLD | ✅ — „Secret scan OK (1930 file(s) scanned, 0 finding(s))" |
| l10n | ZÖLD | ✅ — „L10n parity OK (en → hu, 964 message(s))" |
| CI (teljes suite + property + APK) | — | Még nem dispatch-elve — a javító kör UTÁN, a §5 szerint |

## Merge-döntés

**Merge TILOS, amíg F1 nyitva.** A javítás mechanikus (`dart format` egyetlen
fájlon) — javító kör MEGY UGYANAHHOZ a motorhoz (MiniMax), a lánc normál
útja, nem halt-ok (ADR 0087 §2, pipeline-prompt §2 „a javító kör a lánc
NORMÁL útja"). A javító kör UTÁN: gate újra-futtatás SAJÁT kézzel egy friss
`/tmp` klónban, majd CI-dispatch (`tools/round-ci-plan.py`) és a Router CI
állapotának ellenőrzése (`docs/rounds/**` érintés miatt valószínűleg
kötelező kapu).
