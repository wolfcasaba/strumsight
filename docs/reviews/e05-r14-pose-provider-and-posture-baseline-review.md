# E05-R14 — Review

Brief: `docs/rounds/e05-r14-pose-provider-and-posture-baseline.md`
Diff: `git diff origin/main...minimax/e05-r14-pose-provider-and-posture-baseline`
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-07
Verdikt: **APPROVED** — mindkét javító kör után (fix round 1 `67d61bc`
formázás; fix round 2 `56146c2`, Codex/Terra, security S-MAJOR-1). Nulla
nyitott BLOCKER/MAJOR.

## Összegzés

Funkcionális: BLOCKER 0 · MAJOR 1 (FIXED, `67d61bc`) · MINOR 0 · NOTE 1
Security (külön jelentés): BLOCKER 0 · MAJOR 1 (**FIXED, `56146c2`**) · MINOR 1 (follow-up, E05-R20) · NOTE 3

**Security fix (fix round 2, Codex/Terra, motor-eszkaláció) SAJÁT, HARMADIK
független `/tmp` klónban ellenőrizve** (`/tmp/review-e05-r14-fix2`,
`56146c2` tip): a teljes gate 7/7 ZÖLD; a security-reviewer eredeti kerülő
mutációja (`'chin': PoseLandmarkId.neckReference`) SAJÁT kézzel
megismételve a TELJES `test/features/vision/` suite-on — pontosan 1 teszt
bukik (`the raw-name allow-list maps onto retained IDs only`), a másik 154
zöld marad. A fix pontosan azt teszi, amit a security-jelentés javasolt:
`poseLandmarkIdByRawName.keys.toSet()` pinnelve egy explicit 9-elemű
snapshotra + `.length == PoseLandmarkId.values.length` 1:1-kikényszerítés.
Diffje 26 sor, egyetlen fájl (`pose_privacy_audit_test.dart`), nulla
production-kód-módosítás.

**Funkcionális javító kör után:** friss, izolált `/tmp` klónban
(`67d61bc`/`94a762b` tip) saját kézzel újrafuttatva a teljes
`tools/round-gate.sh test/features/vision test/tooling` — mind a 7 lépés
genuinely ZÖLD, patch/kerülőút nélkül. A fix commit (`67d61bc`) diffje
pontosan 1 fájl, 3 sor (`dart format` tartalom-semleges tördelés) — tartalmi
kód nem változott.

**Motor-eszkaláció (AGENTS.md §15.6, pipeline-prompt §2):** a MiniMax M3 egy
javító kört kapott (fix round 1, a fenti F1-re) — elfogyott. A dedikált
security-review ÚJ, azelőtt nem ismert MAJOR-t talált (S-MAJOR-1, lásd
lent) — ez a MÁSODIK javító kör ennek a körnek, tehát a szabály szerint
Codex viszi (`tools/codex-round.sh`), külön munkapéldányban, ugyanazzal a
leletlistával. Csak akkor H4 halt, ha a Codex-kör UTÁN is nyitva marad
BLOCKER/MAJOR.

## Security-review kulcs-lelet (átemelve, a teljes indoklás a security-jelentésben)

