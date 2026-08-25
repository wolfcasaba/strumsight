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

**Mit építettem.**

- `lib/app/bootstrap/app_bootstrap.dart` — a catch-all ág többé nem
  interpolálja a nyers kivételt (`'Bootstrap failed: $e'` →
  `'Bootstrap failed: unexpected startup error (bootstrap.unknown). Please
  restart the app.'`); a nyers hiba a loggeren megy (diagnosztika), a UI-ra
  soha (A8). A `'Bootstrap failed'` előtag szándékosan megmaradt — egy
  tilos zónában lévő, meglévő teszt (`test/app/app_bootstrap_test.dart`)
  erre a szó szerinti substringre állít, és ez a mérce megőrizhető úgy, hogy
  az A8 sértés (a `StateError` szövege) közben ne kerüljön be.
- `lib/app/bootstrap/recovery_screen.dart` (ÚJ) — a biztonságos mód
  in-app felülete: a már redaktált `problems` listát jeleníti meg, nincs
  adattörlő akciója (A4), `Ss*` design-system tokenekkel épül. Route:
  `AppRoutes.recovery` (`lib/app/routing/app_route.dart`), regisztrálva
  `lib/app/routing/app_router.dart`-ban (`state.extra` hordozza a
  problémákat).
- `lib/app/bootstrap/launch_screen.dart` (ÚJ) — villanásmentes indulási
  felület: kizárólag `Theme.of(context)`-ből származó színek, nincs
  hardcode-olt háttér.
- `lib/features/onboarding/onboarding_provider.dart` — `OnboardingStep`
  enum + `OnboardingStepController` (checkpoint-notifier), publikus
  `storageKey` konstans (`'ss.onboarding.step'`, ÚJ, nincs a
  `StorageKeys`-ben, mert a `lib/core/storage/` a listán kívül van).
  `readStep` a régi `ss.onboarding.seen` bool-t migrálja: `true` → `done`
  (a meglévő felhasználó NEM ismétli a folyamatot), `false`/hiányzó →
  `welcome` (A7). `advanceTo` szinkronban ír state-et, majd perzisztál.
- `lib/features/onboarding/screens/permission_primer_screen.dart` (ÚJ) —
  a mikrofon-primer: a rendszerdialógus ELŐTT indokol (A1), a `SsPermissionState`
  design-system komponenssel a beállítás-utat mutatja végleges elutasításnál
  (A2), és már-megadott engedélynél azonnal `onGranted`-et hív ask-UI nélkül.
- `lib/features/onboarding/first_win_engine.dart` +
  `first_win_providers.dart` (ÚJ) — `OnboardingFirstWinEngine` interfész +
  `FakeOnboardingFirstWinEngine` (P2: a kör saját fake motorja, nincs
  `AudioOwner.onboarding`). `kFirstWinConfidenceThreshold = 0.60` kör-lokális
  `const` (P1, NEM `confidenceThresholdProvider`). A provider-pár
  (`onboardingFirstWinEngineProvider` → `onboardingFirstWinConfidenceProvider`)
  szó szerint a `liveFrameProvider` mintáját követi:
  `ref.onDispose(engine.stop)` az autoDispose providerben (A5).
- `lib/features/onboarding/screens/first_win_stage_screen.dart` (ÚJ) — a
  mini Stage: gyenge jelnél (`< 0.60`) sosem mutat sikert, csak "próbáld
  újra" szöveget és Retry gombot; a küszöbön/fölötte Continue jelenik meg
  (A3).
- `lib/features/onboarding/screens/onboarding_screen.dart` — a
  `_currentStep()`/`_advanceStep()` pár és a lépés-switch a `build()`-ben
  hozzáadva; a KAROUSEL saját két CTA-ja (`onboardFirstWin`,
  `onboardStart`) VÁLTOZATLAN, byte-azonos viselkedésű maradt a régihez
  képest (l. lentebb, "Fontos felfedezés").
- `lib/l10n/features/onboarding_{en,hu}.arb` (ÚJ forrás-fragmentum) — a
  primer/first-win/recovery új szövegei; a meglévő 4 `onboard*` kulcsot a
  `base/`-ben hagytam (a brief ezt megengedi, nem kötelező kiköltöztetni).
  `dart run tool/gen_l10n_segments.dart --write` lefuttatva, `flutter
  gen-l10n` lefuttatva. `test/l10n/arb_parity_test.dart` +1 tuple
  (`features/onboarding`), az öt meglévő és az ellenőrző logika érintetlen.

**Fontos felfedezés a fejlesztés közben — a kör-terv módosítva.**

