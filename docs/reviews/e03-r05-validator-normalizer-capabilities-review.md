# E03-R05 — Review

Brief: `docs/rounds/e03-r05-validator-normalizer-capabilities.md`
Diff: `git diff origin/main...codex/e03-r05-validator-normalizer-capabilities-r2`
Reviewer: Claude Sonnet 5 (orchestrator) · Dátum: 2026-08-02
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 1 · MAJOR: 0 · MINOR: 0 · NOTE: 1

## Folyamat-előzmény (fontos kontextus a leletekhez)

Ez a kör két korábbi `H6` önjavító körön ment át (PR #61, #62, #63 —
`docs/LESSONS.md` L54/L55/L56): a MiniMax M3 a router szerződését megszegve
saját maga commitolt (`d0546f0`, worktree `ss-router-e03-r05-2`), amit
`tools/ai_router/security.py` helyesen `BLOCKED`-ba futtatott. A gyökérokot
(git-guard shim hiánya a shell-rétegen) a H6 #2 heal zárta le — de a
worktree-ben lévő `d0546f0` munka maga scope-tiszta és tartalmilag kész volt,
csak commit-jogosultság nélkül készült. Az orchestrátor (én) ezt a jelen
session pre-flightjában `docs/LESSONS.md` L50 mintája szerint reconciliálta:
`git reset --soft` a pre-flight commitra, `git rebase origin/main` (egyetlen
új commit különbség, konfliktusmentes), scope-audit, saját kézzel
újrafuttatott gate + a teljes `test/features/song_trainer` suite, majd
saját (orchestrátor) authorship alatt commitolva (`6f424da`). Ez a review
tehát a rekonciliált, orchestrátor-commitolt diffet vizsgálja — nem
M3 saját (soha nem elfogadott) commitját.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | `normalize(normalize(x)) == normalize(x)` és canonical event ordering stabil | ✅ | `test/property/song_normalizer_property_test.dart` — 4 property teszt, PROPERTY_SEED=42 (reviewer saját futtatás, izolált klón), idempotencia + ID-megőrzés + event-identity + monoton ordering mind zöld |
| 2 | Validator ismeretlen/rossz inputnál reportot ad, nem nyers exceptiont | ✅ | `song_validator_test.dart` 15 teszt zöld; a validator kódja (`song_validator.dart`) sehol nem dob, minden ág `SongValidationIssue`-t gyűjt |
| 3 | Fatal dokumentum nem persistálható; warningos dokumentum preview-zhető | ❌ | **Lásd F1 — BLOCKER.** Egy teljesen valid dokumentum (létező cél-akkorddal) HAMISAN fatal `strumTargetChordMissing`-et kap, ha a `StrumTrack` a `tracks` listában a célzott `ChordTrack` ELŐTT szerepel — a dokumentum ekkor tévesen nem-persistálhatóként jelenik meg, holott minden esemény valid |
| 4 | Unsupported chord vagy technique esetén display és scoring őszintén eltér; polyphonic pitch false | ✅ | `song_capability_resolver_test.dart` 9 teszt zöld, §6 mátrix mind a 4 kombinációja lefedve (reviewer saját olvasással is megerősítve: `_chordCapability`/`_pitchCapability` a severity-t sosem keveri a capability tengellyel) |

## Scope-audit

`git diff --stat origin/main...HEAD` (a rebase utáni, orchestrátor-commitolt
állapoton): **13 fájl, mind a brief `allowed_paths` listáján** — nincs
listán kívüli változás.

## Megállapítások

### F1 — BLOCKER — `SongValidator._validateTracks` a strum→chord
cross-track referencia-ellenőrzést a `document.tracks` ITERÁCIÓS SORRENDJÉTŐL
teszi függővé, holott a `SongDocument.tracks` semmilyen sorrendi szerződést
nem ad (a kanonikus rendezés a normalizer KÜLÖN, KÉSŐBBI lépése — E03-R05
§0.0 saját méré­se szerint is)

- **Fájl:** `lib/features/song_trainer/domain/services/song_validator.dart:183-262`
- **Probléma:** `_validateTracks` egyetlen lineáris végigmenetelés
  `document.tracks`-on, és a `chordEventIds` halmazt UTÓLAG, ugyanabban a
  menetben tölti fel (183-189. sor gyűjti a `ChordTrack` eseményeit, majd a
  232-258. sor a `StrumTrack` `targetChordId`-ját a MÁR eddig látott
  `chordEventIds`-hoz hasonlítja). Ha egy `StrumTrack` a listában KORÁBBAN
  szerepel, mint a célzott `ChordTrack`, a `chordEventIds` halmaz a strum
  feldolgozásakor még üres — a validator HAMISAN `strumTargetChordMissing`
  fatal issue-t jelent egy ténylegesen létező célra.
