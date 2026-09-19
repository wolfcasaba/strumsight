# ADR 0542 — Opt-in béta telemetria, egyetlen feltöltési kapu és a felismerési kiadási létra: a zászló SOHA nem önmagában enged, és ami nincs mérve, az `off` marad

- **Státusz:** Elfogadva
- **Kör:** `E14-R41` (Chapter 14 — Recognition Accuracy & Useful UI Recovery,
  Kör 41), a `E14-R23` / `E14-R24` / `E14-R33` / `E14-R40` körök
  **zászló-felét** is ez a döntés szállítja (PKG-D 1. hullámos
  kötelezettsége: a teljes E14 zászlókészlet EGYBEN landol)
- **Dátum:** 2026-09-09
- **Implementer motor:** Claude (Opus 5), PKG-D csomag-ügynök
- **Kapcsolódó:**
  [ADR 0484](0484-privacy-safe-telemetry-contract-and-release-slo-schema.md)
  (a privacy-biztos telemetria-szerződés: D1 strukturális tiltás, D2 egyetlen
  redaktor, D4 consent-kapuzott sink, D5 se hálózat, se lokális perzisztencia
  — ez a kör ERRE épül),
  [ADR 0446](0446-feature-flag-registry-and-emergency-kill-switch.md)
  (a zászló-katalógus és a gépi teljesség-audit: D4 a forrás `final bool`
  mezőit parse-olja),
  [ADR 0271](0271-recognition-recovery-program.md) (a felismerési
  helyreállítási program és a három, addig fogyasztó nélküli zászló),
  [ADR 0479](0479-privacy-data-inventory-and-consent-enforcement.md)
  (a visszavonás AZONNAL hat — D2/D3),
  [ADR 0358](0358-consented-on-device-lab-capture-package.md) (a Lab-felvétel
  consent-típusa: a típusrendszer, nem egy `if` kényszeríti ki),
  [ADR 0247](0247-analysis-export-share-and-delete-contract.md) (allowlist-redakció,
  ennek a körnek a property-tesztje ezt a mintát tükrözi),
  [ADR 0511](0511-recognition-release-gate-and-single-source-report.md)
  (a fail-closed felismerési release-kapu, amihez a létra fokai kötődnek)

## Kontextus — a MÉRT állapot (2026-09-09, `claude/laptop-apk-debug-prompt-kys4oa`)

### 1. A telemetria-consent kapcsoló nem létezett

`lib/core/telemetry/telemetry_sink.dart` saját doc-kommentje mondta ki:
*„no telemetry-consent switch exists on the tree today"*. A
`ConsentGatedTelemetrySink` `consentGranted` mezője egy konstruktorba injektált
`bool Function()` volt, aminek a fán **egyetlen valódi forrása sem** volt.
Transport szintén nincs, és az ADR 0484 D5 tiltása (`test/core/telemetry/
telemetry_redaction_test.dart` A7) meg is akadályozza, hogy legyen.

### 2. A felismerési zászlóknak nulla fogyasztójuk van

`recognitionRecoveryEnabled`, `recognitionShadowModeEnabled`,
`newLiveStageEnabled` — a `grep` a `lib/**`-ben csak a definíciót és a
teszteket találja. A shadow-plumbing nincs megírva; a 2. hullám (PKG-E/PKG-F)
írja meg.

### 3. Egyetlen Ch14 §7 küszöb sem zöld

`evaluation/recognition/baseline_manifest.json` mérve: onset F1@50 ms
**0,674** (kapu 0,82), chord accuracy **0,671** (kapu 0,80), a `direction`,
`noChord`, `latency` és `calibration` blokk státusza **`not-measured`**.
Ebből következik a D1 alapdöntése.

### 4. A zászló-audit `final bool` mezőket parse-ol

`tool/check_feature_flags.dart` `_fieldPattern` = `^\s*final bool\??\s+(\w+)`.
Egy katalógus-bejegyzés, aminek nincs ilyen nevű `final bool` mezője,
`unknownCatalogEntry` hibát ad — vagyis egy enum-mezőt **tilos** a registrybe
tenni.

### 5. A telemetria-könyvtár tiltja a `String` MEZŐT

Ugyanaz az A1 cella minden `lib/core/telemetry/**` fájlra kimondja: nincs
`dynamic`, nincs csupasz `Object`, **nincs csupasz `String` mező**. Ez nem
akadály volt, hanem a tervezés bemenete (lásd D3).

## Döntések

### D1 — Minden felismerési kapu `off` MINDEN környezetben, a nem-production is

A `FeatureFlags.forEnvironment` a `recognitionShadowModeEnabled`,
`recognitionChordShadowModeEnabled`, `recognitionPreprocessingEnabled`,
`recognitionFieldSessionTaggingEnabled`, `strumModelRolloutStage` és
`chordModelRolloutStage` értékét **minden** környezetben `off`/`false`-ra
oldja fel — nem `nonProd`-ra, ahogy a `practiceEngineV2Enabled` vagy az
`adaptiveShellEnabled` teszi.