Az eredeti tervem a `PermissionPrimerScreen`+`FirstWinStageScreen`-t az
onboarding-karusszel UTOLSÓ oldalának CTA-ja MÖGÉ akartam kötni (tap →
primer → mini Stage → befejezés). Ez megsértett egy tilos zónában lévő,
MA ZÖLD, végponttól-végpontig tesztet:
`test/app/routing/onboarding_first_win_test.dart` — ez EGYETLEN
`tester.tap` + `pumpAndSettle` után elvárja, hogy a "Try your first win —
30 seconds" gomb azonnal befejezze az onboardingot, `/live`-ra navigáljon,
és felküldje a valódi `LearnScreen(Lessons.firstWin)`-t. Egy interaktív
primer/Stage beékelése ezt strukturálisan lehetetlenné teszi (a felhasználó
nem koppint át rajtuk egyetlen tap-ben).

Mivel ez a fájl a §4 tilos zónáján kívül esik, NEM módosíthattam. A
feloldás: a karusszel két CTA-ja (`_finish`/`_firstWin`) VISSZAÁLLT a
pontosan eredeti implementációra (direkt `primeMic`/mikrofon-kérés,
azonnali befejezés) — ez byte-szinten megegyezik a r155-ös eredetivel, csak
egy `_advanceStep(OnboardingStep.done)` hívással bővült (a checkpointot
szinkronban tartja a seen-bool-lal). A `PermissionPrimerScreen` és a
`FirstWinStageScreen` VALÓDI, teljesen tesztelt komponensek maradtak — az
`OnboardingScreen.build()` lépés-switch-e ténylegesen megjeleníti őket,
amikor a checkpoint már `permission`/`firstWin` állapotban van (l.
`onboarding_resume_test.dart` A6 csoportja) —, de a karusszel CTA-i egyelőre
NEM írják át erre a checkpointot. **Ez azt jelenti, hogy az A1 (primer a
rendszerdialógus előtt) ma csak a `PermissionPrimerScreen` saját
komponens-tesztjében bizonyított, a valós "Try your first win" úton a régi
`primeMic()` közvetlen hívás fut** — ugyanúgy, mint a kör előtt. A teljes
integráció (a karusszel CTA-i ténylegesen a primer/Stage felé
irányítsanak) egy KÖVETKEZŐ kör feladata, együtt az
`onboarding_first_win_test.dart` frissítésével (az a fájl akkor kerül
engedélyezett listára). Empirikusan ellenőrizve: a fenti öt, tilos zónában
lévő fájl (`test/app/routing/onboarding_first_win_test.dart`,
`test/app/app_bootstrap_test.dart`, `test/app/bootstrap_failure_app_test.dart`,
`test/app/routing/app_router_test.dart`, `test/core/screen_size_guard_test.dart`
— utóbbi kettő a `screen_size_guard_test.dart` "Onboarding" esetét is
beleértve, ami `ProviderScope` NÉLKÜL példányosítja az `OnboardingScreen`-t)
mind zölden fut ezzel a végleges implementációval (82/82 teszt, lásd a
gate-naplót); a `_currentStep()`/`_advanceStep()` try/catch védelme pontosan
erre a Riverpod-mentes konstrukcióra való.

**Valódi-sértés próba (KÖTELEZŐ, §5).** `first_win_providers.dart`
`isFirstWinSuccess`-ét ideiglenesen feltétel nélkülire (`=> true`)
állítottam. Első futásnál a próba FÉLREVEZETŐ zöldet adott — egy saját
teszt-időzítési hibát találtam közben (`FirstWinStageScreen` widget-tesztje
egyetlen `pump()`-ot használt `fake.emit()` után, ami nem volt elég a
stream-esemény feldolgozásához — MINDKÉT ág `hasAttempt=false`-t
mutatott, függetlenül a sértéstől). Javítottam (2 pump kell), majd
MEGISMÉTELTEM a próbát: a sértéssel az A3 cella helyesen PIROSRA vált
(`Found 1 widget with key 'onboard-first-win-continue'` egy 0.45-ös
olvasatnál — a gyenge jel hamisan sikert mutatott). Visszaállítva,
`flutter test test/features/onboarding/first_win_test.dart` 9/9 zöld.