- **Hatás:** egy import- vagy szerkesztő-útvonal, ami a track-listát NEM a
  normalizer kanonikus `(kind, id)` sorrendjében adja át a validátornak (pl.
  `importPreview` profil egy nyers, még nem normalizált dokumentumon — ez
  pontosan a brief §1 célja: "importpreview... stabil reportjai") egy
  teljesen jó dalt hamisan `fatal`/nem-persistálhatóként utasít el. Ez
  közvetlenül megszegi a §6 acceptance 3. sorát és az §5 kötött döntés 1-et
  ("fatal persist capabilityt mindig tilt" — itt a "fatal" maga hamis).
- **Reprodukció (eldobható próbateszt, reviewer írta és futtatta, majd
  törölte a merge előtti szabály szerint):** egy dokumentum két trackkel —
  `StrumTrack` (egyetlen esemény, `targetChordId: SongEventId('e-1')`)
  ELŐBB a listában, utána egy `ChordTrack` a valóban létező `e-1` chord
  eventtel. Várt: `report.hasFatalIssue == false`,
  `report.isPersistable == true`. Mért (a mostani kódon): `hasFatalIssue ==
  true`, a report tartalmazza a `strumTargetChordMissing` fatal issue-t a
  létező cél ellenére. RED reprodukálva, majd a próbateszt törölve
  (`test/features/song_trainer/domain/_probe_strum_order_test.dart`, nem
  része a diffnek).
- **Kötelező javítás:** a `chordEventIds` halmazt a `StrumTrack`-ok
  feldolgozása ELŐTT, egy KÜLÖN, teljes előzetes menetben kell összegyűjteni
  minden `ChordTrack`-ból (két lépéses algoritmus: 1) gyűjtsd össze az
  összes chord-event ID-t minden trackből, 2) validáld a strum-eseményeket
  ez ellen) — így a validator eredménye a `tracks` lista sorrendjétől
  FÜGGETLEN lesz, ahogy azt a §0.0 saját mérése is elvárná egy
  document-szintű, cross-collection validátortól.
- **Ellenőrzés:** a fenti reprodukciós szcenárió mint PERMANENS regressziós
  teszt a `song_validator_test.dart`-ban (nem eldobható) — mindkét
  sorrendben (`StrumTrack` előbb ÉS `ChordTrack` előbb) ugyanazt a `false`
  `hasFatalIssue`-t kell adnia egy egyébként valid dokumentumra.
- **Státusz:** OPEN

### N1 — NOTE — a §6 mátrix pozitív strum→chord esete (létező cél)
egyáltalán nincs lefedve a beküldött tesztkészletben

- **Fájl:** `test/features/song_trainer/domain/song_validator_test.dart`
- **Megfigyelés:** a tesztfájlban egyetlen `targetChordId`-t használó eset
  van (240-269. sor), és az is a HIÁNYZÓ cél esetét fedi. A pozitív eset
  (létező cél, bármilyen track-sorrendben) hiánya közvetlenül magyarázza,
  miért maradhatott észrevétlen az F1 hiba egy egyébként 100%-ban zöld
  gate mellett — pontosan az a minta, amit `docs/execution/09-review-
  report.md` és a brief §6 saját maga is kimond ("bemásolt zöld kimenet
  önmagában nem evidencia").
- **Kötelező javítás:** az F1 javításával együtt adott regressziós teszt ezt
  is lefedi — külön akció nem szükséges, csak jegyzem, hogy ez NEM
  hiányzó lefedettség kritikán múlt, hanem tesztezt tervezési vakfolt volt.
- **Státusz:** a fix commitjával együtt zárul.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld (brief §10.2) | ✅ reviewer saját futása, izolált `/tmp/review-e03-r05` klónban |
| analyze | zöld (brief §10.2) | ✅ ua. |
| 4 célzott teszt (validator/normalizer/capability/property) | zöld (brief §10.2) | ✅ ua., `tools/round-gate.sh` teljes kimenettel |
| architecture | zöld (brief §10.2) | ✅ ua. |
| `flutter test test/features/song_trainer/` | 177/177 (brief §10.2 állítja 177-et) | ✅ reviewer saját futása is 177/177 |
| CI (teljes suite + property + APK) | run dispatch-elve a PR-hez | ⏳ folyamatban a review írásakor (run 30742009504, branch `codex/e03-r05-validator-normalizer-capabilities-r2`) — a merge-döntés előtt az orchestrátor újra ellenőrzi |

## Merge-döntés

**Merge TILOS**, amíg F1 nyitva van (BLOCKER). A javító kört ugyanaz a
motor viszi (auto router `resume`, findings-fájllal) — ADR 0087 §2, a kör
saját, még nem merge-elt artefaktuma. A router `m3_attempts=1`-et mutat egy
korábbi, security.py által elutasított self-commit kísérletből (a
mögöttes hiba a H6 #2 healben lezárva) — ez a session ezt sanctioned
`reset --task-id`-vel nullázza (docs/LESSONS.md L48/L50 minta) mielőtt a
findings-fájlt beadja, hogy a fix-kör tiszta 1-attempt keretet kapjon.