**Indok:** a `nonProd` alapértelmezés azt állítaná, hogy a sáv fejlesztői
build-ben „elég jó a bekapcsoláshoz". A §1/3. pont mérése szerint egyetlen
Ch14 §7 küszöb sem teljesül. Egy dev build, ami magától shadow-t futtat,
mérés nélkül vesz fel rollout-fokozatot.

**NEM elfogadható gyengítés:** „legyen `nonProd`, hiszen úgyis csak Lab".
A Lab APK valódi eszközön, valódi felhasználó előtt fut.

### D2 — A shadow-futás feltétele aszimmetrikus ÉS: fokozat ÉS mesterkapcsoló

Egy shadow-inferencia akkor és csak akkor futhat, ha
`stage.runsInference == true` **és** a hozzá tartozó boolean mesterkapcsoló is
igaz (`recognitionShadowModeEnabled` a strum, `recognitionChordShadowModeEnabled`
a chord sávra).

**Indok:** két külön kérdés két külön kapcsolót érdemel. A fokozat egy
**reviewelt kiadási lépés** (dokumentumban rögzített emberi döntés); a boolean
egy **incidens-kapcsoló**, amit egy ügyeletesnek egyetlen `false`-szal kell
tudnia elsütnie anélkül, hogy a létráról kellene gondolkodnia. Az ÉS
aszimmetrikus: bármelyik fél önmagában KIkapcsol, egyik sem kapcsol BE.

Ez ugyanaz a minta, mint az ADR 0395 Community mesterkapcsolója és az ADR 0446
D1 aszimmetrikus vészkapcsolója.

### D3 — A consent HÁROM állapotú zárt enum, a copy-verzió is enum, az azonosító pedig BIT

- `TelemetryConsentState { notAsked, granted, denied }` — egy `bool` nem tudja
  megkülönböztetni a „még nem kérdeztük"-et a „nemet mondott"-tól, pedig ez
  dönti el, szabad-e újra kérdezni. A kapunál mindkét nem-`granted` érték
  elutasítás.
- `TelemetryConsentVersion` — a hozzájárulás KONKRÉT szövegre szól. Ha a
  szöveg változik, a régi érték bent marad az enumban, a `current` továbblép,
  és a meglévő grant **megszűnik** feljogosítani. Egy `String version` mező
  ezt nem tudná géppel kikényszeríteni — és a §1/5. mérés szerint egy csupasz
  `String` mező itt amúgy is tilos.
- `TelemetryPseudonymId` 64 véletlen BITET tárol két `int`-ben, a hex alak
  **getter**. Így a típuson nincs az a szöveges rekesz, amibe egy e-mail vagy
  egy eszköz-sorozatszám valaha bekerülhetne.

### D4 — Az enum-mezők SZÁNDÉKOSAN nincsenek a zászló-registryben

`strumModelRolloutStage` és `chordModelRolloutStage` nem kap
`FeatureFlagDefinition` bejegyzést, mert a registry és a gépi auditja (ADR
0446 D4) `final bool` mezők fölött van definiálva; egy bool-alakú bejegyzés
egy enum-mezőre **mindkét irányban** hamissá tenné az audit teljesség-
állítását. A fokozatok reviewelt nyilvántartása a
`docs/release/ch14-recognition-rollout.md`, és a
`test/app/config/feature_flags_test.dart` cellája **pinneli**, hogy a két
kulcs nincs a registryben — ez a döntés, nem feledékenység.

A négy új **bool** zászló (`recognitionChordShadowModeEnabled`,
`recognitionPreprocessingEnabled`, `recognitionFieldSessionTaggingEnabled`,
`betaTelemetryEnabled`) viszont kap bejegyzést, tulajdonossal és
kill-switch-úttal.

### D5 — A felismerési esemény AGGREGÁTUM, minden mezője zárt enum vagy vödör

`RecognitionTelemetryEvent`: sáv, modell, minőség-vödör, elfogadott/elutasított
**darabszám-vödör**, verdict-latency vödör, javítás-flag. A terv kérése
(„model version") **zárt enumként** teljesül (`RecognitionTelemetryModel`, az
`assets/ml/model_manifest.json` négy binárisa + az NNLS DSP út), nem
szabad szövegként — pontosan azon az indokon, amit a `TelemetryCapability`
saját doc-kommentje kimond.

