# E05-R14 — Security / Privacy / Prompt-Injection Review

Round: **E05-R14** — Pose landmark provider és posture baseline
Branch: `minimax/e05-r14-pose-provider-and-posture-baseline` @ `aa6cad4` (a fix
round 1 — `dart format`, `67d61bc`/`94a762b` — előtti tip; a lelet a
formázástól független, tartalmi kérdés, a fix round 1 nem érinti)
Base: `main` @ `c762abc` (`git diff c762abc..HEAD` = 14 fájl, +1987 / −8; 5 új
production Dart fájl + additív `public.dart` + manifest/generátor/validátor +
4 teszt)
Risk header: `risk = "high"` → dedikált security-review kötelező; a kör-brief
§11 külön nevesíti ezt az ágenst (adatminimalizálás, logolt mezők,
manifest-validátor-paritás)
Reviewer: security-reviewer agent (read-only), izolált klón
`/tmp/security-review-e05-r14`
Módszer: az 5 production fájl + a módosított validátor teljes olvasása; a
szerződés-dokumentumok (ADR 0178, ADR 0186, brief §0.0/§5/§6) keresztref;
danger-grep (IO/network/logging/secret/permission) a diff production fájljain;
a repo saját `tool/ci/check_secrets.dart` kapujának lefuttatása; és **négy
saját kezű reprodukciós próba** eldobható teszt-/pure-Dart harness-szel (mind
visszaállítva, `git status` tiszta).

## Verdikt: **PASS a biztonsági lencsén (0 CRITICAL, 0 BLOCKER) — 1 MAJOR**

A kör tiszta a nem tárgyalható termékhatárokra: nincs persistencia, nincs
hálózat, nincs raw frame/koordináta logolás, nincs titok, nincs új permission,
nincs prompt-injection útvonal. A privacy-ígéret **mai** állapota helyes: a
szállított allow-lista pontosan a 9 engedélyezett pontot tartalmazza, és a
mapping valóban eldobja az arc-pontokat — ezt saját kezűleg reprodukáltam.

A MAJOR nem határsértés a mai kódon, hanem **a kör kulcsbizonyítékának mért
hiányossága**: a privacy-audit teszt — amit a brief §9 szó szerint „az
egyetlen gépi őr"-nek nevez — egy név-heurisztikára támaszkodik, amelyet egy
valódi arc-landmark megkerül, és ilyenkor a **teljes vision-suite zöld
marad**.

