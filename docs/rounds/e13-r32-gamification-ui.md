# E13-R32 — Gamification Hub, Quest, Achievement és Reward UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 0f7afd9a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 32
- **Kör-azonosító:** `E13-R32`
- **Branch:** `<motor>/e13-r32-gamification-ui`
- **Előfeltétel:** `E13-R31` merge-elve (fejlődési felületek)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0290`](../adr/0290-compassionate-streaks-and-idempotent-claims.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES
> gamifikációs főkönyv (ledger) use case-ét — a §5.2 kimondja, hogy a felület
> nem számít jutalmat. Ha az idempotens beváltás use case hiányzik, `blocked`
> jelzéssel állj meg. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/",
  "lib/l10n/features/gamification_en.arb",
  "lib/l10n/features/gamification_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/gamification/presentation/achievements_screen_test.dart",
  "test/features/gamification/presentation/gamification_accessibility_test.dart",
  "test/features/gamification/presentation/gamification_hub_screen_test.dart",
  "test/features/gamification/presentation/quests_screen_test.dart",
  "test/features/gamification/presentation/streak_detail_screen_test.dart",
  "test/features/gamification/ui/claim_idempotency_test.dart",
  "test/features/gamification/ui/streak_states_test.dart",
  "test/features/gamification/ui/compassionate_copy_test.dart",
  "test/features/gamification/ui/reduced_motion_test.dart",
  "test/fixtures/gamification/ui/",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "test/app/routing/app_router_test.dart",
  "docs/rounds/e13-r32-gamification-ui.md",
]
gate_tests = [
  "test/features/gamification/ui/claim_idempotency_test.dart",
  "test/features/gamification/ui/streak_states_test.dart",
  "test/features/gamification/ui/compassionate_copy_test.dart",
  "test/features/gamification/ui/reduced_motion_test.dart",
  "test/ui/goldens/e13_r32_screens_golden_test.dart",
  "test/ui/ui_inventory_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/core/architecture_dependency_test.dart",
  "test/tooling/dio_factory_guard_test.dart",
  "test/tooling/preferences_plugin_import_guard_test.dart",
  "test/tooling/route_literal_guard_test.dart",
]
native_gate = false
```

## 0.0 BRIEF-REVÍZIÓ — 2026-08-25, batch pre-flight (E13-R17…R35)

A brief 2026-08-15-én készült; ez a pre-flight `main @ 41fbd40` ellen mért.
**Visszakeresett előzmény:** [L478](../LESSONS.md) (a pre-flight csak szűkíthet;
a tágítás H3), [ADR 0307 §4](../adr/0307-parallel-round-execution.md) (a
`lib/l10n/app_*.arb` GENERÁLT aggregátum, a forrás a `base/` és a
`features/` szegmens), [L481](../LESSONS.md) (a lánc remote konténerből nem
indítható). A hibaosztályt a **teljes Ch13 sávon** mérte ki egy batch-vizsgálat:
az R17–R35 MIND a generált aggregátumot sorolta fel forrásként (`agg=2, frag=0`).

**Kockázat = high, indoklás:** a gamifikációs felület a felhasználó teljesítmény-adatára épülő, összehasonlító tartalmat jelenít meg.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fája ma **228** l10n-kulcsot használ, és mind feloldható: `gamification` = 227 kulcs, `app` = 1 kulcs.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `gamification` → a MÁR LÉTEZŐ `features/gamification_*.arb` fragmentum

Az aggregátum a listán MARAD, de **kizárólag generált kimenetként**
(`dart run tool/gen_l10n_segments.dart --write`); a merge-elt precedens
egységesen a forrást ÉS a regenerált aggregátumot is commitolja (E09-R26
`df0ad3dd`, E13-R12 `376b8a1d`, E13-R10 `b11ab2ed`). **Új fragmentum NEM
készül**, ezért a `test/l10n/arb_parity_test.dart` beégetett szegmens-listáját
sem kell bővíteni — a felvett források mind szerepelnek benne.

### R2 — a kör SAJÁT feature-fáján élő, ma zöld widget-tesztek (FELVÉVE)

