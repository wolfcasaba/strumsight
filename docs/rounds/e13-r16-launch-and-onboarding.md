# E13-R16 — Launch, recovery és onboarding migráció

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 6adea220`)
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
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
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
| `lib/l10n/app_{en,hu}.arb` | a primer és a helyreállítás szövegei |
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
