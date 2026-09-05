# ADR 0519 — Az audio-setup profil BEMENET, nem kalibráció: elavuló, atomikusan mentett, verziózott eszközprofil képernyő nélkül

- **Státusz:** Elfogadva
- **Kör:** `E14-R14` (Chapter 14 — Recognition Accuracy & Useful UI Recovery, Kör 14)
- **Dátum:** 2026-09-05
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Kapcsolódó:** [ADR 0505](0505-versioned-recognition-frame-contract-and-legacy-adapter.md)
  (a `SignalQualitySnapshot` szerződése és a `SignalQualityState` zárt halmaza —
  ez a kör ezt OLVASSA, nem méri újra), [ADR 0281](0281-permission-primer-and-honest-first-win.md)
  (az onboarding folytatható lépés-ellenőrzőpontja és a kör-lokális, inkluzív
  küszöb precedense), [ADR 0054](0054-versioned-user-content-documents.md)
  (verziózott lokális tárolás + tesztelt migráció mintája)

## Kontextus — a pre-flight MÉRT tényei (2026-09-05, `main @ 5f772a20`)

A brief 2026-08-20-án készült, `main @ 88e08e65` olvasata alapján. A
`brief-lint` **S15** lelete szerint ez az alap ELMOZDULT: a hivatkozott
`lib/features/onboarding/onboarding_provider.dart` módosult, és a kör
feature-gyökere alatt négy ÚJ fájl landolt. A pre-flight ezért újraolvasta a
felsorolt fájlokat. A mérés:

- **Az előre kiosztott `0366` szám elavult.** A foglaló
  (`tools/round-slots.py reserve-adr --round E14-R14`) a **`0519`**-et adta; a
  fán a legmagasabb szám `0517`, a `0366` nem létezik fájlként. A
  `ls docs/adr | tail` alak sorszám-választásra kifejezetten tiltott (mért
  ütközés 2026-08-05, `tools/tests/test_adr_numbering.py`). Az őr csak
  **egyediséget** és névalakot mér, folytonosságot nem, tehát a `0519` szabályos.

- **Nincs időközben merge-elt szerződés ugyanerre a döntésre.** Mérve:
  `grep -rln "AudioProfile\|audio_profile\|micRoute\|audioRoute" lib/ test/` →
  nulla találat az onboarding és a live fában (a két találat a
  `song_trainer` transport-állapota, tárgytalan). A
  `lib/features/onboarding/audio_setup/` könyvtár **nem létezik**, és a négy
  újonnan landolt fájl (`first_win_engine.dart`, `first_win_providers.dart`,
  `screens/first_win_stage_screen.dart`, `screens/permission_primer_screen.dart`)
  egyike sem deklarálja az `AudioSetupStep`, `AudioProfile`, `AudioProfileStore`
  vagy `AudioSetupController` típust. Típusütközés (S5) tehát nincs; az
  `OnboardingStep` (`welcome, permission, done`) egy MÁSIK, kipinnelt enum
  (`test/features/onboarding/onboarding_resume_test.dart`), amelyhez ez a kör
  nem nyúl.

- **A `SignalQualitySnapshot` MEGVAN és a `live` feature PUBLIKUS felületén van.**
  Mérve: `lib/features/live/domain/recognition/signal_quality_snapshot.dart`
  (165 sor, `SignalQualityState { good, tooQuiet, tooLoud, clipping, tooNoisy,
  speechLike, unstable, unknown }`), és a
  `lib/features/live/public.dart:29` **exportálja**. Az E14-R05 analizátora
  (`lib/features/live/engine/quality/live_signal_quality_analyzer.dart`) szintén
  a fán van.