Ezek közvetlenül a migrálandó képernyőkre állítanak, tehát a migráció után
pirosra váltanának, ami a §0 szerint `blocked` lenne:

  - `test/features/gamification/presentation/achievements_screen_test.dart`
  - `test/features/gamification/presentation/gamification_accessibility_test.dart`
  - `test/features/gamification/presentation/gamification_hub_screen_test.dart`
  - `test/features/gamification/presentation/quests_screen_test.dart`
  - `test/features/gamification/presentation/streak_detail_screen_test.dart`

**A jogosultság szűk:** a teszteket az ÚJ widgetekre kell ráállítani. A lefedett
viselkedést gyengíteni, cellát törölni vagy `skip`-elni **TILOS** — az a mérce
meggyengítése, amit a gate-guard emberhez eszkalál.

### R3 — keresztmetszeti tesztek (NEM kerültek listára — figyelmeztetés)

A kör fájára hivatkozó további widget-tesztek közös infrastruktúrán élnek
(`test/app/**`, `test/core/**`, más feature-ek fái) — 1 ilyen fájl van. Ezeket a kör
**NEM** szerkesztheti: ha egy elbukik, az `blocked` jelzés és célzott
brief-revízió, nem csendes átírás. A körbe húzásuk a scope-fegyelem feladása
lenne.

### R4 — a képernyő-leltár őre (H3 önjavító kör, ADR 0112, 2026-08-25)

