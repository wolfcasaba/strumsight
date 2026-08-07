# E05-R12 — Review

Brief: `docs/rounds/e05-r12-hand-landmark-provider-and-model-manifest.md`
Diff: `git diff 414ea28...e7f6823` (pre-flight commit → implementer HEAD),
branch `minimax/e05-r12-hand-landmark-provider-and-model-manifest`
Reviewer: Claude Sonnet 5 (orchestrator) · Dátum: 2026-08-07
Verdikt: **CHANGES REQUESTED**

## Összegzés

BLOCKER: 1 · MAJOR: 0 · MINOR: 0 · NOTE: 1

Az implementáció tartalmilag erős — a 21-pontos topológia, a hand-count és a
timestamp mátrix, a manifest-őr négy hibaesete mind valódi, célzott
tesztekkel bizonyított (nem csak self-report). Az EGYETLEN BLOCKER egy
konkrét, jól körülhatárolt scope-sértés: egy committolt bináris placeholder,
ami nincs a brief `allowed_paths` listáján és ellentmond az ADR 0185
Döntés 2/3-nak.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Mapping-teszt rögzített kimeneten, mind a 21 pont | ✅ | `test/features/vision/data/hand_landmark_provider_test.dart:37-61` — `HandLandmarkId.values`-en végigmegy, mindegyikre `byId(id) != null` |
| 2 | Kéz-szám mátrix 0/1/2/>2 | ✅ | ugyanott `Hand-count matrix` group, 4 teszt; a `>2` cella `lessThanOrEqualTo(2)`-vel + `RecordedHandLandmarkProvider.fixtureManyHands()` `all.take(2)`-vel bizonyítva |
| 3 | Timestamp-mátrix növekvő/azonos/csökkenő | ✅ | `Timestamp matrix` group, 4 teszt; a csökkenő cella `droppedTimestampCount`-ot ÉS `lastAcceptedTimestampUs` nem-regressziót is ellenőriz |
| 4 | Manifest-őr négy hibaesete | ✅ | `test/tooling/ml_asset_manifest_test.dart` `VisionModelManifest — manifest-guard mutations` group, 5 teszt (missing checksum/wrong checksum/missing license/mismatched output_schema/well-formed), mind saját tempdir-fixture-rel, az audio-oldali precedens mintáját követve |
| 5 | Valódi-sértés próba (§10) | ✅ | implementer önjelentése szerint checksum-flip → RED → restore; **saját, független próba** (lásd F1 alatt) is megerősíti a mechanizmust, bár más éllel |
| 6 | Az ADR 0185 megnevezi a stacket/licencet/méretet/alternatívákat/visszavonást | ✅ | ADR 0185 pre-flightban kész, az implementer nem módosította (`git diff` a fájlra üres a pre-flight commit óta) |
| 7 | Audio modellfájlok bájtra változatlanok | ✅ | `git diff --stat 414ea28..HEAD -- assets/ml/*.bin` üres; a diff csak a JSON manifestet és az ÚJ `.tflite`-ot érinti |

Mind a hét kritérium teljesül **tartalmilag** — az egyetlen probléma nem egy
acceptance-cella hiánya, hanem egy scope-sértés (lásd F1), ami a kritériumok
5. és 4. pontját is más, tisztább úton kellene bizonyítania.

## Scope-audit

```
python3 tools/scope-audit.py --repo <munkapéldány> \
  --brief docs/rounds/e05-r12-hand-landmark-provider-and-model-manifest.md \
  --base 414ea28
```

**FAILED** — 1 útvonal a listán kívül:

```
- path outside allowed scope: assets/ml/hand_landmarker_deferred.tflite
```

(A `.codex-round-status` jelzésben `scope_audit=skipped` szerepel — az
orchestrátor elmulasztotta a `ROUND_BRIEF` env-vart a dispatch hívásban; ez
a mulasztás a fenti kézi audittal pótolva, a pipeline-prompt §1.1
dokumentált fallback-je szerint. A 12 másik változott útvonal mind az
`allowed_paths` listán van.)

## Megállapítások