> **Merge-hatás:** a biztonsági lencse verdiktje PASS (0 CRITICAL/BLOCKER). A
> kör **saját** §11 merge-mércéje viszont „nulla OPEN BLOCKER/**MAJOR**" —
> tehát a MAJOR-1 a kör saját szabálya szerint merge előtt lezárandó (javítás
> vagy dokumentált, indokolt waiver).

## Severity table

| # | Súlyosság | Fájl:sor | Egy sor |
|---|---|---|---|
| 1 | **MAJOR** | `pose_privacy_audit_test.dart:46-53,73-88` + `pose_landmarks.dart:40-51` | A privacy-őr a nyers NÉV hat tiltott alszavára támaszkodik; egy ezeket elkerülő valódi arc-pont (pl. `chin`) allow-listázva a teljes vision-suite-ot zölden hagyja (155/155 mérve), miközben arc-koordináta kerül az audit-felszínre. |
| 2 | MINOR | `posture_baseline.dart:199-204` | `PostureObservation.state` MINDIG `good`, ha akár egyetlen landmark közös; `needsImprovement` sosem keletkezik — mérve: 1 pont, `maxDrift = 4.257` → `good` (§5.5 látens mag). |
| 3 | NOTE | `pose_landmarks.dart:199-213` | Duplikált allow-listás nyers név esetén az UTOLSÓ nyer, csendben (kód-olvasásból determinisztikus); egy jövőbeli alias-bővítés így felülírhat egy valódi pontot. |
| 4 | NOTE | `vision_model_manifest.dart:257-271` | Az `active`-ág `File('$root/$path')` olvasásának továbbra sincs path-traversal védelme — **változatlanul átvéve az R12-ből**, ott már MINOR-1-ként dokumentálva; ez a kör nem rontott rajta (sőt szűkített, ld. lent). |
| 5 | NOTE | `posture_baseline.dart:34-36` | `PostureBaselineConfig` validációja `assert`-alapú (release-ben strippelt) — próbálva debug/release alatt, **valódi kapumegkerülést nem sikerült előállítani**. |

---

## Nem tárgyalható termékhatárok (AGENTS.md §5) — mind betartva

- **§5.1 — nyers audio/kamera-frame nem hagyja el az eszközt (ADR 0178 Döntés 1–2).** Az 5 új production fájlon a danger-grep (`print|debugPrint|log(|Logger|dio|Dio|http|Http|SharedPreferences|SecureStore|KeyValueStore|File(|writeAs`) **üres**. A `VisionImage` bemenet sehol nem kerül tárolásra: a `RecordedPoseLandmarkProvider.infer` csak a `timestamp`-ot olvassa ki belőle (`recorded_pose_landmark_provider.dart:202`), a `bytes` mezőt egyetlen új fájl sem érinti. A `CadenceLimitedPoseLandmarkProvider` a kihagyott frame-ekhez az utolsó **eredményt** tartja meg (`pose_landmark_provider.dart:84,130`), nem a frame-et — nincs frame-history.
- **§5.2 — kijelentkezve/diagnostics-off nincs rejtett hálózati kérés.** Nincs hálózati felület egyáltalán; nulla `Dio`/HTTP/socket import a körben. Nincs új platform permission (a diff nem érint manifestet/Info.plist-et/`permission_handler` hívást).
- **§5.3 — titok/token/nyers frame nem kerül logba, jelzésfájlba, hibaüzenetbe, commitba.**
  - `PoseLandmarks.toString()` (`pose_landmarks.dart:163-165`) **csak számokat** ad: `timestampUs`, enum-név, `count`. Koordináta nincs benne — mérve a próba-kimeneten: `PoseLandmarks(timestampUs: 1000, observability: observed, count: 2)`.
  - Az `AppFailure`-szövegek (`native_pose_landmark_provider.dart:61,71-73,82-83`) csak manifest-metaadatot interpolálnak (`modelId`, `version`, `outputSchema`) — nincs bennük koordináta, felhasználói adat vagy titok.
  - `tool/ci/check_secrets.dart` futtatva ebben a klónban: `Secret scan OK (1930 file(s) scanned, 0 finding(s))`.
  - A diff hozzáadott sorain a secret-alakú minta (`api_key|secret|token|password|PRIVATE KEY|Bearer|sk-…|ghp_|AKIA…`) egyetlen találata a brief §10.3 gate-kimenetének `→ [6] secrets: ZÖLD` sora.
- **§5.4 — cloud/community funkció nem ronthatja az offline alapélményt.** N/A: tisztán on-device domain + data réteg, felhő-út nincs.
- **§5.5 — gyenge confidence nem jelenhet meg biztos állításként.** Lásd MINOR-2 (látens; R14-ben nincs fogyasztó, az interpretációs réteg az E05-R20).
- **Prompt-injection / fejlesztőrendszer-határ (AGENTS.md §5.1).** N/A és mérve: a diff hozzáadott sorain az utasítás-alakú minta (`ignore (all|the|previous|prior)|disregard|you are|system:|assistant:|new instruction|override|jailbreak|do not follow|as an ai`) egyetlen találata a Dart `@override` annotáció (fals pozitív). A fixture-ök string-literáljai kizárólag landmark-nevek (`left_shoulder`…`mouth_right`) és a `pose_landmarker` modell-id — nincs szabad szöveg, nincs AI-Tutor felé menő útvonal, a kör kimenete numerikus/enum.

---

## Findings

### MAJOR-1 — a privacy-őr név-heurisztikás: egy alszó-kerülő arc-landmark átjut, és a teljes suite zöld marad

- **Fájl:** `test/features/vision/data/pose_privacy_audit_test.dart:46-53` (`_forbiddenSubstrings`), `:73-88` (az allow-listát ellenőrző cella); a védett felület `lib/features/vision/domain/landmarks/pose_landmarks.dart:40-51`.
- **Sértett szabály:** kör-brief §5 pont 1–2 és §9 („a privacy-audit teszt az egyetlen gépi őr"), ADR 0186 Döntés 1, ADR 0178 Döntés 1. A **mai kód nem sérti** — a gépi őr fedezete sérül.
- **Gyökérok.** Az allow-lista bővítése ellen két, egymást nem fedő állítás véd:
  1. `poseLandmarkIdByRawName.values.toSet() == PoseLandmarkId.values.toSet()` — ez **halmaz**-egyenlőség, ezért egy MEGLÉVŐ ID-ra mutató ÚJ alias nem rontja el (a value-halmaz továbbra is a 9 elem);
  2. a nyers kulcsnév ellenőrzése hat fix alszóra: `eye`, `nose`, `mouth`, `ear`, `face`, `lip`.
  Így az egyetlen tényleges őr a (2) név-heurisztika. A MediaPipe BlazePose 11 arc-pontját ez lefedi — de nem a topológiát, hanem a *névadási konvenciót* őrzi.
- **Failure scenario (konkrét bemenet → konkrét rossz kimenet).** Egy jövőbeli aktiváló kör olyan stacket köt be, amely `chin` (vagy `head_top`, `jaw`, `forehead`, `brow`, `cheek`, `iris`, `pupil` — egyik sem tartalmazza a hat alszót) néven ad fej-pontot, és „nyak-proxyként" felveszi az allow-listára. Ekkor az arc-pont koordinátája a **szentesített `neckReference` néven** kerül a domain-objektumba és az audit-felszínre, miközben minden gépi őr zöld.
- **Mérve (saját kezű reprodukció, 2 lépés).**

  **(a) A védett mutáció — a kért valódi-sértés próba.** `'nose': PoseLandmarkId.neckReference` felvéve a `poseLandmarkIdByRawName` allow-listára, majd:
  ```
  $ flutter test test/features/vision/data/pose_privacy_audit_test.dart
  00:00 +1 -1: the raw-name allow-list maps onto retained IDs only [E]
    Expected: false
      Actual: <true>
    allow-listed raw name "nose" looks like a face point
    test/features/vision/data/pose_privacy_audit_test.dart 81:9
  00:00 +3 -2: a face-only payload yields notObservable, not a zero-filled body [E]
    Expected: PoseObservability:<PoseObservability.notObservable>
      Actual: PoseObservability:<PoseObservability.observed>
    test/features/vision/data/pose_privacy_audit_test.dart 151:7
  00:00 +3 -2: Some tests failed.
  ```
  **PIROS, két független cellán** — a brief §10.4 állítása független reprodukcióval megerősítve (baseline előtte: `+5 All tests passed!`). Visszaállítás: `git checkout lib/features/vision/domain/landmarks/pose_landmarks.dart`.

  Figyelemre méltó: a `face landmarks … never reach … its serialized form, or its log form` cella **ZÖLD maradt** még ebben az esetben is — mert az orr-koordináta az audit-mapben `neckReference` kulcs alatt jelenik meg, és az alszó-keresés a szerializált szövegen nem talál `nose`-t. Ez a cella tehát nevet ellenőriz, nem provenanciát.

  **(b) A kerülő mutáció — a tényleges rés.** `'chin': PoseLandmarkId.neckReference` felvéve ugyanoda (a `chin` valódi arc-landmark, de a hat alszó egyikét sem tartalmazza):
  ```
  $ flutter test test/features/vision/
  00:20 +155: All tests passed!
  ```
  **A TELJES vision-suite zöld** — a mapping-teszt, a privacy-audit mind az 5 cellája, a baseline-mátrix és a manifest-tesztek is. A `chin` pont ilyenkor ténylegesen kiszivárog; eldobható próba-teszttel kimérve:
  ```
  PROBE presentIds = [PoseLandmarkId.leftShoulder, PoseLandmarkId.neckReference]
  PROBE auditMap   = {"timestamp_us":1000,"observability":"observed","landmarks":{
                      "leftShoulder":{"x":0.4,"y":0.3,"z":0.01,"visibility":0.9},
                      "neckReference":{"x":0.777,"y":0.888,"z":0.999,"visibility":0.95}}}
  ```
  — ahol `0.777/0.888/0.999` a `chin` nyers koordinátája. Mindkét mutáció és a próba-fájlok visszaállítva/törölve; a fa tiszta (`git status --short` üres).
- **Miért MAJOR és nem BLOCKER:** a **szállított** allow-lista (`pose_landmarks.dart:42-50`) pontosan a 9 engedélyezett bejegyzést tartalmazza, a `neck` nem arc-pont, és a `PoseLandmarkId` enum tartalmát a `:66-71` cella karakterre pinneli — mai határsértés tehát **nincs**. A kockázat az, hogy a kör a saját privacy-ígéretének gépi őrét gyengébbnek szállítja, mint amilyennek a brief §9 és az ADR 0186 Döntés 1 hiszi, és ez pont a jövőbeli aktiváló körben (valódi modell, valódi nevek) fog számítani.
- **Javasolt javítási irány (nem írtam kódot):** az őr legyen **pozitív, zárt lista**, ne negatív alszó-szűrő — pl. a teszt pinnelje a `poseLandmarkIdByRawName` **teljes kulcshalmazát** egy explicit snapshotra (`{'left_shoulder', …, 'neck'}`), így BÁRMELY új nyers alias — nevétől függetlenül — pirosra vált, és csak a snapshot tudatos frissítésével kerülhet be. Másodlagosan érdemes a `.values` halmaz-egyenlőség mellé egy `poseLandmarkIdByRawName.length == PoseLandmarkId.values.length` állítást tenni (1:1 leképezés kikényszerítése, alias tiltása).

### MINOR-2 — a `PostureObservation` állapota mindig `good`, ha egyetlen pont is közös

- **Fájl:** `lib/features/vision/domain/landmarks/posture_baseline.dart:199-204` (`state: VisionMetricState.good` feltétel nélkül), a hármas enum `vision_frame_quality.dart:5`.
- **Failure scenario:** a baseline 9 pontból épült, de az aktuális frame-ben egyetlen váll látszik épp a `minimumLandmarkVisibility` küszöbön, és az is messze a baseline-tól. A megfigyelés `state = good`-ot ad — egy fogyasztó (E05-R20) számára ez „megbízható testtartás-megfigyelés", holott egyetlen, gyenge pontból származik. A `VisionMetricState.needsImprovement` értéket ez az osztály **soha nem** állítja elő.
- **Mérve (pure-Dart harness):**
  ```
  B: baseline exists = true
  B: state=VisionMetricState.good comparedLandmarkCount=1 maxDrift=4.257
  ```
  (`maxDrift = 4.257` = a vállszélesség 4,2-szerese — extrém elmozdulás, mégis `good`.)
- **Sértett szabály:** SDD §5.5 / AGENTS.md §5 pont 5 (gyenge confidence ≠ biztos állítás), ADR 0179 szelleme.
- **Miért MINOR:** R14-ben nincs fogyasztója a `PostureObservation`-nek (`grep` szerint csak a saját tesztje) — látens mag, pontosan az E05-R13 MINOR-1 (`visibility = MAX`) mintázata. A `comparedLandmarkCount` publikus, tehát a fogyasztó ma is tudna szigorítani.
- **Javasolt irány:** vagy `needsImprovement` a küszöb alatti `comparedLandmarkCount`/visibility esetén, vagy a `state` mező elhagyása a nyers modellből (az ítélet úgyis R20 dolga — ADR 0186 Döntés 5), hogy a réteg ne tegyen konfidencia-állítást.

### NOTE-3 — duplikált allow-listás nyers név esetén az utolsó nyer, csendben

`pose_landmarks.dart:199-213`: a ciklus `landmarks[id] = …` értékadással dolgozik, tehát ha a nyers payload két, ugyanarra az ID-ra képződő nevet tartalmaz (ma pl. csak `neck`; MAJOR-1 javítása után is releváns marad, ha alias-ok engedélyezettek), az utolsó felülírja az elsőt — jelzés nélkül. Ma nem kihasználható (a 9 kulcs 1:1), de a MAJOR-1 javasolt 1:1 kikényszerítése ezt is lezárja.

### NOTE-4 — a manifest `path` path-traversal védelme továbbra sincs (átvett, nem rontott)

`lib/core/ml/vision_model_manifest.dart:257-271` — az `active` ág `File('${projectRoot.absolute.path}/$path')`-ot olvas `path`-normalizálás nélkül. Ez **nem ennek a körnek a leletje**: az R12 security review már MINOR-1-ként dokumentálta, és a diff ezt a blokkot nem érinti. A kör mérlege itt inkább **javító**: az új `visionModelOutputSchemas` registry (`:222-229`) egy regisztrálatlan `model_id`-t **a `File()` ág ELŐTT** utasít el (`issues.add` + `continue`), tehát egy idegen modellcsalád ma már el sem jut a fájlolvasásig. Mindkét szállított bejegyzés `status = "deferred"`, így a `File()` ág ma nem fut.

### NOTE-5 — `PostureBaselineConfig` validációja assert-alapú (release-ben strippelt) — próbálva, kihasználhatóság nem igazolt

`posture_baseline.dart:34-36`. A repo mért igazsága szerint az `assert` a release APK-ban strippelt, ezért futtattam a `dart --enable-asserts` / `--no-enable-asserts` párost egy degenerált konfigurációval (`minimumSampleCount: 0`, `minimumQualityScore: -5.0`, `minimumLandmarkVisibility: -1.0`, `minimumVisibleDuration: Duration.zero`) és a lehető legrosszabb mintával:
```
=== DEBUG (asserts ON) ===   asserts enabled = true
A: rejected -> _AssertionError
=== RELEASE (asserts OFF) === asserts enabled = false
A: baseline built from garbage? false (sampleCount=null, durationUs=null)
```
Release alatt az assert valóban eltűnik, **de a baseline így sem épült fel** — a `_accepts` numerikus quality-kapuja (`:213`) továbbra is elutasított. A §5.5 „részleges ablakból nincs baseline" határ tehát release-ben is tartott a próbámban. NOTE-ként rögzítem (a `PoseLandmarkPoint`/`PoseLandmarks` ezzel szemben helyesen valódi `ArgumentError`-t dob, `pose_landmarks.dart:66-71,109-115` — release-safe).

---

## Ellenőrzött és PASS-elt pontok (evidenciával)

1. **Adatminimalizálás valódi-sértés próbával — PASS** (a fedezet hiányossága külön: MAJOR-1). Baseline `+5 All tests passed!`; `'nose'` injektálva → `+3 -2`, két független cella piros; visszaállítva, fa tiszta.
2. **A szűrés a mappingben történik, nem a fogyasztóban — PASS.** `mapRawPoseLandmarks` (`pose_landmarks.dart:195-222`) az egyetlen út a `PoseLandmarks`-hoz a data rétegből; a nem allow-listás név a `continue`-n (`:202`) esik ki, **mielőtt** `PoseLandmarkPoint` példányosulna. Csak arc-pontokat tartalmazó payload → `notObservable`, nulla ponttal (`:214-216`) — nincs nullákkal töltött álkimenet; mérve a `fixtureFaceOnly` cellán.
3. **`toAuditMap()` / `toString()` logolási felszíne — PASS, a kérdés lezárva.** A `toAuditMap()` valóban tartalmaz koordinátát a MEGTARTOTT pontokra, de **nincs semmilyen hívási lánca logba, hálózatra vagy tárba**: a repo egészén (`grep -rn "toAuditMap" --include=*.dart .`) pontosan három találat van — a definíció (`pose_landmarks.dart:147`) és két teszt-hívás (`pose_privacy_audit_test.dart:96,123`). **Nulla production hívó.** Ez tehát in-memory teszt-audit-felszín, ahogy a feladat leírta — nem BLOCKER. A `toString()` (a tényleges log-alak) koordinátát nem tartalmaz.
4. **A manifest-validátor általánosítása nem gyengítette a `hand_landmarker` utat — PASS, byte-szinten igazolva.** A `git diff` a validátoron két hunk: egy additív konstans/registry blokk (`:30-45`) és az egysoros séma-ellenőrzés registry-lookupra cserélése (`:222-236`). A checksum-formátum (`:240-245`), az `active`-ági asset+checksum ág (`:257-271`) és a licenc-validátorok (`:307-338`) **érintetlenek**. A `hand_landmarker` elvárt sémája bitre ugyanaz (`visionModelOutputSchemas['hand_landmarker'] == handLandmarksOutputSchema`). A hat meglévő hand-mutáció-cella szövege **byte-azonos**: a `main` 169–310. és a `HEAD` 194–335. sorainak md5-je egyaránt `1382f80860ba2e17c1510f694e9e1517`. Az általánosítás **fail-closed**: regisztrálatlan `model_id` → `issues.add` + `continue` (az entry nem kerül a `entries` listába, a report nem `isClean`) — új `unregistered model_id → init failure` cella fedi.
5. **`NativePoseLandmarkProvider` fail-closed — PASS, a legmegengedőbb ágon is.** A `deferred` bejegyzés `initialize`-t buktatja (`:76-86`), így `_entry` `null` marad és `infer` `mlModelLoad`-dal bukik (`:93-97`). Mivel a szállított manifest `deferred`, ez a valós út. Külön kiprobáltam a **nem tesztelt** ágat is (`status = active` + helyes séma → `initialize` sikeres):
   ```
   PROBE initialize.isSuccess = true
   PROBE infer.isSuccess      = false
   PROBE infer.valueOrNull    = null
   ```
   `infer` **feltétel nélkül** `mlInference`-szel bukik (`:100-102`) — nincs olyan út, ahol sikeres, hamis vagy nullákkal töltött pózt adna. A séma-ellenőrzés (`:65-75`) a `deferred`-ág ELŐTT fut, tehát hand-sémájú bejegyzés pose-providerként az aktiváló körben sem tölthető be.
6. **Nincs secret/kulcs/PII a diffben — PASS.** `tool/ci/check_secrets.dart` → `Secret scan OK (1930 file(s) scanned, 0 finding(s))`. A `sha256` placeholder szemantikailag is valóban fake: 64 nulla (`model_manifest.json` pose-bejegyzés), és **fail-closed**, ha valaki `active`-ra váltana anélkül, hogy valódi checksumot generálna — valós fájl bájtjai sosem hashelnek csupa nullára, tehát a `:264-270` checksum-ág elutasítana. A licenc/provenance mező kitöltve (`Apache-2.0` / `MediaPipe Pose`) + `evaluation_report` útvonal, az AGENTS.md §9 asset-provenance elvárása szerint.
7. **Nincs új dependency, nincs új asset-bináris — PASS.** A `pubspec.yaml` nem változott; a pose-modell binárisa nem kerül a repóba (`deferred`), ezért ellátásilánc-felület sem nyílt. A `ml/make_manifest.py` bővítése tisztán adat (egy dict-literál), nincs benne új import, hálózat vagy futtatás.
8. **A generátor a shipped JSON egyetlen forrása — PASS.** A `model_manifest.json` diff kizárólag a 19 soros pose-bejegyzés; a `hand_landmarker` bejegyzés és a 4 audio modell változatlan, tehát nincs kézi JSON-szerkesztés, ami a generátort megkerülné.
9. **Kikapcsolás-kapu — PASS.** `createPoseLandmarkProvider` (`pose_landmark_provider.dart:159-169`) a `build()` closure-t **a flag-ellenőrzés után** hívja, tehát kikapcsolt pose mellett a delegált provider fel sem épül (nem csak eldobásra kerül) — a `built` számláló 0-t mérő cella ezt gate-eli.
10. **Determinizmus — PASS.** `DateTime.now` / `Random` / `Stopwatch` az 5 új production fájlban nem szerepel; az idő kizárólag injektált `timestampUs`.

---

## Merge-döntés

**PASS a biztonsági lencsén át — 0 CRITICAL, 0 BLOCKER.** Nincs bizonyított
titok-szivárgás, consent-megkerülés, path traversal vagy termékhatár-sértés; a
kör privacy-ígérete a szállított kódon **teljesül**, és ezt saját kezű
reprodukcióval igazoltam.

A **MAJOR-1** a kör saját §11 mércéje szerint („nulla OPEN BLOCKER/MAJOR")
merge előtt lezárandó. A javítás kicsi és teszt-oldali (a negatív alszó-szűrő
helyett a `poseLandmarkIdByRawName` kulcshalmazának pozitív pinnelése + 1:1
hosszellenőrzés a `pose_privacy_audit_test.dart`-ban) — production kódot nem
igényel, és a NOTE-3-at is lezárja.

**Státusz-frissítés (orchestrátor, javító kör 2 után):** MAJOR-1 **FIXED**
(`56146c2`, Codex/Terra — motor-eszkaláció, mert a MiniMax M3 egy javító
kört már elhasznált a formázási F1-re). A javítás pontosan a javasolt
irányt követi: `poseLandmarkIdByRawName.keys.toSet()` pinnelve egy explicit,
pontos 9-elemű snapshotra + `.length == PoseLandmarkId.values.length`
1:1-kikényszerítés — a meglévő alszó-szűrés megmaradt kiegészítő védelemként.
Az orchestrátor SAJÁT, HARMADIK, független `/tmp` klónban (`/tmp/review-e05-r14-fix2`)
megismételte a `'chin': PoseLandmarkId.neckReference` kerülő mutációt: a
teljes `test/features/vision/` suite-ból pontosan 1 teszt bukik (`the
raw-name allow-list maps onto retained IDs only`), a másik 154 zöld — a
korábban észrevétlen kerülés most helyesen elakad. MINOR-2 NEM lett
javítva ebben a körben (Codex tudatosan kihagyta, mert a brief ezt
explicit engedte, ha bizonytalan a diff mérete) — E05-R20 follow-up-ként
dokumentálva a round-brief §10.5-ében, nem blokkolja a merge-öt.