A `test/ui/ui_inventory_test.dart` **repó-szintű** őr: a `tool/ui_inventory.dart`
a `lib/features/**` fa `_screen.dart` végű fájljait számolja, a teszt pedig
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/gamification/` könyvtár-előtag
alá képernyőt hoz vagy hozhat, tehát a szám **elmozdul**, és az exact-SHA Full
Gate pirosra vált.

A `test/ui/goldens/` előtag ezt **nem** fedi (az a `test/ui/` fának csak az egyik
ága), a leltárteszt utólagos felvétele pedig tágítás, azaz **H3** — az
orchestrátor a pre-flightban nem oldhatja fel ([L478](../LESSONS.md)). Ezért
kerül a listára MOST, az önjavító körben.

**MÉRVE (E13-R16, 2026-08-25):** pontosan ez a hiány állította meg a sáv első
migrációs körét — [full-gate 32867296946](https://github.com/wolfcasaba/strumsight/actions/runs/32867296946)
6366 passed / 2 failed, `hasLength(79)` a tényleges 81 ellen. A `9acd14e5`
sáv-szintű batch pre-flight azért nem találta meg, mert a `tools/brief-lint.py`
`S9` szabálya csak LITERÁLIS `*_screen.dart` útvonalat nézett, KÖNYVTÁR-előtagot
nem — a predikátumot ugyanez az önjavító kör javította, regressziós teszttel
([L483](../LESSONS.md)).

**A jogosultság PONTOSAN a szám emelése** a kör tényleges képernyőszámára; a
leltárteszt minden más állítása érintetlen marad. Kerülőút (képernyő-átnevezés
vagy a `tool/ui_inventory.dart` szabályának lazítása) **TILOS** — az a mérce
meghamisítása.

### S11 — az örökség-képernyőt PINNELŐ, listán kívüli tesztek (2026-08-25)

A kör lecserél legalább egy MEGLÉVŐ képernyőt, amelynek a TÍPUSÁT a brief
listáján kívül élő teszt pinneli. Mérve a `tools/brief-lint.py` `S11`
szabályával (import ÉS típusnév együtt), a `main @ b28bb1bf` fán:

- `test/app/routing/app_router_test.dart`

Ez pontosan az a halt-osztály, amelyik az **E13-R16/F9**-et (full-gate
32867296946, `hasLength(79)` vs 81) és az **E13-R17/H3**-at (`flutter test
test/app/navigation/` +33 → +30 -3) megállította: az őr a listán kívül él, a
felvétele az orchestrátornak TÁGÍTÁS ([L478](../LESSONS.md)), tehát a kör H3-ban
áll meg, mielőtt egyetlen sor kód megszületne. A fenti fájlok ezért mostantól
az `allowed_paths`-on ÉS a `gate_tests`-en is szerepelnek.

**A jogosultság PONTOSAN a lecserélt képernyő típusának átírása.** Cella
törlése, `skip`-je, küszöb-lazítása vagy az állítás gyengítése TILOS — az a
mérce meghamisítása. Ha a kör bizonyíthatóan nem cseréli le a képernyőt, a kör
pre-flightja mondja ki ezt a mérést, és hagyja a cellákat érintetlenül.

### S12 — a fa-szintű őrök a kör LOKÁLIS kapujába (2026-08-25)

A kör lokális kapuja eddig KIZÁRÓLAG a saját céltesztjeit futtatta, ezért a
teljes `lib/` fát pásztázó őrök leletei szerkezetileg csak a ~17 perces
exact-SHA Full Gate-en jelentek meg — javító kör árán. MÉRT eset: **E13-R16/F8**
(`docs/reviews/e13-r16-review.md`), ahol mind a három új képernyő közvetlenül
importálta a `design_system/foundations/**`-ot a `public.dart` helyett — **11
sértés** —, és a review szó szerint rögzíti, miért nem fogta a célzott gate:
a `tools/round-gate.sh` `architecture` lépése a `tool/check_architecture.dart`-ot
futtatja, ami egy MÁSIK, tágabb szabálykészlet; a design-system-határ mércéje
egy külön `test/core/` teszt, amit csak a teljes suite futtat.

Ezért ez a kör mostantól a `gate_tests`-ben futtatja ezeket az őröket:

- `test/core/architecture_dependency_test.dart`
- `test/tooling/dio_factory_guard_test.dart`
- `test/tooling/preferences_plugin_import_guard_test.dart`
- `test/tooling/route_literal_guard_test.dart`

A kiválasztás MÉRT, nem vaktában: a globális őrök a `Directory('lib')` teljes
fát pásztázzák (bármelyik kör diffje elmozdíthatja őket), a szűkített őrök pedig
csak akkor kerülnek fel, ha a kör `allowed_paths`-a metszi a pásztázott
gyökeret.

**Ezek az őrök NEM kerülnek az `allowed_paths`-ra** — és ez szándékos: a kör
futtatja, de NEM szerkesztheti őket, tehát a lelet javítása kizárólag a kör
SAJÁT kódjában történhet. Cella törlése, `skip`-je vagy küszöb-lazítása így
gépileg kizárt, a mérce pedig tiszta erősítést kap.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az UI-51–UI-52 **együttérző**, idempotens jutalmazási felülete
(SDD Ch13 Kör 32).

## 2. Jelenlegi állapot — mért tények

- Az R22 ADR 0283 §4 kimondta: a jutalom a főkönyvből jön, nem UI-számításból.
  Ez a kör ugyanazt a szabályt viszi végig a gamifikációs felületen.
- Az R06 ADR-je szerint a csökkentett mozgás **csökkent, nem kikapcsolt**
  visszajelzés — az ünneplésre is.
- A széria (streak) a legkönnyebben büntetővé váló mechanizmus.

## 3. Scope

**Benne van:** a gamifikációs hub szint, XP, széria, küldetés és jutalom-összegzés
elrendezése · a részletes Küldetések / Eredmények / Bejövő fülek · pihenőnap,
türelmi idő, széria vége, offline főkönyv, függő beváltás és integritás-vizsgálat
állapotok · a beváltás **idempotens use case-hez** kötve · csökkentett mozgású
ünneplés és animáció nélküli alternatíva · együttérző microcopy és lokalizáció.

**NINCS benne (tilos):** a jutalom UI-oldali **számítása** · a főkönyv vagy a
küldetés-logika módosítása · fizetős széria-megőrzés bevezetése · más
képernyők · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/` | a hub és a fülek |
| `lib/l10n/features/gamification_{en,hu}.arb` | **FORRÁS** — az együttérző microcopy (`gamification` MÁR migrált feature) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/…` (5 meglévő teszt) | ma zöld, a migrált képernyőkre állítandó — lásd §0.0 R2 |
| `test/features/gamification/ui/*_test.dart` (4) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r32-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a `gamification/` KIVÉTELÉVEL ·
`lib/core/design_system/**` · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0290)

### 5.1 NINCS büntető széria-nyelv

A megszakadt széria tény, nem kudarc. A szöveg nem hibáztat, nem kelt bűntudatot
és nem sürget — a pihenőnap és a türelmi idő normális állapot.

**NEM elfogadható gyengítés:** „Elvesztetted a 30 napos szériádat!" felkiáltó
jellel. Ez a mechanizmus szorongást termel, nem gyakorlást.

### 5.2 A beváltás IDEMPOTENS, és a felület NEM számít jutalmat

A UI a főkönyv use case-ét hívja. Offline állapotban a beváltás sorba kerül, és
a hálózat visszatérésekor **nem duplikál** (ADR 0283 §4).

**NEM elfogadható gyengítés:** optimista jóváírás a felületen, a főkönyv
megerősítése nélkül. A projekt már mérte ezt a hibaosztályt: a `try/catch`-be
fojtott írás néma eltérést hagy a felület és az adat között.

### 5.3 A jutalom FORRÁSA auditálható

A felhasználó megnézheti, mit miért kapott.

### 5.4 NINCS fizetős megőrzés (pay-to-preserve)

A szériát nem lehet pénzért visszavásárolni. Az a szorongásra épülő monetizáció.

### 5.5 Az eredmény FELTÉTELE érthető

Minden eredményhez világos, teljesíthető feltétel tartozik — nem rejtett
kritérium.

### 5.6 Az ünneplésnek van csökkentett mozgású alternatívája

Az ADR (E13-R06) szabálya: a visszajelzés megmarad, csak más modalitásban.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Nincs büntető vagy bűntudatkeltő széria-szöveg (en + hu) | `compassionate_copy_test.dart` |
| A2 | A beváltás idempotens — offline sorból sem duplikál | `claim_idempotency_test.dart` |
| A3 | A felület nem számít jutalmat (use case-t hív) | `grep` a diffben |
| A4 | A jutalom forrása auditálható | `claim_idempotency_test.dart` |
| A5 | Pihenőnap / türelmi idő / széria vége külön, nem büntető állapot | `streak_states_test.dart` |
| A6 | Nincs fizetős széria-megőrzés | `compassionate_copy_test.dart` |
| A7 | Az eredmény feltétele megjelenik és érthető | ugyanott |
| A8 | Csökkentett mozgás mellett az ünneplés visszajelzése megmarad | `reduced_motion_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r32_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| „Elvesztetted a szériádat!" | **A1** |
| Optimista jóváírás a főkönyv megerősítése előtt | **A2** |
| A jutalom a képernyőn számolva | **A3** |
| A pihenőnap a széria végeként | A5 |
| Fizetős visszaállítás felajánlva | **A6** |
| Csökkentett mozgás → az ünneplés eltűnik | **A8** |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A beváltás három kötelező cellája** (a küszöb: hányszor íródik jóvá):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | a beváltás megszakad | **0** jóváírás |
| rajta (a küszöbön) | egyszeri beváltás | **pontosan 1** jóváírás |
| a küszöb fölött | offline beváltás + újrapróbálkozás online | **pontosan 1** jóváírás |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** írd jóvá a jutalmat
optimista módon a főkönyv megerősítése előtt → az **A2** cellának PIROSNAK kell
lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/ui/claim_idempotency_test.dart test/features/gamification/ui/streak_states_test.dart test/features/gamification/ui/compassionate_copy_test.dart test/features/gamification/ui/reduced_motion_test.dart test/ui/goldens/e13_r32_screens_golden_test.dart test/ui/ui_inventory_test.dart test/app/routing/app_router_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r32_screens_golden_test.dart
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

1. A hub elrendezése (szint, XP, széria, küldetés, jutalom-összegzés).
2. A beváltás use case-hez kötve + a három idempotencia-cella.
3. A széria-állapotok: pihenőnap, türelmi idő, vége — nem büntető nyelven.
4. Az együttérző microcopy en + hu, a fizetős megőrzés kizárásával.
5. Az eredmények feltételeinek megjelenítése és a jutalom-forrás auditja.
6. Csökkentett mozgású ünneplés-alternatíva.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az optimista jóváírás.** Gyorsabbnak hat, és néma eltérést hagy a felület
  meg a főkönyv között (A2).
- **A büntető széria-nyelv.** Rövid távon növeli a visszatérést, hosszú távon
  szorongást termel — és a terméket elhagyják miatta (A1).
- **A fizetős visszaállítás.** Bevételi ötletnek látszik, és a szorongásra
  épít (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