**S-MAJOR-1 — a privacy-audit teszt (`test/features/vision/data/pose_privacy_audit_test.dart`)
egy negatív, hat-alszavas név-szűrőre (`eye/nose/mouth/ear/face/lip`)
támaszkodik, nem egy pozitív, zárt kulcshalmaz-pinre.** A security-reviewer
SAJÁT, az implementer és az én próbámtól FÜGGETLEN mutációval (`'chin':
PoseLandmarkId.neckReference` — a `chin` valódi arc-pont, de egyik tiltott
alszót sem tartalmazza) demonstrálta, hogy a **teljes 155-tesztes
vision-suite zöld marad**, miközben egy arc-koordináta ténylegesen bekerül az
audit-felszínbe `neckReference` álnéven. A MAI szállított allow-lista
(pontosan 9, helyes bejegyzés) emiatt NEM sérült — ez egy jövőre nézve
gyenge regressziós őr, amit a brief §9 explicit „az EGYETLEN gépi őr"-nek
nevez. Javasolt irány (a security-jelentésben): a teszt pinnelje a
`poseLandmarkIdByRawName` TELJES kulcshalmazát egy explicit snapshotra
(nem csak a value-halmazt), plusz egy `length`-egyenlőségi állítás az 1:1
leképezésre. Tisztán teszt-oldali javítás, production kód nem szükséges
hozzá.

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
- **Státusz:** FIXED (`67d61bc` — 1 fájl, 3 sor, tisztán `dart format`
  tördelés; `94a762b` a §10.3 handoffot friss, csonkítatlan gate-kimenettel
  frissítette). Saját, független újra-futtatás egy MÁSODIK, friss `/tmp`
  klónban (`/tmp/review-e05-r14-fix1`, patch nélkül): mind a 7 gate-lépés
  ZÖLD.

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

Első pass (javítás előtt, `aa6cad4` tip):

| Gate | Állított eredmény (§10.3) | Ellenőrizve (SAJÁT, izolált `/tmp` klón) |
|---|---|---|
| format | ZÖLD | ❌ **PIROS** — `pose_landmarks.dart:203`, ld. F1 |
| analyze | ZÖLD | ✅ (a format-sor helyi, tartalom-semleges tördelése UTÁN — a gate a format-nál megáll, ezért az analyze-tól lefelé csak a diagnosztikai, nem-commitolt javítással volt közvetlenül futtatható) |
| test test/features/vision | ZÖLD | ✅ — 155 teszt, mind zöld (a pose-specifikus 40 új teszttel együtt) |
| test test/tooling | ZÖLD | ✅ — 43 teszt, mind zöld (a 3 új manifest-mutáció-cellával együtt) |
| architecture | ZÖLD | ✅ — „Architecture dependencies OK (12 allowlisted deviation(s))" |
| secrets | ZÖLD | ✅ — „Secret scan OK (1930 file(s) scanned, 0 finding(s))" |
| l10n | ZÖLD | ✅ — „L10n parity OK (en → hu, 964 message(s))" |

**Második pass, javító kör UTÁN** (`94a762b` tip, MÁSODIK, teljesen friss
`/tmp/review-e05-r14-fix1` klón, patch/kerülőút NÉLKÜL):

| Gate | Eredmény |
|---|---|
| format | ✅ ZÖLD |
| analyze | ✅ ZÖLD |
| test test/features/vision | ✅ ZÖLD |
| test test/tooling | ✅ ZÖLD |
| architecture | ✅ ZÖLD — „12 allowlisted deviation(s)" (változatlan) |
| secrets | ✅ ZÖLD — „1931 file(s) scanned, 0 finding(s)" |
| l10n | ✅ ZÖLD — „964 message(s)" (változatlan) |
| CI (teljes suite + property + APK) | Dispatch az orchestrátor záró rituáléja — ld. lent |

## Dedikált security-review (risk = "high")

Kötelező (brief §11) — `security-reviewer` ágenssel,
`docs/reviews/e05-r14-pose-provider-and-posture-baseline-security.md`.
Verdikt: PASS a biztonsági lencsén (0 CRITICAL/BLOCKER), 1 MAJOR (S-MAJOR-1),
1 MINOR (E05-R20 follow-up), 3 NOTE. Az S-MAJOR-1 fix round 2-ben (Codex)
lezárva, SAJÁT harmadik `/tmp` klónban megismételt próbával megerősítve (ld.
fent).

## Merge-döntés

**Mindkét javító kör után minden gate genuinely ZÖLD, mindkét lelet SAJÁT
kézzel, független `/tmp` klónokban ellenőrizve** (nem az implementer/Codex
önjelentésére hagyatkozva). Nulla nyitott BLOCKER/MAJOR — sem funkcionális,
sem security oldalon. Hátra van: CI (build-apk + router-ci) zöld a merge SHA-n
és a záró rituálék (ADR 0052 zöld-kapu).