### F1 — BLOCKER — committolt bináris placeholder a listán kívül, ellentmond az ADR 0185-nek

- **Fájl:** `assets/ml/hand_landmarker_deferred.tflite` (ÚJ, 1 bájt, commit
  `10518c1`); ripple: `lib/core/ml/vision_model_manifest.dart:222-238`,
  `ml/make_manifest.py:276-310` (`_build_vision_models`), `assets/ml/model_manifest.json`
  `vision_models[0].path`.
- **Probléma:** a brief `allowed_paths` listája (a `docs/rounds/e05-r12-*.md`
  TOML blokkja) NEM sorol fel semmilyen `assets/ml/*.tflite`/`*.task`
  útvonalat — ez szándékos, mert az ADR 0185 §Döntés 2/3 (amit az
  orchestrátor írt a pre-flightban, az implementer csak olvasta) kifejezetten
  eldöntötte: **ez a kör NEM szerzi be, NEM tölti le és NEM pinneli a bináris
  assetet**, és `pubspec.yaml` sem kap inference-függőséget. Az implementer a
  `vision_model_manifest.dart` validátorát és a `make_manifest.py`
  `_build_vision_models` függvényét úgy írta meg, hogy a `status = "deferred"`
  bejegyzés IS megköveteli a fájl létezését a lemezen + a checksum
  egyezését egy VALÓDI fájllal szemben — ezért egy 1-bájtos placeholder
  binárist committolt, hogy a validátor egységes maradjon.
- **Hatás:** scope-sértés, gépi auditttal mérve (fent). Emellett a
  `ml/make_manifest.py` `_build_vision_models` egy `FileNotFoundError`-t
  dob, ha ez a fájl valaha eltűnik — azaz a generátor MOST már örökre
  megköveteli egy bináris jelenlétét, pontosan azt intézményesítve, amit az
  ADR 0185 kizárt.
- **Kötelező javítás:**
  1. `git rm assets/ml/hand_landmarker_deferred.tflite`.
  2. `validateVisionManifest`-ben (`lib/core/ml/vision_model_manifest.dart`)
     `status == VisionModelStatus.deferred` esetén **NE** dereferálja a
     fájlrendszert (ne `File(...).existsSync()`, ne checksum-összehasonlítás
     egy valódi fájllal) — csak a `sha256` MEZŐ formátumát ellenőrizze
     (64 lowercase hex, változatlanul). A fájlrendszeres létezés+checksum-
     egyezés ellenőrzés maradjon meg egy jövőbeli `status = "active"`
     bejegyzéshez (a validátor-függvény maradjon rá képes), de EBBEN a
     körben csak tempdir-fixture-ön keresztül tesztelve (az 5 meglévő
     mutációs teszt mintáját követve egy ÚJ, `status: 'active'` cellával),
     NEM a repo committolt fájlján.
  3. `ml/make_manifest.py` `_build_vision_models`: a `deferred` specekhez
     NE olvasson fájlt a lemezről — a `sha256` egy explicit, dokumentált
     placeholder-string legyen a `_VISION_MODEL_SPECS` tuple-ben (pl.
     64 db `'0'`, kommenttel: „nincs valódi asset, aktiváláskor cserélendő”).
     A fájlrendszeres checksum-számítás (a mai `_build_entry` mintája) csak
     akkor fusson, ha a spec `status == 'active'` — ezt a jövőbeli aktiváló
     kör spec-je fogja kiváltani.
  4. `assets/ml/model_manifest.json` `vision_models[0].sha256` a fenti
     placeholder-string legyen (nem egy tényleges fájl checksuma).
  5. `test/tooling/ml_asset_manifest_test.dart`:
     - a **'shipping manifest vision_models entry is well-formed'** teszt
       maradjon, de a validátor 2. pont szerinti módosítása után fájl
       nélkül is zöld lesz (a shipped bejegyzés `deferred`).
     - a **'wrong checksum'** mutációs teszt jelentése változik: mivel egy
       `deferred` bejegyzésnek nincs valódi fájlja, „rossz checksum” a
       formátum-validáció esetét jelentse (pl. nem 64 hex karakter, vagy egy
       szintaktikailag helytelen string) — ne egy fájl-mismatch esetet.
     - 'missing checksum', 'missing license', 'mismatched output_schema',
       'well-formed' változatlanul megy tovább (ezek nem függenek a
       fájlrendszertől egy deferred bejegyzésnél sem, a 2. pont után sem).