A darabszám is vödör, nem nyers szám: az ADR 0484 indoklása a nyers
időtartamra (*„egy nyers érték de-facto szabad csatorna"*) szó szerint áll a
darabszámra is, és a béta-riport minden mutatója amúgy is arány.

**A kódoló ALLOWLIST, két irányban:** az esemény mezői kulcsonként íródnak
(nincs reflexió, nincs `toJson` egy nyílt modellen), a hívó által átadott
diagnosztikai kontextusból pedig csak a néven nevezett kulcs marad meg — és
ott is csak `bool`, `int`, vagy **enum-név alakú** string. Egy engedélyezett
KULCS nem engedélyezett TARTALOM: egy fájlnév vagy egy sorozatszám a
`rolloutStage` kulcs alatt is eldobásra kerül.

### D6 — EGY feltöltési kapu, három fail-closed feltétellel

`TelemetryUploadGate.allowsUpload == betaTelemetryEnabled &&
diagnosticsEnabled && consent.permitsCollection`.

A `diagnosticsEnabled` bevonása szándékos: a béta telemetria a MEGLÉVŐ
diagnosztikai kapun utazik, nem nyit második, saját szabályú kijáratot — és
mivel production build ezt `false`-ra oldja fel, a production akkor is néma
marad, ha valahogy mégis lenne consent-rekord.

**Amit ez a kapu NEM:** ez nem a küldő. Ez a kör **nem szállít transportot**
(az ADR 0484 D5 tiltása változatlan). A kapu azért landol most, hogy egy
jövőbeli transport ne tudjon mellette bekötődni.

### D7 — A field-session tag zárt kohorsz + ugyanaz a forgó pszeudonim

`FieldSessionTag.resolve` `null`-t ad, ha a build-zászló ki van kapcsolva,
VAGY a résztvevő nincs beiratkozva, VAGY nincs élő pszeudonim. Tag nélküli
felvétel érvényes felvétel; félkész taggel ellátott felvétel **kitalált
kutatási rekord** volna.

A tanulmányi beiratkozás (`fieldStudyEnrolmentProvider`) KÜLÖN opt-in a
telemetria-consenttől: részt venni egy vizsgálatban más aktus, mint
hozzájárulni az aggregált jelentéshez.

### D8 — A visszavonás TÖRLI az azonosítót, és a UI nem állít küldést

- `revoke()` nemcsak `denied`-et ír, hanem **eltávolítja** a pszeudonim három
  kulcsát a tárolóból. Egy megtartott azonosító pontosan az, amire a
  felhasználó visszavonta az engedélyt.
- A Privacy Center kártyája **nem rendel switchet**, ha a build nem kínálja a
  bétát (a zászló vagy a diagnosztika ki van kapcsolva) — egy kapcsoló, ami
  semmit nem változtat, szebb formájú hazugság.
- A bekapcsolt állapot szövege **nem** azt mondja, hogy adat megy el, és egy
  külön sor kimondja, hogy ebben a build-ben nincs küldési csatorna. Ch14 §9:
  gyenge/hiányzó mechanizmus soha nem jelenhet meg magabiztos állításként.

## Ami MÉRVE VAN és ami NEM

| Állítás | Státusz |
|---|---|
| A kapu három feltétele ÉS-kapcsolatban van, mindegyik fail-closed | **gépi cella** (`test/core/telemetry/telemetry_consent_test.dart`) |
| A visszavonás azonnal hat és nincs visszamenőleges flush | **gépi cella** (ugyanott + `test/privacy/beta_telemetry_egress_test.dart`) |
| A visszavonás törli a pszeudonim kulcsokat | **gépi cella** (`test/features/settings/telemetry_consent_center_test.dart`) |
| A kódolt kulcshalmaz sosem lépi túl a független allowlistet | **randomizált property** (`test/property/telemetry_redaction_property_test.dart`, `PROPERTY_SEED`) |
| Az öt tiltott tartalom-kategória sosem jelenik meg a kimenetben | **randomizált property** (ugyanott) |
| Ma nulla hálózati kérés indul a béta-úton | **gépi cella** `FakeNetworkGuard`-dal — de ez azt bizonyítja, hogy MA nincs küldő, nem azt, hogy egy JÖVŐBELI küldő kapuzott lesz |
| A privacy review és a threat model ALÁÍRÁSA | **NEM MÉRT** — emberi kapu (Ch14 Kör 41, „Nem itt") |
| A béta kohorsz tényleges elindítása | **NEM MÉRT** — emberi kapu |
| Bármelyik Ch14 §7 küszöb teljesülése | **NEM MÉRT / MÉRTEN BUKÓ** — lásd `docs/release/ch14-production-gate.md` |
| A shadow-fokozat futásidejű viselkedése | **NEM MÉRT** — nincs fogyasztó; a 2. hullám (PKG-E) írja |

## Következmények

- A `lib/core/telemetry/**` mostantól hordozza a consent-modellt, az
  aggregátum-eseményt és a kaput; a `public.dart` mind a hármat exportálja.
- A `lib/features/settings/**` hordozza a perzisztenciát, a szolgáltatókat és
  a Privacy Center kártyáját. A tárolókulcsok a feature saját
  `TelemetryStorageKeys` katalógusában vannak (a `GamificationStorageKeys`
  precedense szerint), nem a közös `StorageKeys`-ben.
- A `docs/analytics/event-catalog.md` egy sorral bővült
  (`recognitionQualityReported`) — ezt a `telemetry_redaction_test.dart`
  MINOR-5 cellája kétirányban kényszeríti ki, tehát nem opcionális kísérő.
- A 2. hullám (PKG-E) a `recognitionShadowModeEnabled` +
  `strumModelRolloutStage` PÁRT fogyasztja, nem a boolean-t önmagában.
