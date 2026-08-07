# E05-R12 — Dedicated Security / Privacy / Prompt-Injection Review

**Round:** E05-R12 — Hand landmark provider adapter és model manifest
**Merge commit:** `f39d7b6` (squash) · diff base `a6e6f3d`
**Trigger:** `risk = "high"` a brief `ai-router` blokkjában → dedikált security review kötelező.
**Futtatva:** POST-MERGE (az orchestrátor mulasztása — a review-t a merge ELŐTT
kellett volna lefuttatni, minden korábbi E05 kör precedense szerint; pótolva
azonnal, miután a mulasztás kiderült).
**Kör:** READ-ONLY. Nincs production-kód módosítás.
**Reviewer:** `security-reviewer` subagent (Claude Sonnet 5 alatt), 2026-08-07.

## Verdikt

**Safe to remain merged. Nincs revert, nincs BLOCKER, nincs CRITICAL, nincs MAJOR.**

A kör tartalmilag egy valóban fail-closed, privacy-tiszta infrastruktúra-
kontraktus. Nem ad hozzá hálózati, permission-, consent-, analytics-,
diagnosztika- vagy storage-felületet, és a teljes hand-landmark stack ma
DORMANT (nulla külső hívó). Egy MINOR, ma nem elérhető hardening-rés +
három NOTE — mind follow-up, egyik sem blokkoló.

| Severity | Count |
|---|---|
| CRITICAL | 0 |
| BLOCKER | 0 |
| MAJOR | 0 |
| MINOR | 1 |
| NOTE | 3 |

## Megállapítások

### MINOR-1 — a vision-manifest `path` mezőjének nincs path-traversal védelme (dormant; az audio-oldali testvér validátornak van)

- **Fájl:sor:** `lib/core/ml/vision_model_manifest.dart:233` (a fájlolvasás),
  a `path` forrása `_requiredString` hívással a `:159` sorban.
- **Hiba-forgatókönyv:** egy `status:"active"` bejegyzésnél a validátor
  `File('${projectRoot.absolute.path}/$path').readAsBytesSync()`-et hív,
  ahol a `path`-ot csak nem-üres string-ként validáljuk. Egy
  `path: "../../../etc/passwd"` értékű bejegyzés a validátort a
  `assets/ml/`-en KÍVÜLI, tetszőleges fájl megnyitására és SHA-256-olására
  veszi rá. **Reprodukálva** egy dedikált `dart:io` harnessel: a 233. sor
  pontos kifejezése a fake project root-on kívülről sikeresen beolvasott egy
  `OUT_OF_TREE_SECRET` tartalmú fájlt.
- **Sértett szabály:** a checklist „importált tartalom — path traversal"
  pontja; az audio-oldali testvér-validátor MÁR véd
  (`_modelPathPattern = ^assets/ml/[A-Za-z0-9][...]\.bin$` +
  `path.split('/').contains('..')` elutasítás,
  `test/tooling/ml_asset_manifest_test.dart:396,569`) — a vision-oldali
  validátor ezt a két védelmet NEM örökölte.
- **Miért MINOR, nem magasabb (gyakorlati kockázat-elemzés):**
  1. **Nem elérhető a szállított artefaktumon.** A `File()`-olvasás
     `status == "active"`-ra van kapuzva; az egyetlen szállított bejegyzés
     `status:"deferred"`, ennek ága sosem ér fájlrendszerhez (`:232`).
  2. **Nem futásidejű-felhasználó által vezérelt.** A manifest repo/CI
     build-artefaktum; nincs is `pubspec.yaml` assetként bundle-ölve, és a
     `FileVisionModelManifestReader` `Directory.current`-alapú — Androidon
     ez NEM az asset-bundle-t éri el, tehát on-device egyáltalán nincs
     elérési út.
  3. **Korlátozott hatás:** csak fájl-OLVASÁS + hash; a tartalom nem
     szivárog ki (csak egy SHA-256 jelenik meg egy issue-stringben eltérés
     esetén); nincs kódfuttatás.
- **Eszkalációs feltétel:** MAJOR-rá válik abban a pillanatban, amikor egy
  jövőbeli aktiváló kör valódi `active` vision-bejegyzést ad hozzá (ami TÉNYLEG
  végrehajtja a `File($root/$path)` olvasást) a védelem hozzáadása NÉLKÜL.
- **Javasolt irány:** a `File()` hívás ELŐTT a `path`-ot safe-path
  allowlisttel kell validálni, az audio-oldali testvért tükrözve (kikötött
  `^assets/ml/...` regex, vezető `/` és bármilyen `..` szegmens elutasítása),
  fail-closed `issues.add(...)`-dal. **Az aktiváló kör előfeltétele** — az a
  kör NE merge-eljen a védelem nélkül.