**Golden-felvétel (A9).** `test/ui/goldens/e13_r16_screens_golden_test.dart`
— 10 PNG (5 képernyő × 2 keret: 412×915 compact portrait és
`textScaler: 2.0`), VALÓDI kapu (nincs `GOLDENS=1` skip). Két valódi
overflow-hibát talált és javítottam:
`OnboardingScreen`'s `_Page` és `PermissionPrimerScreen` most
`SingleChildScrollView`-ban görgethető, nem csordul túl 2.0-s
szövegméretnél. A `LaunchScreen` végtelen `CircularProgressIndicator`-a
miatt `pumpAndSettle` helyett egyetlen `pump()`-ot használ a teszt (a
végtelen animáció sosem "settle"-ödne). A screens `SsDarkTheme.data()`-val
renderelnek (nem puszta `AppTheme.dark()`-kal) — az utóbbi nem regisztrálja
az `SsColorScheme`/`SsTypography` theme extension-öket, amiket az
`SsPermissionState` force-unwrap-el (`!`); ennek hiánya crash-elt az A2
teszteken, amíg nem javítottam.

**Acceptance-mátrix, hol teljesül:**

| # | Bizonyíték | Megjegyzés |
|---|---|---|
| A1 | `permission_primer_test.dart` csoport "A1" + "A1 (app-level)" | teljes (javító kör 1 — F1) |
| A2 | `permission_primer_test.dart` csoport "A2" | teljes |
| A3 | `first_win_test.dart` csoport "A3" + valódi-sértés próba | teljes |
| A4 | `bootstrap_routing_test.dart` csoport "A4" | teljes |
| A5 | `first_win_test.dart` csoport "A5" | teljes |
| A6 | `onboarding_resume_test.dart` csoport "A6" | a karusszel CTA-i valódi bemenettel írják a `permission` checkpointot (javító kör 1 — F1/F2); `firstWin` az enumból törölve, l. §10.1 |
| A7 | `onboarding_resume_test.dart` csoport "A7" + "F3" | teljes, a sorrend pinnelve (javító kör 1 — F3) |
| A8 | `bootstrap_routing_test.dart` csoport "A8" | teljes |
| A9 | `e13_r16_screens_golden_test.dart`, 10 PNG commitolva | teljes |

**Gate.** `tools/round-gate.sh` a brief §7 szerinti pontos öt teszttel:
MINDEN lépés zöld (format, analyze, mind az 5 teszt-fájl, architecture,
secrets, l10n).

---

## 10.1 JAVÍTÓ KÖR 1 — a független review leletei (`docs/reviews/e13-r16-review.md`)

**F1 (BLOCKER, A1) — javítva.** A karusszel mindkét mikrofon-kérő CTA-ja
(`onboardFirstWin` az utolsó oldalon, `onboardStart` a csendes út) MOST a
`OnboardingStep.permission` ellenőrzőponton ÁT megy: `_finish`/`_firstWin`
eltárolja, melyik befejezést kell folytatni (`_afterPermission` mező), majd
`_advanceStep(OnboardingStep.permission)`-t hív — ez rendereli a
`PermissionPrimerScreen`-t. A primer `onGranted`/`onSkipped` hívása
(`_onPermissionResolved`) folytatja az eltárolt befejezést
(`_completeFinish`/`_completeFirstWin`) — best-effort, PONTOSAN úgy, mint a
kör előtti implementáció: egy skip vagy egy elutasítás is befejezi az
onboardingot (a Live újra kéri, ha még nincs megadva). A rendszer-párbeszéd
így SOSEM érhető el a primer nélkül — az A1 mostantól app-szinten is igaz,
nemcsak az izolált `PermissionPrimerScreen` komponens-tesztjén.

A korábbi indoklás (a karusszel CTA-i azért nem köthetők be, mert
`test/app/routing/onboarding_first_win_test.dart` egyetlen settle-ön belüli
befejezést vár) MÉRVE téves volt: az a teszt `fakeAudioOverrides()`-t használ,
aminek az alapértelmezése `granted`, és megadott engedélynél a primer
`_loadCurrentState()`-je egyetlen extra képkocka nélkül, azonnal
`onGranted`-et hív — a primer így ÁTFUTÓ no-op ebben a tesztben, a régi
`pumpAndSettle()` VÁLTOZATLANUL leszalad. **KÖTELEZŐ BIZONYÍTÉK (a fájl a
listán kívül van, MÓDOSÍTVA NEM lett):**

```
$ ~/flutter/bin/flutter test test/app/routing/onboarding_first_win_test.dart
00:00 +0: default first-win survives reactive redirect during delayed persistence
00:02 +1: All tests passed!
```

