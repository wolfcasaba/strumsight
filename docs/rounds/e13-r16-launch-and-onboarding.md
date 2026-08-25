# E13-R16 — Launch, recovery és onboarding migráció

- **Státusz:** READY (pre-flight lezárva 2026-08-25, `main @ 3848ef72` — lásd
  §0.0 és §0.0/B; előre megírva 2026-08-15, `main @ 6adea220`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 16 — **az első képernyő-migrációs kör**
- **Kör-azonosító:** `E13-R16`
- **Branch:** `<motor>/e13-r16-launch-and-onboarding`
- **Előfeltétel:** `E13-R15` merge-elve (lokalizáció)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0281`](../adr/0281-permission-primer-and-honest-first-win.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a TÉNYLEGES bootstrap-
> és engedély-átjáró réteget (`lib/app/bootstrap/`), valamint az onboarding
> jelenlegi tárolt állapotát — a §5.4 migráció csak a mért sémára írható meg.
> Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/app/bootstrap/",
  "lib/features/onboarding/",
  "lib/app/routing/",
  "lib/l10n/features/onboarding_en.arb",
  "lib/l10n/features/onboarding_hu.arb",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/l10n/arb_parity_test.dart",
  "test/features/onboarding/onboarding_test.dart",
  "test/features/onboarding/bootstrap_routing_test.dart",
  "test/features/onboarding/permission_primer_test.dart",
  "test/features/onboarding/onboarding_resume_test.dart",
  "test/features/onboarding/first_win_test.dart",
  "test/ui/goldens/",
  "docs/rounds/e13-r16-launch-and-onboarding.md",
]
gate_tests = [
  "test/features/onboarding/bootstrap_routing_test.dart",
  "test/features/onboarding/permission_primer_test.dart",
  "test/features/onboarding/onboarding_resume_test.dart",
  "test/features/onboarding/first_win_test.dart",
  "test/ui/goldens/e13_r16_screens_golden_test.dart",
]
native_gate = false
```

## 0.0 BRIEF-REVÍZIÓ — 2026-08-25, az indítás előtti KÖTELEZŐ pre-flight

A brief 2026-08-15-én készült, `main @ 6adea220` olvasásával; ez a pre-flight
`main @ 0f05df02` (E09-R27 után) ellen mért. **Visszakeresett előzmény**
(`tools/knowledge-rag.mjs --corpus lessons,halts,adr`):
[L478](../LESSONS.md) (a pre-flight csak SZŰKÍTHET), [ADR 0307 §4](../adr/0307-parallel-round-execution.md)
(generált ARB-aggregátum), [ADR 0424](../adr/0424-localization-resilience-contract.md)
(fragmentum-szintű paritás) és [ADR 0281](../adr/0281-permission-primer-and-honest-first-win.md)
(a kör előre kiosztott ADR-je, a `main`-en — **ne írd újra**).

**Kockázat = high, indoklás:** a kör az `authorization` határon dolgozik — a
mikrofon **engedély**-primer és a rendszer-párbeszéd sorrendje (§5.1), valamint
az erőforrás felszabadítása a route elhagyásakor (§5.4/A5) — továbbá a §5.5
onboarding-állapot **migration** útja perzisztált felhasználói adatot érint.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → SZŰKÍTVE

A brief §4-e pontosan ezt a két fájlt sorolta fel szövegírás céljára. Mérve az
[ADR 0307 §4](../adr/0307-parallel-round-execution.md): a körök
`lib/l10n/features/<feature>_{en,hu}.arb` fragmentumot írnak, az `app_*.arb`
determinisztikus unió, amit a gate frissességre ellenőriz. A fán ma öt szegmens
él (`base/app`, `features/{community,design_system,gamification,tuner}`), a
`tool/gen_l10n_segments.dart` pedig a `features/` könyvtárat **beolvassa** —
regisztrálandó lista nincs. Ez a hibaosztály **ötödször** ütött (L365, L369,
L396, [L478](../LESSONS.md)).

**Elvégzett lépés (szűkítés, orchestrátor-hatáskör) — az R5 RÉSZBEN
VISSZAVONTA, olvasd ott:** a két generált útvonal először törölve lett az
`allowed_paths`-ról; a merge-elt precedens mérése után viszont a listán marad,
`CSAK GENERÁLT KIMENET` szereppel. Kézzel írni őket változatlanul TILOS; a
gate `L10n aggregate freshness` lépése ezt függetlenül méri.

### R2 — a kör ÚJ szöveget IGÉNYEL, tehát a szűkítés nem teszi teljesíthetővé → **H3**

Az E13-R15-öt a mérés oldotta fel: ott a paritás minden szinten teljes volt,
tehát nulla pótolandó hiány maradt, és a kör ARB-írás NÉLKÜL teljesült. **Itt
ez a kiút mérve nem áll fenn.** A §5.1 primer-szöveg, a §5.2 gyenge-jel segítő
szöveg és a §5.6 redaktált hibaüzenet MIND új, felhasználónak megjelenő
szöveg; a képernyő ma mindössze **négy** kulcsot használ
(`onboardFirstWin`, `onboardNext`, `onboardSkip`, `onboardStart`), amelyek a
`lib/l10n/base/app_{en,hu}.arb`-ban élnek — az pedig szintén nincs az
engedélyezett listán.

A szó szerint vett brief tehát **végrehajthatatlan**: nincs olyan
engedélyezett útvonal, ahová a kör egyetlen új szöveget is írhatna. A
feloldás a FORRÁS-útvonal felvétele, ami **tágítás, azaz H3**
([ADR 0087 §2](../adr/0087-autonomous-round-pipeline.md)) — az orchestrátor ezt
[L478](../LESSONS.md) szerint utólag **NEM javíthatja**, a helyes felsorolás a
brief-írás felelőssége. **A kör ezért emberi döntésig NEM indítható.**

### R3 — két további, listán kívüli útvonal, amit a kör mérve érinteni fog

Egyik sem javítható tágítás nélkül; a döntéshez tartoznak, nem külön leletek.

1. **`test/l10n/arb_parity_test.dart`** — a `fragments` lista **beégetett** öt
   tuple (`arb_parity_test.dart:20-39`). Egy új `features/onboarding_*.arb`
   fragmentum mérce NÉLKÜL maradna: sem a fragmentum-szintű paritás, sem az
   ICU-plural ellenőrzés nem futna a kör új szövegeire.
2. **`test/features/onboarding/onboarding_test.dart`** — MA is létezik és zöld,
   közvetlenül állít a migrálandó képernyőre (`OnboardingController`,
   `onboardingSeenProvider`, `screens/onboarding_screen.dart` import). A brief
   négy ÚJ teszt-fájlt sorol fel, ezt nem. A migráció után majdnem biztosan
   pirosra vált — a §0 szerint az `blocked`, nem teszt-átírás.

### R4 — az „örökség ellenőrzőpont-állapot" MÉRVE egyetlen `bool` (tiszta mérés, nem lista-változás)

Az §5.5/A7 gazdagabb örökséget feltételezett. Mérve:

- `lib/features/onboarding/` **két** fájl: `onboarding_provider.dart` és
  `screens/onboarding_screen.dart`.
- A tárolt állapot egyetlen logikai érték:
  `StorageKeys.onboardingSeen = 'ss.onboarding.seen'`, amit
  `OnboardingController.readSeen` olvas (hiányzó kulcs ⇒ `false`).
- A régi `onboarding_seen_v1` → `ss.onboarding.seen` átnevezést a
  `lib/core/storage/storage_migrator.dart:371-376` (`version: 11`,
  `id: 'r06.onboarding_seen'`) **MÁR elvégzi** — a kör nem ezt írja meg újra.

Ezért az **A7** cella így értendő: a kör BEVEZETI a lépés-szintű
ellenőrzőpont-tárolót, és a migráció az, hogy a meglévő `true` érték
**befejezett** onboardingként öröklődik (visszatérő felhasználónál nem indul
újra a folyamat), a `false`/hiányzó pedig az első lépésre áll. A
`storage_migrator.dart` **TILOS zóna** — új tároló-verzió igénye ⇒ `stopped`.

### R5 — a H3 FELOLDVA emberi döntéssel (2026-08-25), és a szűkítés részben visszavonva

A user az R2/R3 eszkalációra **engedélyezte** a lista tágítását. A §4 és az
`ai-router` blokk ezzel hat útvonallal bővült:
`lib/l10n/features/onboarding_{en,hu}.arb` (ÚJ forrás-fragmentum),
`lib/l10n/base/app_{en,hu}.arb` (a 4 meglévő `onboard*` kulcs kiköltöztetése),
`test/l10n/arb_parity_test.dart` (egy tuple) és
`test/features/onboarding/onboarding_test.dart`.

**Az R1 szűkítése részben VISSZAVONVA — mérés alapján.** A merge-elt
precedens egységes: minden fragmentumot érintő kör a fragmentumot **ÉS** a
regenerált aggregátumot is commitolja, és a briefjeik az aggregátumot az
`allowed_paths`-on tartják — E09-R26 (`df0ad3dd`), E13-R12 (`376b8a1d`),
E13-R11 (`d55d1656`), E13-R10 (`b11ab2ed`), E09-R21, E09-R20 mind ezt a
párost mutatja. Az aggregátum teljes törlése tehát a kör KÖTELEZŐ
regenerálását tette volna listán kívüli sértéssé. A helyes alak nem a törlés,
hanem a **szerep megnevezése**: az `app_*.arb` a listán marad, de kizárólag
`dart run tool/gen_l10n_segments.dart --write` kimeneteként — kézzel írni
TILOS, és ezt a gate `L10n aggregate freshness` lépése függetlenül méri.

**Az onboarding-kulcsok kiköltöztetése megengedett, nem kötelező:** a kör
vagy átviszi a 4 meglévő `onboard*` kulcsot a fragmentumba (az ADR 0307 §4
szerinti lusta migráció), vagy a `base/`-ben hagyja és csak az ÚJ kulcsokat
írja a fragmentumba. Mindkettő elfogadható; a `base/` útvonal ezért van a
listán. Ami NEM elfogadható: a `base/app_*.arb` bármely, az onboardinghoz
nem tartozó kulcsának érintése.

### Nem lelet, de rögzítve

`test/ui/goldens/` MA nem létezik (a kör hozza létre, a §4 már engedi); a
golden-precedens `test/features/live/chord_timeline_golden_test.dart` létezik
és valódi kapu; az ADR 0281 a `main`-en van.

---

## 0.0/B — A DISPATCH ELŐTTI pre-flight mérései (orchestrátor, 2026-08-25)

A fenti R1–R5 az előkészítő batch mérése `main @ 0f05df02` ellen; ez a blokk a
tényleges indítás előtt, `main @ 3848ef72` ellen mért. **Mind a négy lelet
pontosítás vagy SZŰKÍTÉS — egyik sem tágítja az engedélyezett listát**
([ADR 0087 §2](../adr/0087-autonomous-round-pipeline.md), [L478](../LESSONS.md)).

**ADR:** a kör **nem ír új ADR-t**. A döntéseket a `main`-en lévő
[ADR 0281](../adr/0281-permission-primer-and-honest-first-win.md) rögzíti
(`0d65c861`), és a `docs/adr/**` a §3 tilos zónájában van. A 0,60-as küszöböt
az ADR 0281 §2 Döntés-pontja kimondja — a brief §6.1 ezt tükrözi, nem újítja.

### P1 — a 0,60-as küszöb KÖR-LOKÁLIS állandó, NEM a `confidenceThresholdProvider`

*(A kör-prompt §1.1 „elérhetetlen cél-státusz" mérése: melyik BEMENET produkálja
a cél-állapotot — a hívási úton mérve, nem a táblából olvasva.)*

Mérve: `ConfidenceThresholdNotifier.defaultValue = 0.45`
(`lib/features/settings/providers/confidence_threshold_provider.dart:10`) —
felhasználó által állítható és perzisztált érték. A §6.1 „küszöb alatt" cellája
**pontosan 0,45** bemenettel dolgozik.

Ha tehát az „első siker" kapuja a `confidenceThresholdProvider`-t olvasná, a
0,45-ös cella a küszöbre esne (`>=` inkluzív határ ⇒ **siker**), és az A3
„nem siker" elvárása **elérhetetlenné** válna; ráadásul mind a három cella
kimenetele egy felhasználói beállítástól függene.

**Előírás:** a 0,60 a kör saját, `const` állandója a
`lib/features/onboarding/` fán; az „első siker" út a
`confidenceThresholdProvider`-t **nem olvassa**. (A `lib/features/settings/**`
amúgy is tilos zóna.)

### P2 — az A5 a kör SAJÁT fake motorján mérendő; új `AudioOwner` = tilos zóna

*(A kör-prompt §1.2 „erőforrás-tulajdonlás" mérése a tényleges hívási láncon.)*

Mérve — a mikrofon megszerzésének EGYETLEN útja:
`createMicCapture(ref, AudioOwner.<x>)` (`lib/core/audio/audio_providers.dart:43`),
és `enum AudioOwner { live, tuner, analyzeRecorder, latencyCalibration,
diagnostics }` (`lib/core/audio/lifecycle/audio_session_lease.dart:5-11`) —
**onboarding-variáns nincs**. Egy ilyen felvétele a `lib/core/audio/**`-ot
írná, ami a §4 tilos zónája ⇒ `stopped`.

A brief §3 ezért ír „fake átjáróval és motorral" mini Stage-et: az **A5**
(mikrofon felszabadul a route elhagyásakor) a kör saját, onboarding-tulajdonú
felszabadítási útján mérendő. Merge-elt minta, amit követni kell:
`liveFrameProvider` → `ref.onDispose(engine.stop)`
(`lib/features/live/providers/live_providers.dart:22`).

Az engedély-primer NEM igényel tilos-zóna írást: a kapu
`microphonePermissionGatewayProvider` (`lib/core/audio/audio_providers.dart:14`),
és a MAI onboarding képernyő már ezen keresztül kér
(`lib/features/onboarding/screens/onboarding_screen.dart:53`) — a tesztek
`ProviderScope` override-dal fake átjárót adnak, pont ahogy a
`MicrophonePermissionGateway` doc-commentje előírja.

### P3 — `test/features/onboarding/first_win_test.dart` MA IS LÉTEZIK és zöld

Az R3.2 ezt a hibaosztályt megtalálta, de csak az `onboarding_test.dart`-ra. A
`first_win_test.dart` **szintén létező, zöld, legacy teszt** (87 sor, r155
eredet, `36c93152`): állít a `Lessons.firstWin` szerkezetére, a
`ChordShapes.has('Em')`-re, a `Lessons.nextAfter('first-win')` becsatornázásra
és az onboarding utolsó oldalának CTA-jára.

A §4 tehát nem „4 ÚJ teszt-fájlt" sorol: a `first_win_test.dart` **migrációs
célpont**, és rá az R3.2 szabálya változatlanul áll — **a lefedett viselkedés
NEM gyengíthető**, a kör a §6.1 cella-hármast és az A5-öt HOZZÁADJA, nem
lecseréli. Ellenőrizve: `bootstrap_routing_test.dart`,
`permission_primer_test.dart`, `onboarding_resume_test.dart` valóban nem
léteznek (újak).

### P4 — az A8/§5.6 a `BootstrapFailure` SZÖVEGÉBEN oldandó meg, a szerződés alakja NEM törhet

Mérve, a mai helyreállítási út végig:

1. `lib/app/bootstrap/app_bootstrap.dart:106` → `BootstrapFailure(['Bootstrap failed: $e'])`
   — a kivétel **nyers `toString()`-je**;
2. `lib/main.dart:57-58` → `runApp(BootstrapFailureApp(problems: problems))`;
3. `lib/app/strumsight_app.dart:98` → `Text('• $p')` — a problémák szó szerint
   a képernyőre kerülnek.

Vagyis a §6.1 „`toString()` a helyreállítási hibán" PIROS cellája **ma tényleges
viselkedés**, és a javítás helye (`lib/app/bootstrap/`) az engedélyezett listán
van. A gyökér-javítás tehát scope-on belüli: a `catch` ág **redaktált,
kód-alapú** üzenetet adjon, ne `$e`-t.

**Kötött megszorítás:** a `BootstrapFailure`/`BootstrapSuccess` publikus alakja
**forrás-kompatibilis** kell maradjon, mert két fogyasztója a tilos zónában van
(`lib/main.dart:58`, `lib/app/strumsight_app.dart:53`). Mező **hozzáadása**
(alapértelmezett értékkel) rendben; a `problems` típusának/nevének
megváltoztatása vagy a konstruktor-szignatúra törése lefordíthatatlanná tenné
két, nem szerkeszthető fájlt ⇒ `stopped`. Az ÚJ, redaktált helyreállítási
felület a `lib/app/bootstrap/` fán éljen (route-ja a `lib/app/routing/`-ban),
a golden- és route-teszt közvetlenül azt példányosítsa.

### P5 — az `arb_parity_test.dart` `fragments` listája (pontosítás)

Mérve: `test/l10n/arb_parity_test.dart:19-40`, öt tuple (`base/app`,
`features/{community,design_system,gamification,tuner}`). A kör **pontosan egy**
tuple-t vesz fel (`features/onboarding`), a meglévő ötöt és az ellenőrző
logikát nem érinti — ahogy a §4 sora előírja.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az UI-01–UI-04 felületek (indulás, helyreállítás, onboarding, mikrofon-primer)
átállítása az új design systemre (SDD Ch13 Kör 16).

## 2. Jelenlegi állapot — mért tények

- Az R02–R15 teljes komponens-készlete rendelkezésre áll: felület, szín,
  tipográfia, motion, ikon, állapot, űrlap, overlay, accessibility, l10n.
- Az R10 ADR 0277 kimondta: nyers kivétel nem jelenik meg — a helyreállítási
  képernyő **redaktált** hibamegjelenítést kap.
- Az R09 ADR 0276 kimondta: prezentációs réteg nem birtokol erőforrást — a
  mikrofon-primer ezt a határt tartja.

## 3. Scope

**Benne van:** az indulási felület villanásmentes, téma-biztos állapotkezelése ·
helyreállítás / biztonságos mód **redaktált** hibamegjelenítéssel · progresszív,
**visszatérhető** onboarding lépések · mikrofon-primer + „első siker" mini
Stage folyamat **fake átjáróval és motorral** tesztelhetően · az onboarding
verzió/ellenőrzőpont tároló migrációja · golden és route tesztek.

**NINCS benne (tilos):** DSP vagy felismerési logika módosítása (AGENTS.md §9) ·
más képernyők migrációja (Kör 17+) · az onboarding **kihagyhatóságának**
termékdöntése (az user-döntés; a kör csak a technikai lehetőséget adja meg) ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/app/bootstrap/` | villanásmentes indulás + biztonságos mód |
| `lib/features/onboarding/` | a folyamat migrációja |
| `lib/app/routing/` | az UI-01–UI-04 route-ok |
| `lib/l10n/features/onboarding_{en,hu}.arb` | **FORRÁS** — a primer, a helyreállítás és az „első siker" új szövegei (ÚJ fragmentum, ADR 0307 §4) |
| `lib/l10n/base/app_{en,hu}.arb` | a MA is itt élő 4 `onboard*` kulcs kiköltöztetése a fragmentumba (lusta migráció, ADR 0307 §4) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/l10n/arb_parity_test.dart` | az ÚJ fragmentum felvétele a `fragments` listába — **pontosan egy tuple**, a meglévő 5 sor és az ellenőrző logika érintetlen |
| `test/features/onboarding/onboarding_test.dart` | ma zöld, a migrált képernyőre állítandó; a lefedett viselkedés NEM gyengíthető |
| `test/features/onboarding/*_test.dart` (4) | a §6 cellái |
| `docs/rounds/e13-r16-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` az `onboarding/` KIVÉTELÉVEL ·
`lib/core/design_system/**` (kész, csak használni kell) · `lib/core/theme/**` ·
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0281)

### 5.1 Nincs engedélykérés KONTEXTUS nélkül

A rendszer engedély-párbeszédét mindig megelőzi a primer, ami elmondja, mire
kell és mi lesz, ha nem adják meg. A hidegen felugró engedélykérés a
leggyakoribb végleges elutasítás oka.

**NEM elfogadható gyengítés:** engedélykérés az indulási képernyőn, mielőtt a
felhasználó bármit látott volna.

### 5.2 Az „első siker" NEM hazudik sikert gyenge jelnél

Ha a mikrofonjel gyenge vagy a felismerés bizonytalan, a folyamat ezt **kimondja**
és segít (közelebb a mikrofonhoz, csendesebb környezet) — nem gratulál.

**NEM elfogadható gyengítés:** garantált siker-képernyő az onboarding végén
„hogy jó élmény legyen". A termék hitelessége pont a felismerés igazmondása.

### 5.3 A biztonságos mód NEM töröl adatot

Helyreállítási felület, nem gyári visszaállítás. Ami törölhető, azt a
felhasználó **kéri**, tárgy-specifikus megerősítéssel (ADR 0279).

### 5.4 A mikrofon a route elhagyásakor FELSZABADUL

A primer és a mini Stage után nem maradhat nyitva a felvétel. Ez
acceptance-cella (A5).

### 5.5 Az onboarding VISSZATÉRHETŐ és folytatható

Megszakítás után ott folytatódik, ahol abbamaradt — az ellenőrzőpont-migráció
a régi állapotokat is átveszi.

### 5.6 A hibamegjelenítés REDAKTÁLT

Az ADR 0277 szerint: kód → lokalizált modell. A helyreállítási képernyőn sem
jelenik meg stack trace vagy belső útvonal.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Nincs engedélykérés primer (kontextus) nélkül | `permission_primer_test.dart` |
| A2 | Véglegesen megtagadott engedélynél a beállítás-út jelenik meg | ugyanott |
| A3 | Az „első siker" gyenge jelnél NEM jelent sikert | `first_win_test.dart` |
| A4 | A biztonságos mód nem töröl adatot | `bootstrap_routing_test.dart` |
| A5 | A mikrofon a route elhagyásakor felszabadul | `first_win_test.dart` |
| A6 | Az onboarding megszakítás után folytatható | `onboarding_resume_test.dart` |
| A7 | A régi ellenőrzőpont-állapot migrálódik, nem vész el | ugyanott |
| A8 | A helyreállítási képernyőn nincs nyers kivétel | `bootstrap_routing_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r16_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Engedélykérés az indulásnál, primer nélkül | **A1** |
| Végleges megtagadásnál újrakérés | A2 |
| Fix „Gratulálunk!" képernyő gyenge jelnél is | **A3** |
| A biztonságos mód üríti a tárolót | **A4** |
| A mikrofon nyitva marad kilépés után | **A5** |
| A régi onboarding-állapot eldobva | A7 |
| `toString()` a helyreállítási hibán | A8 |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**Az „első siker" három kötelező cellája** (a küszöb: a felismerés
megbízhatósági határa, **0,60**):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | 0,45 megbízhatóság | **nem siker** — segítő szöveg, újrapróba |
| rajta (a küszöbön) | pontosan **0,60** | **siker** (a határ inkluzív) |
| a küszöb fölött | 0,85 | siker |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** tedd a siker-képernyőt
feltétel nélkülivé → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/onboarding/bootstrap_routing_test.dart test/features/onboarding/permission_primer_test.dart test/features/onboarding/onboarding_resume_test.dart test/features/onboarding/first_win_test.dart test/ui/goldens/e13_r16_screens_golden_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r16_screens_golden_test.dart
```

A keletkezett PNG-ket **commitolni kell** — enélkül az A9 nem teljesült. A
márkabetűtípusok a teszt-hostban nem töltődnek be (fallback face); ez a
meglévő golden-teszt mért viselkedése, az elrendezést, méretezést és színeket
nem érinti. MIÉRT ez a kör dolga és nem az E13-R36-é: a záró vizuális
regressziós kör csak azt tudja megmondani, hogy valami MEGVÁLTOZOTT — azt,
hogy a képernyő eleve csúnya-e, a saját körében kell látni.

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. Bootstrap: villanásmentes, téma-biztos állapot + redaktált hibamegjelenítés.
2. Biztonságos mód — adatmegőrzéssel.
3. Onboarding lépések, visszatérhetően + ellenőrzőpont-migráció.
4. Mikrofon-primer (fake átjáró) + a végleges megtagadás útja.
5. „Első siker" mini Stage (fake motor) + a három küszöb-cella.
6. A mikrofon felszabadítása route-elhagyáskor.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A garantált siker.** Az onboarding „jó élmény" reflexe pont a termék
  igazmondását áldozza fel (A3).
- **A nyitva maradó mikrofon.** Nem látszik a felületen, és az akkumulátort meg
  a bizalmat is viszi (A5).
- **Az ellenőrzőpont-migráció.** A régi mezőnevek elhagyása némán újrakezdeti az
  onboardingot a meglévő felhasználóknak (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