- **A cross-feature import szabálya GÉPI, és ez a kör benne él.** Mérve:
  `tool/check_architecture.dart:382-392` — „A cross-feature import csak akkor
  legális, ha a cél-feature `public.dart` barrelére mutat"; a szabály neve
  `crossFeatureImportsMustUsePublicApi`, a kapu a `test/core/architecture_dependency_test.dart`
  („contains exactly the allowlisted dependency deviations"), amit a
  `tools/round-gate.sh` `architecture` lépése futtat. A `tool/check_architecture.dart`
  az allowlistjével együtt a kör TILOS zónájában van, tehát új deviációt
  felvenni nem lehet — a legális út a már meglévő export.

- **A `lib/features/onboarding/public.dart` NEM létezik, és kézzel írandó.**
  Mérve: 20 feature-nek van `public.dart`-ja, az onboardingnak nincs. A
  generált-barrel frissesség-őre (`_checkGeneratedBarrels`,
  `tool/check_architecture.dart:804`) kizárólag azokra a feature-ökre fut, amelyeknek
  van `lib/features/<f>/public/` fragmentum-könyvtára — mérve ez ma EGYETLEN
  feature, a `practice_generator`. Az onboardingnak nincs ilyen könyvtára,
  ezért egy kézzel írt barrel nem visz pirosra staleness-ellenőrzést.

- **A feature-lokális tárolókulcs a MERGE-ELT precedens.** Mérve:
  `OnboardingStepController.storageKey = 'ss.onboarding.step'`
  (`lib/features/onboarding/onboarding_provider.dart:64`), a doc-comment szó
  szerinti indoklásával: „this key has no `StorageKeys` entry of its own
  because `lib/core/storage/` is out of this round's allowed paths". A
  `KeyValueStore` (`lib/core/storage/key_value_store.dart`) szinkron olvasású,
  `writeString`/`remove`/`contains` műveletekkel, és a `PersistedPreference`
  mixin sosem nyeli el a `StorageException`-t némán, hanem logolja.

- **Az inkluzív küszöb szintén merge-elt precedens.** Mérve:
  `kFirstWinConfidenceThreshold = 0.60` + „The boundary is inclusive"
  (`lib/features/onboarding/first_win_providers.dart:10-14`).

- **A hossz-cellák egészben biztonságosak.** `python3 -c` mérés:
  `30 <= 59 <= 60 → True`, `30 <= 60 <= 60 → True`, `30 <= 61 <= 60 → False`;
  ezredmásodpercben `59000 <= 60000 → True`, `60000 <= 60000 → True`,
  `60001 <= 60000 → False`. Nincs lebegőpontos él, tehát az L637 csapdája
  (számolt „a küszöbön" cella) nem él, ha a cella egész literálból dolgozik.

## Döntés

### D1 — A profil a döntési réteg BEMENETE, sosem konstans-felülírás

Az `AudioProfile` egyetlen shipping DSP/ML konstanst sem ír felül, és nem
tartalmaz classifier-küszöböt. Amit hordoz: javasolt input gain, javasolt
input/vizuális latency, mért jelminőségi elvárás és a felhasználó saját
confidence-profilja. A Chapter 14 §9/4–5 tiltása (egy játékosra hangolt
threshold; mért A/B nélkül mozgatott shipping konstans) így gépileg nem
sérthető: a profil nem ír, csak leír.

**NEM elfogadható implementáció:** „a profil beállítja a küszöböt a
classifierben", vagy a profil bármely mezőjének visszavezetése a
`lib/features/settings/**` provider-eibe ebben a körben.

### D2 — Rossz jelminőség SOSEM ad sikerállapotot

Ha a lépéssor `tooQuiet` / `tooLoud` / `clipping` / `tooNoisy` /
`speechLike` / `unstable` állapotban zárul, az eredmény `needsAttention`,
**nem üres** tanács-szöveggel. A `success` kizárólag `good` mellett érhető el.
Az `unknown` (nincs elég adat) szintén nem `success` — az ADR 0505 §1 „valódi
állapot, sosem csendben `good`" kikötésének folytatása.

### D3 — A profil elavul a route vagy a mintavétel érdemi változásakor

A profil hordozza a felvételkori mikrofon-route azonosítóját és a mintavételi
frekvenciát. Ha a mai környezet ezektől eltér, a profil `stale`, és az
„érvényes profil" getter **nem adja vissza**. A stale profil csendes
felhasználása tilos: az olvasó vagy érvényes profilt kap, vagy semmit — a
kettő között nincs „majdnem jó" ág.

### D4 — Megszakítható, és a félbehagyott futás nem hagy részleges profilt

A lépés-gép bármely lépésen megszakítható és újraindítható. A mentés
**atomikus**: a profil egyetlen művelettel kerül a tárba a teljes futás
lezárultakor. Lépésenkénti („ami eddig megvan, azt már írjuk ki") mentés tilos —
ez a D4 egyetlen mérhető állítása, és a 3. acceptance-pont pontosan ezt méri.

### D5 — Verziózott tárolás, típusos hiba, tesztelt migráció

A tárolt alak kötelezően hordoz `schemaVersion`-t. Ismeretlen verzió **típusos
hiba** (`ArgumentError`), nem default profil és nem `null` — ugyanaz a
fail-closed dekódolás, amit a `SignalQualitySnapshot.fromJson` már alkalmaz
(ADR 0505 D6). A támogatott korábbi verzióból a migráció külön, tesztelt út
(ADR 0054 mintája), és a migrált profil mezői mérten egyeznek a várttal.

### D6 — A jelminőség a `live` feature PUBLIKUS felületén át érkezik

Az `audio_setup` réteg a `SignalQualitySnapshot`-ot kizárólag a
`lib/features/live/public.dart` barrelen keresztül importálja, sosem a
`domain/recognition/signal_quality_snapshot.dart` mély útvonalán. Indoklás: a
`crossFeatureImportsMustUsePublicApi` szabály (mérve fent) a mély importot
architektúra-sértésként jelenti, az allowlist bővítése pedig a kör tilos
zónájában lévő `tool/check_architecture.dart`-ot igényelné → H3. Az export
MÁR LÉTEZIK, tehát a legális út ma is járható.

### D7 — A tárolókulcs feature-lokális konstans

Az `AudioProfileStore` a saját `static const String storageKey` konstansát
használja (`ss.onboarding.audio_profile` alakban), nem vesz fel új
`StorageKeys` bejegyzést: a `lib/core/storage/` a kör tilos zónájában van. Ez
NEM új minta, hanem a merge-elt `OnboardingStepController.storageKey`
precedens (mérve fent) folytatása, ugyanazzal a doc-commentbe írt indoklással.

### D8 — Képernyő nélkül, a Chapter 13 sávval nem ütközve

A kör a lépés-gépet, a profil-modellt és a tárolót szállítja; képernyőt nem.
A `lib/features/onboarding/screens/**` a Chapter 13 sáv területe (E13-R16 ott
landolt), és két sáv ugyanarra a felületre írva fájl-ütközést adna. A
UI-bekötés külön kör (`E14-R14b`); ennek a körnek az acceptance-e nem
hivatkozhat rá.

## Következmények

- Az onboarding megkapja az első `public.dart` barrelét — a kézzel írt,
  additív export a feature első reviewzott publikus felülete. Amíg nincs
  `lib/features/onboarding/public/` fragmentum-könyvtár, a generált-barrel őr
  nem érinti; ha egy későbbi kör fragmentumokra migrálja, a barrelt akkor a
  `dart run tool/gen_public_barrel.dart --write` termeli.
- A `live` feature `public.dart`-ja ezzel a második fogyasztóját kapja meg a
  felismerési szerződésre — az ADR 0505 „stabil szerződés" állítása mérhető
  használatot kap, nem csak deklarációt marad.
- A profil elavulási szabálya (D3) azt jelenti, hogy egy fejhallgató
  csatlakoztatása vagy egy mintavétel-váltás után a wizard újrafuttatandó. Ez
  szándékos költség: a D1 szerinti „bemenet" csak akkor hasznos, ha ahhoz a
  környezethez tartozik, amelyben mérték.
- A D2 miatt a wizard nem tud „zöldre hazudni" egy rossz felvételi
  környezetet. A felhasználó felé ez több `needsAttention` végállapotot jelent,
  mint amennyi egy engedékeny osztályozással látszana — ez a truthfulness-blokk
  (Chapter 14) kimondott célja.

## Alternatívák

- **A profil felülírja az input gain / confidence küszöböt a settings
  providerekben.** Elvetve: pontosan a Chapter 14 §9/4–5 tiltott mintája (egy
  játékosra hangolt shipping konstans, mért A/B nélkül), és a
  `lib/features/settings/**` a kör tilos zónájában van.
- **A profil mély importtal olvassa a `SignalQualitySnapshot`-ot, és az
  architektúra-allowlist kap egy új sort.** Elvetve: az allowlist a
  `tool/check_architecture.dart`-ban él, ami a kör engedélyezett listáján
  KÍVÜL van → H3. Ráadásul a mély import a `live` engine-jének átszervezésekor
  némán törne, miközben a `public.dart` export épp ezt a stabilitást ígéri.
- **Új `StorageKeys` bejegyzés a profilnak.** Elvetve: `lib/core/storage/` a
  tilos zónában van, és a merge-elt onboarding-precedens (D7) már megoldotta
  ugyanezt a problémát feature-lokális konstanssal.
- **Lépésenkénti mentés, hogy egy megszakadt futás ne vesszen el.** Elvetve: a
  részleges profil pont az a „majdnem jó" állapot, amit a D3 és a D4 kizár —
  egy fél mérésből származó gain-javaslat rosszabb, mint a javaslat hiánya.
- **A kör a wizard képernyőjét is szállítja (a SDD Kör 14 eredeti kérése).**
  Elvetve a D8 szerint: sáv-ütközés a Chapter 13 onboarding felületével.