**Bővített A1 mérce.** `permission_primer_test.dart` új csoportja ("A1
(app-level) — the carousel goes through the primer, never a cold request")
egy `denied` gateway-vel a teljes `OnboardingScreen`-t építi fel, megnyomja a
"Try your first win — 30 seconds" CTA-t, és állítja: `gateway.requestCalls ==
0` marad, és a `PermissionPrimerScreen` (az "Allow" gombjával) van a
képernyőn — tehát a rendszer-dialógushoz vezető `request()` hívás app-szinten
sem futhat le a primer megjelenése előtt.

**F2 (MAJOR, A6/A7) — javítva, szűkítéssel.** Az F1 javítása az
`OnboardingStep.permission`-t valódi bemenettel elérhetővé tette. A
`OnboardingStep.firstWin`-re a két felkínált út közül a **szűkítést**
választottam, mérve: a `.firstWin` állapotot (a `FirstWinStageScreen`
mini Stage-et) a karusszel "Try your first win" CTA-jára kötni azt
jelentené, hogy a primer UTÁN egy MÁSODIK, interaktív képernyő
(pontozott próba, Continue gomb) ékelődne be a befejezés elé — ez a
`test/app/routing/onboarding_first_win_test.dart` egyetlen-settle
elvárását STRUKTURÁLISAN sértené (a Stage nem "átfutó no-op" egy
`granted` gateway-nél, mert egy tényleges mérési próbát vár, amit a
teszt sosem indít el). Mivel ez a fájl a listán kívül van és nem
módosítható, a bekötés mérve NEM lehetséges a jelen körben. Ezért:

- `OnboardingStep` enumból a `firstWin` érték **törölve** —
  `{welcome, permission, done}` (`onboarding_provider.dart:47`). A
  `.firstWin`-et korábban semmilyen valódi bemenet nem produkálta (F1
  mérése), csak egy kézzel beültetett teszt-checkpoint — pontosan az
  "elérhetetlen cél-státusz" hibaosztály, amit F2 tiltott.
  `onboarding_resume_test.dart`-ban a hozzá tartozó widget-teszt
  ("a checkpoint left at the first-win step shows the Stage directly")
  törölve; az "explicit checkpoint wins" teszt `firstWin.index` helyett
  `permission.index`-et pinnel.
- `FirstWinStageScreen`/`first_win_providers.dart`/`first_win_engine.dart`
  VÁLTOZATLANUL a fában maradtak — VALÓDI, teljesen tesztelt komponensek
  (`first_win_test.dart` csoport A3/A5, golden-felvétel), csak nem érhetők
  el a checkpoint-enumon keresztül. A karusszel "Try your first win" CTA-ja
  a primer után továbbra is közvetlenül a `LearnScreen(Lessons.firstWin)`-t
  nyitja meg (a kör előtti byte-azonos navigáció), NEM a mini Stage-et. A
  Stage tényleges bekötése — a "Try first win" CTA a primer UTÁN a Stage-re
  vezessen, a Stage `onContinue`-ja pedig a Learn-lecke helyett/mellett — egy
  KÖVETKEZŐ kör feladata, együtt az `onboarding_first_win_test.dart`
  frissítésével (amikor az a fájl engedélyezett listára kerül).

**F3 (MAJOR, A7) — javítva.** `onboarding_provider.dart:47` doc-commentje
most kimondottan hivatkozik a pinnelt tesztre.
`onboarding_resume_test.dart` új csoportja ("F3 — the persisted step order is
pinned") literálisan rögzíti mind a három név-index párt
(`welcome`=0, `permission`=1, `done`=2); egy jövőbeli beszúrás vagy átrendezés
ezt a cellát pirosra váltja, mielőtt bármelyik eszközön tárolt checkpoint
némán elcsúszna.

**F4 (MINOR) — javítva, explicit teszttel.** A `_currentStep()`/
`_advanceStep()` `on StateError` ága VÁLTOZATLAN maradt — a listán kívüli
`test/core/screen_size_guard_test.dart` "Onboarding" esete `ProviderScope`
NÉLKÜL építi fel az `OnboardingScreen`-t, tehát az "adj a hívó tesztnek
ProviderScope-ot" út nem elérhető ebben a körben. Helyette a degradálás
`test/features/onboarding/onboarding_test.dart`-ban explicit, saját cellával
tesztelt: `ProviderScope` nélkül az `OnboardingScreen` a welcome-karusszelt
mutatja kivétel nélkül (`tester.takeException()` `isNull`), nem csendes
mellékhatásként bizonyítva, mint korábban.

**F5 (NOTE) — érintetlen**, a review indoklása szerint (§0.0/B P4).

**Gate a javító kör után.** `tools/round-gate.sh` a brief §7 szerinti pontos
öt teszttel — MINDEN lépés zöld (format, analyze, mind az 5 teszt-fájl,
architecture, secrets, l10n). A golden-PNG-k VÁLTOZATLANOK (a `.firstWin`
szűkítés és a primer-routing egyike sem érinti a golden-tesztben közvetlenül
példányosított `PermissionPrimerScreen`/`FirstWinStageScreen` widgeteket) —
nem kellett újra felvenni őket.

## 11. Review — a Claude tölti ki