- **Ellenőrzés:** `git rm` után `flutter test test/tooling/ml_asset_manifest_test.dart`
  fusson zölden (mind a 7 cella, beleértve az új `active`-ági tempdir-tesztet
  is); `python3 tools/scope-audit.py --repo <munkapéldány> --brief
  docs/rounds/e05-r12-*.md --base <pre-flight-sha>` 0 lelettel térjen vissza;
  `git diff --stat -- assets/` üres legyen (a szöveges JSON manifest kivételével,
  ami TARTALMAZ soronkénti diffet, de bináris fájlt nem).
- **Saját, független próba (a review protokoll 5. lépése):** a review-klónban
  `rm assets/ml/hand_landmarker_deferred.tflite` után
  `flutter test test/tooling/ml_asset_manifest_test.dart` lefuttatva
  **PONTOSAN 1** teszt bukott (`shipping manifest vision_models entry is
  well-formed`, üzenet: `vision_models[0] asset missing:
  assets/ml/hand_landmarker_deferred.tflite`) — a másik öt, mutációs
  (tempdir-alapú) teszt változatlanul zöld maradt. Ez megerősíti, hogy a
  fájl KIZÁRÓLAG a valódi, committolt manifest ellenőrzéséhez kell, a
  mátrix-lefedettséghez nem — tehát a fenti javítás nem csökkenti a valódi
  tesztlefedettséget.
- **Státusz:** OPEN

### N1 — NOTE — a „decreasing before any accept” teszt neve félrevezető

- **Fájl:** `test/features/vision/data/hand_landmark_provider_test.dart:156-166`.
- **Megfigyelés:** a `MonotonicHandLandmarkProvider._lastAcceptedUs` kezdőértéke
  `-1`, ezért az ELSŐ valaha érkező hívás (bármilyen nem-negatív timestamppel)
  mindig elfogadódik — nincs is ténylegesen tesztelhető „csökkenő az első
  elfogadás előtt” eset. A teszt valójában „csökkenő PONTOSAN egy előzmény
  után”-t mér, ami a szomszédos teszttel majdnem azonos. Nem hibás, csak a
  név ígér többet, mint amit mér.
- **Hatás:** nincs — nem blokkol, nem téveszt meg contentben, csak
  elnevezésben.
- **Javasolt (nem kötelező):** a teszt átnevezése „decreasing after the
  first accepted call”-ra egy jövőbeli körben.
- **Státusz:** OPEN (non-blocking)

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ — saját `/tmp/review-e05-r12` klónban, `tools/prepare-flutter-generated.sh` után, `tools/round-gate.sh test/features/vision test/tooling` |
| analyze | zöld | ✅ — ugyanott |
| test test/features/vision | zöld | ✅ — ugyanott |
| test test/tooling | zöld | ✅ — ugyanott (F1 felfedezése UTÁN, külön `flutter test` hívással a konkrét cella izolálására) |
| architecture | zöld | ✅ — `dart run tool/check_architecture.dart`, 12 allowlistelt eltérés (a kör nem bővítette) |
| secrets | zöld | ✅ |
| l10n | zöld | ✅ |
| CI (teljes suite + property + APK) | még nem dispatch-elve | ⏳ — a javító kör után, a round-ci-plan.py döntése szerint |

`gate_shape=ok` a jelzésfájlban (nincs csonkoló `\| tail`/`&&` a naplóban,
mérve).

## Merge-döntés

**Merge TILOS amíg F1 nyitva** (ADR 0052 — nyitott BLOCKER). Javító kör
szükséges, ugyanazon a motoron (MiniMax, ez az 1. javító kör — a
motor-eszkalációs küszöb 1 javító kör után Codex-re vált, ha még mindig
nyitott BLOCKER/MAJOR marad).