### NOTE-1 — `timestampUs` `assert`-tel védett, ahol a testvér domain-típusok `ArgumentError`-t használnak (release-ben stripped)

`lib/features/vision/domain/landmarks/hand_landmarks.dart:145`
(`HandLandmarkResult`) és
`lib/features/vision/data/landmarks/hand_landmark_provider.dart:82`
(`HandLandmarkTimestamp`) `assert(... >= 0)`-t használ, ami release APK-ban
STRIPPELŐDIK — míg a testvér értéktípusok (`VisionImage`, `HandLandmarkPoint`,
`HandObservation`) release-biztos `ArgumentError`-t dobnak. Nem elérhető
NEM-bizalmas bemenetből ebben a körben (az egyetlen builder, a Recorded
fixture, a `VisionImage`-ből származtatja a timestampet, ami MÁR
release-biztos). Az aktiváló kör dolga összhangba hozni.

### NOTE-2 — `FileVisionModelManifestReader` on-device NEM funkcionális — de fail-SAFE

`Directory.current`-alapú olvasás Androidon nem az asset-bundle-t éri el, és
a manifest nincs is pubspec-bundle-ölve — on-device ez MINDIG
`vision manifest is missing`-et ad, ami a `NativeHandLandmarkProvider`-t
fail-closed-ra viszi. Biztonsági szempontból ez POZITÍV (fail-safe), csak
egy latens korrektségi csapda: az aktiváló kör `rootBundle`-alapú readerre
kell váltson (lásd `lib/features/analyze/providers/analyze_providers.dart:85,96`
mintáját), EGYÜTT a MINOR-1 védelemmel.

### NOTE-3 — `initialize()` nem védi a `manifestReader.read()`-et olvasási race ellen

`lib/features/vision/data/landmarks/native_hand_landmark_provider.dart:57` —
egy TOCTOU race (fájl törölve `existsSync` és `readAsStringSync` között) egy
elutasított `Future`-ként szivárogna ki, nem `AppResult.failure`-ként.
Fail-closed-to-throw (nem fail-open, nem capability-szivárgás), tehát
robusztussági NOTE, nem biztonsági lelet.

## Amit ellenőrzött (a hat StrumSight-specifikus szempont)

1. **Raw frame / kamerakép perzisztencia (ADR 0178/0183) — TISZTA.**
   `VisionImage.bytes` defenzív másolat; nincs `print`/`debugPrint`/logger/
   `IOSink` a diffben; egyik hibaútnak sincs `cause`-a képadattal; nulla
   külső hívó az egész `HandLandmarkProvider.infer`-re.
2. **Secret/kulcs szivárgás — TISZTA.** Nincs URL/kulcs/token minta; a
   manifest `sha256` egy dokumentált `"0"*64` placeholder, nem redaktált
   valódi hash; `pubspec.yaml`/`.lock` érintetlen (`crypto` már meglévő
   közvetlen függőség).
3. **`deferred` fail-closed integritás — ERŐSEN IGAZOLVA.** Minden
   `NativeHandLandmarkProvider` útvonal végigkövetve — nincs hamis-pozitív
   capability-állítás, nincs silent no-op.
4. **Model-asset integritás, nincs checksum/schema bypass — IGAZOLVA.** Az
   `output_schema` és `sha256`-formátum ellenőrzés MINDEN bejegyzésre lefut a
   status-elágazás ELŐTT; a fájlrendszeres checksum-egyezés feltétel nélkül
   fut `active`-ra.
5. **Prompt-injection / adatszennyezés — NEM RELEVÁNS ebben a körben.** Nincs
   LLM/AI-tutor kód a diffben; a `lib/features/ai_tutor/` nem hivatkozik
   landmark-típusokra.
6. **Hálózat/permission/consent — TISZTA.** Nincs `dio`/`http`/socket/
   `Permission`/consent/analytics/diagnosztika felület a diffben.

## Javaslat az orchestrátornak

Nincs revert, a merge marad. Egy MINOR follow-up nyitva: a safe-path guard
hozzáadása a `validateVisionManifest`-hez (az audio-oldali testvért
tükrözve) **a jövőbeli aktiváló kör előfeltétele** — az a kör ne merge-eljen
a védelem nélkül, különben a lelet MAJOR-ra eszkalálódik. A NOTE-1/NOTE-2
ugyanabba az aktiváló körbe olvasztandó (assert→`ArgumentError`
összhangba hozás; `rootBundle` reader).
