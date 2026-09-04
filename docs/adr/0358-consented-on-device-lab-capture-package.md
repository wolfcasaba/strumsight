# ADR 0358 — Az eszközön keletkező Lab-mérőcsomag: beleegyezés nélkül nincs kimenet, azonosító nélkül nincs metadata, és ugyanaz a bemenet bájtra ugyanaz a csomag

- **Státusz:** Elfogadva
- **Kör:** `E14-R06` (Chapter 14 — Recognition Accuracy & Useful UI Recovery, Kör 6)
- **Dátum:** 2026-09-04
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Kapcsolódó:** [ADR 0249](0249-analysis-evaluation-dataset-governance.md)
  (a repó sémát és annotációt tart, nyers audiót soha),
  [ADR 0354](0354-recognition-baseline-manifest-and-evidence-index.md)
  (determinisztikus, bájtazonos mérési artefaktum),
  [ADR 0178](0178-vision-privacy-by-default.md)
  (privacy by default; a Lab capture consent-flow külön kör felelőssége — ez az),
  [ADR 0132](0132-ai-tutor-privacy-and-consent.md)
  (tengelyenkénti, azonnal ható beleegyezés),
  [ADR 0479](0479-privacy-data-inventory-and-consent-enforcement.md)
  (egress-útvonalak nyilvántartása — lásd D7),
  [ADR 0054](0054-versioned-user-content-documents.md)
  (verziózott dokumentum: ismeretlen séma-verzió nem néma default)

## Kontextus — a pre-flight MÉRT tényei (2026-09-04, `main @ 5dcff18e`)

- **A felvevő MEGVAN, nem ez a kör írja:**
  `lib/features/analyze/engine/clip_recorder.dart` (2085 bájt) mono `List<double>`
  (-1..1) puffert és `sampleRate`-et ad (`stop()` → `List<double>.of(_buffer)`).
  A kör ehhez a KIMENETHEZ épít csomagot; a felvevő a tilos zónában van.
- **`lib/features/accuracy_lab/` nem létezik** (`ls` → „No such file or directory”),
  és a fán nincs `LabTask`, `LabConsent`, `LabCapturePackage`, `LabPackageWriter`
  típusnév (`grep -rn "class Lab…" lib/ test/` → nulla találat): nincs S5-ütközés.
- **A consent-minta megvan:** `tutor_privacy_providers.dart` +
  `domain/models/tutor_consent.dart` — tengelyenkénti grant/revoke másoló
  metódusok egy értékobjektumon (ADR 0132). Az `E14-R06` ezt a mintát
  ÚJRAHASZNOSÍTJA, de nem importálja: a cross-feature import csak `public.dart`
  barrelt célozhat (`tool/check_architecture.dart:774`), és az ai_tutor barrelje
  nem exportálja a consent modellt.
- **Nincs elérhető WAV-kódoló:** a `lib/features/learn/audio/wav.dart` és a
  `lib/features/analyze/engine/wav_decoder.dart` LÉTEZIK, de EGYIK feature
  `public.dart`-ja sem exportálja (`grep -rn "wav" lib/features/*/public.dart`
  → nulla). Egy közvetlen import architektúra-sértés lenne, a barrel bővítése
  pedig a tilos zóna.
- **A barrel-frissesség őre NEM aktiválódik:** a generált barrel-ellenőrzés
  (`tool/check_architecture.dart:798` → `barrel.featuresWithPublicFragments`)
  csak azokra a feature-ökre fut, amelyeknek van `lib/features/<f>/public/`
  **fragment-könyvtára** (`tool/gen_public_barrel.dart:182-199`). Az
  `accuracy_lab` nem hoz létre ilyet, ezért a `public.dart` **kézzel írott**
  és a generátor futtatása nem előfeltétel.
- **A data-inventory őre hálózati kilépést keres:** a felderítés Dio-factory,
  `ApiClient`, `share_plus`, `HttpClient` és `package:http` mintákra fut
  (`tool/check_data_inventory.dart:371-438`) — egy `dart:io` fájlírás NEM
  egress-útvonal, ezért a kör nem igényel nyilvántartás-bejegyzést. Ez a
  mentesség KIZÁRÓLAG addig áll, amíg a diff egyik felsorolt mintát sem
  használja (D7).
- **A `crypto: ^3.0.7` deklarált függőség** (`pubspec.yaml:46`, „source SHA-256
  provenance”) — a checksumhoz nem kell új csomag; a `pubspec.yaml` a tilos
  zónában van.
- **A `share_plus: ^13.2.0` a fán van** (`pubspec.yaml:39`), tehát egy „megosztom
  a csomagot” reflex GÉPILEG elérhető — a D7 tiltása nem elméleti.
- **Mérési előzmény a redakciós tesztre:** [L260](../LESSONS.md) — egy fix
  kulcskészletű DTO ellen a `forbiddenKeys.contains('"$key"')` alakú teszt
  KONSTRUKCIÓ SZERINT mindig zöld, mert a DTO kulcsai sosem egyeznek a
  tiltólistával. A szivárgás az ÉRTÉK-oldalon van.

## Döntés

### D1 — A beleegyezés a TÍPUSBAN él, nem egy `bool`-ban

A csomagot kiadó/exportáló hívás paramétere `LabConsentGranted` (vagy azzal
egyenértékű, kizárólag megadott beleegyezésből előállítható típus). A
`granted` / `revoked` / `unknown` állapot **külön típus vagy zárt sealed
hierarchia**; a hívás a `revoked`/`unknown` ágra **nem fordul**.

**NEM elfogadható** gyengítés: nullable consent + `?? false`, `bool granted`
paraméter, „a hívó felelőssége” doc-comment, futásidejű `assert`.

### D2 — A csomag nem hordoz azonosítót — a mérce ALLOWLIST, nem tiltólista

Az eszköz-metadata kulcskészlete **zárt**: modellnév, OS-verzió, mintavételi
frekvencia, csatornaszám, app-verzió. Tilos e-mail, account/auth token, pontos
hely, IMEI, hirdetési azonosító, felhasználónév, abszolút fájlút.

A mércét **allowlist**-ként kell megírni: a szerializált JSON rekurzívan
összegyűjtött kulcshalmaza **EGYENLŐ** a megengedett halmazzal (nem
„nem tartalmazza a tiltottakat”). Ez a döntés közvetlenül az [L260](../LESSONS.md)
mérésből következik: egy tiltólista-teszt fix kulcskészletű DTO fölött vakon
zöld marad, az allowlist-egyenlőség viszont PIROSRA vált, amint bárki új mezőt
tesz a csomagba. A tiltólista-cella emellett MEGMARAD, de **érték-oldali
kanárival**: a bemenetbe tett, egyedi felismerhető minta (pl. eszköznévbe ágyazott
token) nem jelenhet meg a kimenetben azon a mezőn kívül, ahová szánták.

### D3 — Determinizmus: az idő BEMENET, a kulcsrendezés kanonikus

A csomag időbélyege a konstruktor/író **paramétere**; `DateTime.now()`,
`Random`, `hashCode`-alapú sorrend és `identityHashCode` a csomagot előállító
úton tilos. A JSON kulcsai minden szinten rendezettek, így ugyanaz a bemenet
**bájtra azonos** kimenetet ad — ez az [ADR 0354](0354-recognition-baseline-manifest-and-evidence-index.md)
D-sorának ugyanaz a szerződése, egy szinttel lejjebb.

### D4 — A törlés a fájlrendszert érinti, nem egy flaget

A törlő ág után sem a WAV, sem az annotáció, sem a manifest nem létezik a
lemezen, és a csomag lekérdezése `missing` státuszt ad. A mérce a fájlrendszer
(`existsSync()` → `false`), nem egy in-memory jelző.

### D5 — Séma-verzió kötelező, ismeretlen verzió TÍPUSOS hiba

`schemaVersion` a csomag gyökerében. Ismeretlen vagy hiányzó verzió olvasásakor
típusos hiba keletkezik ([ADR 0054](0054-versioned-user-content-documents.md)
mintája) — nem `null`, nem „legutolsó ismert” default, nem néma `try/catch`.

### D6 — A feladatlista mérete VALIDÁLT tartomány, nem kommentben leírt szándék

A 15–20 elemű tartományt egy **futtatható validáció** kényszeríti ki, amely
tetszőleges listát fogad (nem csak a beépítettet) — enélkül a „14 → hiba” és a
„21 → hiba” acceptance-cella nem írható meg, tehát a szerződés mérhetetlen
lenne. A beépített katalógus lefedi a hat feladat-családot (csend, zaj, egyes
akkord, lassú down/up, váltott pengetés, gyors pattern), és maga is átmegy a
validáción.

### D7 — Ez a kör NEM nyit kimenő csatornát

A csomag az eszközön marad. A diff nem használhat `share_plus`-t, Diót,
`ApiClient`-et, `HttpClient`-et vagy `package:http`-t, és nem hívhat
`path_provider`-t sem (a cél-könyvtár a hívótól érkező `Directory` paraméter,
így a teszt ideiglenes könyvtárban mér, a CI-n pedig nincs plugin-csatorna).

**Miért ADR-szintű:** ezek a minták EGYENKÉNT aktiválják a
`tool/check_data_inventory.dart` egress-felderítését, ami
`docs/privacy/data-inventory.yaml` bejegyzést követelne — az pedig ennek a
körnek a TILOS zónájában van. A tiltás tehát nem ízlés, hanem a kör
scope-határának gépi következménye.

### D8 — A WAV-kódolás a kör SAJÁT fájljában él

Mivel egyetlen feature-barrel sem exportál WAV-segédet (lásd a kontextus mért
tényét), a PCM → WAV bájtsorozat előállítása a `lab_package_writer.dart`-ban,
`dart:typed_data` fölött történik. Más feature belső fájljának importálása
architektúra-sértés, idegen barrel bővítése tilos zóna — a duplikáció itt a
HELYES ár, és a következő kör(ök) dolga, ha ezt közös helyre emeli.

## Következmények

- A későbbi körök (R07 annotáció, R08 harness) egy **bájtazonos, azonosító
  nélküli** csomagformátumra építhetnek ground truthot.
- A UI-bekötés (`E14-R06b`) csak a D1 típusos kapun keresztül férhet a
  csomaghoz; egy képernyő nem „adhat hozzá” beleegyezést egy bool-lal.
- Ha egy jövőbeli kör mégis kimenő csatornát nyit a csomagra, az a
  `docs/privacy/data-inventory.yaml` bejegyzéssel és a
  `test/privacy/consent_enforcement_test.dart` turn-path mérésével EGYÜTT
  történhet — ez a döntés nem ad rá felmentést.
- Ez a döntés nem lazítható azért, hogy egy teszt vagy egy demó zöld legyen.
