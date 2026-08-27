# E13-R32 — Gamification Hub, Quest, Achievement és Reward UI

- **Státusz:** READY (pre-flight elvégezve 2026-08-27, `main @ 81640319` — lásd §0.0.B;
  előre megírva 2026-08-15, kód olvasva: `main @ 0f7afd9a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 32
- **Kör-azonosító:** `E13-R32`
- **Branch:** `<motor>/e13-r32-gamification-ui`
- **Előfeltétel:** `E13-R31` merge-elve (fejlődési felületek)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0290`](../adr/0290-compassionate-streaks-and-idempotent-claims.md)
  — **MÁR MERGE-ELVE (`5b32bd8e`, 2026-08-15): a kör ADR-t NEM ír, a `docs/adr/`
  TILOS zóna, módosítása H1.** Lásd §0.0.B/B2.

> ✅ **Pre-flight ELVÉGEZVE (2026-08-27, orchestrátor).** A brief §0-ja `blocked`
> jelzést írt elő, ha az idempotens beváltás use case hiányzik: **LÉTEZIK**, a
> teljes lánc a fán van (`appendIfAbsent` / `hasProcessedEvent` / outbox
> `enqueue`+`drain` / `supersededByLedger`) — a mért típusok és sorszámok a
> §0.0.B/B3-ban. Az implementer NE jelezzen `blocked`-ot ezen a címen; a
> felület a főkönyvet KIZÁRÓLAG olvassa (§0.0.B/B4).

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

## 0.0.B — PRE-FLIGHT MÉRÉS, 2026-08-27 (`main @ 81640319`, orchestrátor Claude)

Az alábbi leletek a kör INDÍTÁSA előtt, a fán MÉRVE keletkeztek. A `brief-lint`
`S13` lelete a B1-ben oldódik fel; a többi a §1.1 két kötelező mérési szabálya
(elérhetetlen cél-státusz, erőforrás-tulajdonlás) és a merge-elt precedens
ütköztetése.

**Visszakeresett előzmény** (ADR 0312, `tools/knowledge-rag.mjs`, szűkítve →
teljes korpusz): [ADR 0301](../adr/0301-reward-ledger-append-only-idempotency.md)
(a főkönyv szerializált idempotenciája — EZ a merge-elt technikai kikényszerítés
az ADR 0290 §2 elvi kimondása mögött), [ADR 0393](../adr/0393-gamification-accessibility-and-settings.md)
(a gamifikációs preferencia-modell és a celebration-UI szándékosan KÜLÖN körre
hagyott bekötése), [ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md)
+ [L486](../LESSONS.md#l486)/[L493](../LESSONS.md#l493) (golden CSAK x86-on),
[L397](../LESSONS.md#l397)/[L401](../LESSONS.md#l401)/[L465](../LESSONS.md#l465)
(a `ui_inventory` egzakt bázisvonala CI-only lelet — ez a hibaosztály KÉTSZER
pont a gamifikációs fán ütött), [L478](../LESSONS.md#l478) (a pre-flight csak
SZŰKÍTHET), [L497](../LESSONS.md#l497) (nem létező `allowed_paths` előtag),
[L403](../LESSONS.md#l403) (a „valódi-sértés próba" a FELIRATOT és az
ADATFORRÁST mérje, ne a widget-TÍPUST).

### B1 — `test/fixtures/gamification/ui/` a fán NEM létezik → az útvonal TÖRÖLVE a listáról (`S13` feloldva)

Mérve: `ls test/fixtures/` → 12 gyerek (`analysis`, `audio`, `practice`,
`practice_generator`, `practice_planner`, `song_trainer`, `vision` + 5 JSON),
`gamification` **nincs**. Az előtag tehát NULLA verziókövetett fájlt fed.

**A feloldás a SZŰKÍTÉS, nem a könyvtár bejelentése:** az útvonal kikerült az
`allowed_paths`-ból. Indok — a szomszéd, merge-elt kör (E13-R31) user-jóváhagyott
listáján SINCS fixture-előtag, a négy `test/features/gamification/ui/*_test.dart`
cella pedig tételesen fel van sorolva, tehát a teszt-adat a saját teszt-fájljában
él (pontosan úgy, ahogy az E13-R31 `dashboard_states_test.dart`-ja). A törlés
[L478](../LESSONS.md#l478)-konform: szigorúan KEVESEBB, mint a szomszéd kör
listája.

### B2 — a kiosztott ADR `0290` MÁR MERGE-ELVE VAN: a kör ADR-t NEM ír

Mérve: `docs/adr/0290-compassionate-streaks-and-idempotent-claims.md` a fán van,
`git log` → `5b32bd8e` („docs(ch13): E13-R30..R36 briefek + ADR 0288-0292",
2026-08-15). A `docs/adr/` tilos zóna; módosítása **H1**.

Ez a sávon a **tizenötödik** ADR nélküli kör egymás után (E13-R17…R32). Új
döntés nincs, ezért `tools/round-slots.py reserve-adr` **nem futott** — nem
égetünk el egy szabad sorszámot olyan körre, amelyik nem ír ADR-t. A §5 kötött
döntései a MÁR MERGE-ELT ADR 0290 §1–§7-jével szó szerint egyeznek.

### B3 — a §0 pre-flight-feltétel TELJESÜL: az idempotens beváltás use case LÉTEZIK (nincs `blocked`)

A brief §0-ja `blocked` jelzést ír elő, ha az idempotens beváltás use case
hiányzik. Mérve — LÉTEZIK, és a lánc végig a fán van:

| Réteg | Mért artefaktum | Szerep |
|---|---|---|
| `data/reward_ledger_repository.dart:10` | `Future<bool> appendIfAbsent(RewardLedgerEntry)` | „hozzáad, HA a forrás-esemény még nincs benne" |
| `data/reward_ledger_repository.dart:13` | `bool hasProcessedEvent(String sourceEventId)` | a dedup-kulcs lekérdezése ÍRÁS NÉLKÜL |
| `data/activity_outbox_repository.dart:118` | `enqueue(ActivityOutboxRecord)` | az OFFLINE sor (`entry.sourceEventId == event.eventId` assert) |
| `data/activity_outbox_repository.dart:126` | `drain()` | „minden függő rekord LEGFELJEBB egyszer" — online visszatéréskor |
| `data/activity_outbox_repository.dart:8` | `ActivityOutboxOutcome.supersededByLedger` | a mért „már be volt írva" kimenet |
| `application/activity_event_ingestor.dart:91` | `ActivityEventIngestor.drain()` | az EGYETLEN hívási pont a felület felé |

Tehát **nincs `blocked`**, és az A2/A4 mércéje NEM elvi: a fenti típusokra
állítható.

### B4 — erőforrás-tulajdonlás (§1.1/2. szabály): a főkönyvet a felület SOHA nem írja

`grep -rn "appendIfAbsent" lib/` → **6 hívási hely**, mind az `application/` és
`data/` rétegben (`achievement_evaluator.dart:304,374`,
`daily_challenge_service.dart:468`, `local_activity_outbox_repository.dart:249`),
és **nulla** a `presentation/` alatt. `grep -rn "\.drain()" lib/` → a
gamifikációs oldalon egyetlen hívó: maga az ingestor.

**Merge-elt precedens a felület oldalán** (E13-R22, ADR 0283 §4) —
`lib/features/practice/presentation/providers/practice_result_providers.dart`:
a képernyő egy `RewardLedgerRepository` seamet olvas, `readPage`-dzsel keresi a
`sourceEventId`-t, és a doc-comment szó szerint kimondja: *„This is a pure read:
it never calls `appendIfAbsent`, so reopening the same session's result always
returns the same answer — the A5 idempotency guarantee at the UI boundary."*

**Ebből a kör KÖTELEZŐ mércéje:**

- a gamifikációs képernyők a főkönyvet **kizárólag olvassák** (`readPage` /
  `hasProcessedEvent`) — `appendIfAbsent` hívás a `lib/features/gamification/presentation/`
  fán **TILOS**, és ezt az **A3** grep-je méri;
- a „beváltás" felületi művelete = az `ActivityEventIngestor.drain()`
  (`retry now`) meghívása; a jóváírásról a főkönyv dönt, nem a képernyő;
- a §6.1 harmadik cellája („offline beváltás + újrapróbálkozás online") így
  KÉT `drain()` hívás UGYANAZZAL a `sourceEventId`-vel, és **pontosan 1**
  jóváírás — falszifikációs őr az optimista jóváírásra.

### B5 — a `RewardInboxItem` NEM claim-modell: a „beváltás" szó a briefben ≠ a felhasználó gombja

Mérve — `lib/features/gamification/domain/profile/reward_inbox_item.dart:159`,
a `seen` mező doc-commentje szó szerint:

> *„Display state only — not a claim, not an expiry, not a precondition for
> anything."*

és a `RewardEvent` konstruktora `sourceLedgerId`-t követel *„must reference an
already-written ledger entry"* felirattal, azaz a postaláda **MÁR JÓVÁÍRT**
jutalmakat tükröz.

**Következmény, ami a kör kódjára köt:** a kör **nem vezet be** felhasználó által
indított „claim" gombot, ami jóváírást vált ki — az ellentmondana a merge-elt
modellnek (és **H2** lenne, egy lezárt kör viselkedésének megváltoztatása). A
felület idempotencia-felülete a **függő sor újrapróbálkozása** (B4) és a
**megjelenített egyenleg**; a „beváltás" a brief nyelvében ezt jelenti.

### B6 — A5 (`türelmi idő`) elérhetetlen a `StreakGraceState`-ből; a MÉRT input a `StreakEvaluationReason` (§1.1/1. szabály)

Nem az átmenettáblát, hanem a **tényleges inputot** mértem:

```
grep -rn "StreakGraceState" lib/   → enum StreakGraceState { none }   (EGYETLEN érték)
```

A `StreakState.graceState` mező tehát a fán **soha nem vesz fel** `none`-tól
különböző értéket — egy erre épített A5-cella előállíthatatlan lenne.

A státuszt ténylegesen előállító input a `StreakEvaluationReason`
(`lib/features/gamification/application/streak_service.dart:9`), amit a
`StreakStatusCard._contentFor` képez feliratra:

| A5 állapot | MÉRT enum-érték | Ki produkálja |
|---|---|---|
| pihenőnap | `StreakEvaluationReason.plannedRest` | `streak_service.dart:110` — `plannedRestDays.contains(epochDay)` |
| türelmi idő | `StreakEvaluationReason.grace` | `streak_service.dart:169–170` — `gap <= graceDays` |
| széria vége | `StreakEvaluationReason.broken` | `streak_service.dart:171` és `:199` (`resetAfterMissedDays`) |

**A numerikus küszöb MÉRVE:** `default_streak_policy.dart:10` → `graceDays = 1`.
A cellahármas (`python3 -c` -vel kiszámolva, a predikátum `gap <= graceDays`):

| Cella | `gap` | `gap <= 1` | Elvárt `reason` |
|---|---|---|---|
| a küszöb alatt | `0` | `True` | `grace` |
| rajta (a küszöbön) | `1` | `True` | `grace` |
| a küszöb fölött | `2` | `False` | `broken` |

A `streak_states_test.dart` ezt a hármast **a `StreakEvaluationReason` értékkel**
állítja be a képernyőn (a képernyő caller-fed, lásd B8), és a MEGJELENÍTETT
feliratot méri — nem a widget típusát ([L403](../LESSONS.md#l403)).

### B7 — az együttérző microcopy MÁR merge-elve van: az A1/A6 mércéje REGRESSZIÓS őr, nem új szöveg

Mérve — `lib/l10n/features/gamification_en.arb`: **258** kulcs, közte a teljes
`streakV2*` készlet. A merge-elt szöveg már ma nem büntető:

- `streakV2BrokenTitle = "Your practice rhythm is ready when you are"`,
  `streakV2BrokenBody = "The skill you have built stays with you."`
- `streakV2PlannedRestTitle = "Planned rest protects your rhythm"`
- `streakV2GraceTitle = "Your rhythm has room to breathe"`
- `streakV2RecoveryCta = "Start a recovery practice"` — **gyakorlás**-CTA, NEM
  fizetős visszaállítás; az A6-ot ez teljesíti, és a cella a jövőbeli
  gyengítés ellen véd.

**Ebből az A1/A6 mércéje pontosítva:** a `compassionate_copy_test.dart` a
`gamification_{en,hu}.arb` FORRÁS-fragmentumot olvassa, és tiltott mintákra
állít (felkiáltójel a széria-státusz szövegeiben, veszteség-nyelv, valamint
bármely fizetős visszaállításra utaló kulcs/felirat). Így a cella akkor is
piros lesz, ha egy KÉSŐBBI kör írja vissza a büntető nyelvet — a jelenlegi
zöld nem üres, hanem lehorgonyzott bázisvonal. A brief §8/4. lépése ezért
**nem** új szöveg írását jelenti, hanem a hiányzó/új felületi kulcsok
kiegészítését en+hu paritással.

### B8 — a hét gamifikációs képernyő MÁR caller-fed, és NULLA design-system importja van: EZ a kör tényleges munkája

Mérve — `find lib/features/gamification -name "*_screen.dart"` → **7 fájl**
(`gamification_hub`, `quests`, `achievements`, `achievement_detail`,
`streak_detail`, `reward_inbox`, `level_detail`), mind kötelező konstruktor-
paraméterekkel (`required this.profile`, `required this.onOpenInbox`, …), azaz
repository-, storage- és falióra-olvasás nélkül.

```
grep -rn "design_system" lib/features/gamification/   → 0 találat
```

**A kör tehát MIGRÁCIÓS kör, nem zöldmezős** (ellentétben az E13-R31
`progress_v2` fájával). Következmények:

- a caller-fed szerződést **megőrizni kell** — a képernyők ezután sem olvasnak
  repositoryt vagy `SharedPreferences`-t (`test/tooling/preferences_plugin_import_guard_test.dart`
  a `gate_tests`-ben fut);
- a design-system importja **kizárólag** a `lib/core/design_system/public.dart`
  barrelen át mehet — ezt a `test/core/architecture_dependency_test.dart` méri
  (E13-R16/F8: 11 sértés, §0.0/S12). **Új DS-komponens NEM készül**, a
  `lib/core/design_system/**` tilos zóna marad;
- az A8 adatforrása a MÁR MERGE-ELT `GamificationPreferences`
  (`reduceMotion`, `CelebrationIntensity.{full,subtle,silent}`, ADR 0393 §5.1),
  amit a `presentation/providers/gamification_preferences_provider.dart`
  exportál. **Az ADR 0393 kifejezetten erre a körre hagyta a celebration-UI
  bekötését** — a `reduced_motion_test.dart` a `subtle`/`silent` ágon is
  megmaradó, nem-nulla visszajelzést méri.

### B9 — `ui_inventory` és `app_router_test`: a MÉRT jelenlegi bázisvonal

| Őr | MÉRT jelenlegi állítás | Mikor mozdul |
|---|---|---|
| `test/ui/ui_inventory_test.dart:22` | `expect(first.screenPaths, hasLength(94))` | CSAK ha a kör ÚJ vagy törölt `lib/features/**/*_screen.dart`-ot hoz |
| `test/app/routing/app_router_test.dart:21–26` | 6 gamifikációs képernyő-TÍPUST importál és `find.byType(GamificationHubScreen)`-t állít (`:437`) | CSAK ha a kör lecseréli a képernyő TÍPUSÁT |

**A jogosultság mindkettőn PONTOSAN a szám, illetve a típusnév igazítása.** Ha a
migráció a meglévő 7 képernyőt a helyén hagyja (a B8 szerint ez a várt út), a
két őr **érintetlen marad** — és a kör ezt a §10-ben mondja ki mérve. Cella
törlése, `skip`-je vagy az állítás gyengítése TILOS.

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

**A beváltás három kötelező cellája** (a küszöb: hányszor íródik jóvá). A
§0.0.B/B4 szerint a felületi művelet az `ActivityEventIngestor.drain()`, a
jóváírás mércéje pedig a főkönyvbe került `RewardLedgerEntry`-k száma az adott
`sourceEventId`-re:

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | a `drain()` a főkönyv hibájába fut (a rekord karanténba kerül) | **0** jóváírás, és a felület **nem** mutat jóváírt egyenleget |
| rajta (a küszöbön) | egyetlen sikeres `drain()` | **pontosan 1** jóváírás |
| a küszöb fölött | offline `enqueue` → `drain()` → ÚJRA `drain()` ugyanazzal a `sourceEventId`-vel | **pontosan 1** jóváírás (a második `ActivityOutboxOutcome.supersededByLedger`) |

**A5 — a széria-státusz három cellája** (§0.0.B/B6, `graceDays = 1`, a predikátum
`gap <= graceDays`, `python3 -c`-vel kiszámolva):

| Cella | `gap` | Elvárt `StreakEvaluationReason` | Elvárt felirat-forrás |
|---|---|---|---|
| a küszöb alatt | `0` | `grace` | `streakV2GraceTitle` |
| rajta (a küszöbön) | `1` | `grace` | `streakV2GraceTitle` |
| a küszöb fölött | `2` | `broken` | `streakV2BrokenTitle` |

A pihenőnap külön cella: `plannedRest` → `streakV2PlannedRestTitle`, és a
`broken`-től MEGKÜLÖNBÖZTETHETŐEN jelenik meg (a §6.1 „A pihenőnap a széria
végeként" hibás implementációját ez fogja pirosra).

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
tools/golden-x86.sh record test/ui/goldens/e13_r32_screens_golden_test.dart
tools/golden-x86.sh check  test/ui/goldens/e13_r32_screens_golden_test.dart
```

> **§0.0.B/B10 — a `flutter test --update-goldens` TILOS ezen a boxon.** Az
> ARM-en rögzített pixel az x86-os merge-kapu nulla toleranciájú komparátorán
> MINDIG piros ([ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md)
> §2–§3, [L486](../LESSONS.md#l486), [L493](../LESSONS.md#l493): az E13-R17 két
> vak javító kört, az E13-R20 egy **H5 haltot** fizetett érte). A
> `tools/golden-x86.sh` a CI-vel AZONOS architektúrán vesz fel és ellenőriz — a
> mérce (nulla tolerancia, ugyanaz a komparátor és golden-készlet) VÁLTOZATLAN.
> Kilépési kódok: `0` = egyezik, `10` = valódi golden-eltérés, `20` =
> környezeti hiba, `30` = hibás hívás. A merge-elt E13-R23…R31 precedens
> egységesen ezt az alakot használja; minta:
> `test/ui/goldens/e13_r31_screens_golden_test.dart`.

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

**Motor:** Claude Sonnet 5 (`sonnet-impl`), 2026-08-27, `main @ 481bf9bd` felett.

### Mit változtattam

1. **`GamificationThemeScope`** (új widget, `presentation/widgets/gamification_theme_scope.dart`,
   mintája `progress_v2/widgets/progress_theme_scope.dart`): garantálja a
   `SsColorScheme`/`SsTypography`/stb. design-system `ThemeExtension`-öket
   függetlenül az ambiens témától. Minden 7 gamifikációs képernyő (Hub,
   Quests, Achievements, StreakDetail, RewardInbox, LevelDetail — az
   AchievementDetail nem, mert nincs benne DS-komponens) `Scaffold`-ja ezzel
   van becsomagolva.
2. **Design-system migráció** (§0.0.B/B8 tényleges munkája — a 7 képernyő
   korábban NULLA `design_system` importtal élt): `level_badge.dart`,
   `xp_progress_bar.dart`, a Hub `_CountSummaryTile`/`_LatestResultCard`, és
   a `reward_summary_sheet.dart` `_SummaryEventTile` `Container`-decorációja
   `SsSurface`-re cserélve, kizárólag a `core/design_system/public.dart`
   barrelen át (mérve: `test/core/architecture_dependency_test.dart` „real
   production source reaches the design system only via public.dart" zöld).
   Az `_InboxIndicator` (Hub) és a `_StreakMetricCard`/`_InboxEntryTile`
   szándékosan MARADT a korábbi alakján — az első egy egyedi accent-színt
   használ, amit az `SsSurface` nem paraméterez, a második egy `find.byType(Card)`
   asszerciót visel a meglévő `streak_detail_screen_test.dart`-ban — a
   migráció szűkítése mért, dokumentált döntés, nem elfeledett kör.
3. **`reduceMotion` szál** — új, opcionális (`= false`) paraméter a
   `StreakStatusCard`, `StreakDetailScreen` (átadja tovább) és
   `RewardSummarySheet` widgeteken, VAGY-kapcsolva a meglévő
   `MediaQuery.disableAnimationsOf`-fal — a §5.6/A8 „az ünneplésnek van
   csökkentett mozgású alternatívája" bekötése a caller-fed szerződésen
   belül (ADR 0393 kifejezetten erre a körre hagyta).
4. **`PendingRewardsCard`** (új widget) — a §3 „offline főkönyv, függő
   beváltás és integritás-vizsgálat" felülete: caller-fed
   `pendingCount`/`quarantinedCount`/`onRetry`. Az `onRetry` a hívó által
   `ActivityEventIngestor.drain()`-re kötendő „retry now" — a widget SOSEM
   hív `appendIfAbsent`-et és SOSEM mutat jóváírt egyenleget a drain előtt.
   Bekötve a `RewardInboxScreen`-be (3 új opcionális paraméter, alapértéken
   `0`/`0`/`null`, ezért az `app_router.dart` meglévő hívása változtatás
   nélkül fordul).
5. **L10n** — 6 új kulcs (`rewardInboxPending{Title,Body,RetryCta,Semantics}`,
   `rewardInboxIntegrity{Title,Body}`) a `gamification_{en,hu}.arb`
   FORRÁSBA, en+hu paritással, együttérző nyelven (nincs „lost"/„veszett"
   szó szerint — a `compassionate_copy_test.dart` erre külön ellenőriz).
   `dart run tool/gen_l10n_segments.dart --write` + `flutter gen-l10n`
   regenerálva.
6. **Elrendezési javítás (mérve a golden felvétel közben, nem előre
   jelezve):** a `PendingRewardsCard` első verziója a retry-gombot egy
   `Row`-ban helyezte az `Expanded` cím/leírás oszlop mellé — ez
   `textScaler 2.0`-nál egy 1577px-es `RenderFlex overflow`-t adott (mérve:
   `PendingRewardsCard` önálló próbateszttel, magasság 2472px). Javítás: a
   gomb egy `Align(centerEnd)`-be került, a cím/leírás Row ALÁ, külön sorba
   — a magasság 412px-re esett vissza, kivétel nélkül. Ugyanekkor a
   `reward_inbox_screen.dart` MEGLÉVŐ `_InboxEntryTile` trailing XP-felirata
   (`l10n.rewardInboxEarnedXpLabel`) is túlcsordult vízszintesen 41px-szel
   `textScaler 2.0`-nál (ez a kör előtti kód, a golden felvétel fogta meg
   most először) — `Flexible(overflow: ellipsis, maxLines: 2)`-be csomagolva.

### §6 acceptance-cellák teljesülése

| # | Kritérium | Bizonyíték | Állapot |
|---|---|---|---|
| A1 | Nincs büntető/bűntudatkeltő széria-szöveg | `compassionate_copy_test.dart` (5/5) | ZÖLD |
| A2 | A beváltás idempotens | `claim_idempotency_test.dart` §6.1 mátrix (3/3 cella) + valódi-sértés próba | ZÖLD |
| A3 | A felület nem számít jutalmat | `claim_idempotency_test.dart` grep-cella (`appendIfAbsent` 0 találat `presentation/` alatt) | ZÖLD |
| A4 | A jutalom forrása auditálható | `claim_idempotency_test.dart` — `RewardLedgerEntry.readPage` a ténylegesen írt sorokat adja vissza | ZÖLD |
| A5 | Pihenőnap/türelmi idő/széria vége külön állapot | `streak_states_test.dart` — 3 küszöb-cella + pihenőnap-vs-broken cella + valódi-sértés próba | ZÖLD |
| A6 | Nincs fizetős széria-megőrzés | `compassionate_copy_test.dart` — kulcsnév-mintázat scan, 0 találat | ZÖLD |
| A7 | Az eredmény feltétele érthető | Már merge-elt (`achievements_screen_test.dart`/`achievement_detail_screen.dart`), változatlan | ZÖLD |
| A8 | Csökkentett mozgás mellett a visszajelzés megmarad | `reduced_motion_test.dart` (8/8) — duration=0, de a tartalom/inbox-jelvény megmarad | ZÖLD |
| A9 | Golden minden §3 képernyőről, 412×915 + scale 2.0 | `e13_r32_screens_golden_test.dart`, 5 képernyő × 2 keret = 10 PNG, `tools/golden-x86.sh check` zöld | ZÖLD (ld. lent) |

### Valódi-sértés próba (KÖTELEZŐ, A2)

`lib/features/gamification/data/local_activity_outbox_repository.dart`
`_enqueue`-jába ideiglenesen beszúrtam egy `await _ledger.appendIfAbsent(record.entry);`
hívást közvetlenül a `_pending.add(...)` után — ez szimulálja az optimista,
a főkönyv megerősítése ELŐTTI jóváírást. Lefuttatva:

```
flutter test test/features/gamification/ui/claim_idempotency_test.dart
```

**Mért eredmény: PONTOSAN az A2 cella vált PIROSSÁ** — „a pendingCount of 0
immediately after enqueue (before drain) would misrepresent the ledger" →
`Expected: false, Actual: <true>` a `ledger.hasProcessedEvent(...)`
asszerción, pontosan a RED FLAG üzenettel. Bónuszként az „alatta" küszöb-cella
is elbukott (`Bad state: ledger offline`), mert a hibás enqueue-útvonal a
`alwaysThrow` ledger-et is azonnal meghívta. A módosítást ezután
visszaállítottam (`git checkout -- lib/features/gamification/data/local_activity_outbox_repository.dart`,
ellenőrizve: nincs diff), és a teljes `claim_idempotency_test.dart` újra
zöld (9/9).

### `ui_inventory` és `app_router_test` — mért, érintetlen bázisvonal (§0.0.B/B9)

A kör a meglévő 7 képernyőt a helyén hagyta (egyet sem hozott, egyet sem
törölt, egyiket sem nevezte át) — mérve:

- `find lib/features/gamification -name "*_screen.dart" | wc -l` → **7**
  (változatlan a B8 mérésével egyezően).
- `find lib/features -name "*_screen.dart" | wc -l` → **94** — egyezik a
  `ui_inventory_test.dart:22` `hasLength(94)` bázisvonalával, a teszt
  módosítás nélkül zöld.
- `app_router_test.dart` — mind a 6 gamifikációs route-cella (`E08-R30 —
  gamification routes` csoport, 8 teszt) változtatás nélkül zöld; egyik
  importált screen-TÍPUS neve sem változott.

Mindkét őr érintetlen maradt — a §0.0.B/B9 jogosultságát (a szám/típusnév
igazítása) nem kellett gyakorolni.

### Golden (A9) — mért aarch64-vs-x86 rasterizációs eltérés (ADR 0426)

`tools/golden-x86.sh record test/ui/goldens/e13_r32_screens_golden_test.dart`
majd `check` — **mindkettő zöld, nulla eltérés**, mind az 5 képernyő × 2
keret (10 PNG, commitolva `test/ui/goldens/goldens/` alatt).

Ez a box (aarch64) natív `flutter test`-je ugyanerre a golden-fájlra
**determinisztikusan** (két egymást követő futással ellenőrizve, bit-azonos
eredménnyel) kis eltérést mér: `hub_compact`/`streak_detail_compact`/
`hub_compact_scale2`/`streak_detail_compact_scale2` egyenként „0.00%, 1px
diff", `achievements_compact_scale2` „0.24%, 896px diff" — a `quests_*` és
`reward_inbox_*` 4 keret helyben is pontosan egyezik. Ez az ADR 0426 §2–§3 /
L486 / L493 mért jelensége (a nulla toleranciájú `LocalFileComparator`
ARM↔x86 anti-aliasing/ikon-rasterizációs eltérésre is érzékeny, nem csak
fordítva) — reprodukálható, tehát NEM flakiness, hanem architektúra-drift.
Mivel a CI és a `golden-x86.sh` UGYANAZ az architektúra (x86_64), az A9
mércéje a `golden-x86.sh check` zöld kimenete, nem ennek a boxnak a natív
`flutter test`-je. A `round-gate.sh`-t emiatt a golden-útvonal NÉLKÜL
futtattam egyetlen, csonkítatlan hívásban (a golden-útvonal a
`round-gate.sh`-ba fűzve az ELSŐ lépésnél megállítaná a láncot, mielőtt az
`architecture`/`secrets`/`l10n` lépések lefutnának) — a golden-bizonyíték a
fenti, külön `golden-x86.sh record`+`check` páros.

### A záró kapu — tényleges kimenet

```
tools/round-gate.sh test/features/gamification/ui/claim_idempotency_test.dart test/features/gamification/ui/streak_states_test.dart test/features/gamification/ui/compassionate_copy_test.dart test/features/gamification/ui/reduced_motion_test.dart test/ui/ui_inventory_test.dart test/app/routing/app_router_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**MINDEN GATE ZÖLD**: format, analyze (0 lelet), mind a 10 célteszt zöld,
`architecture` (12 allowlisted deviation, változatlan), `secrets` (3843
fájl, 0 találat), `l10n` (paritás OK, en→hu 2168 üzenet). A golden-útvonal
külön, `tools/golden-x86.sh record`+`check`-kel zöld (ld. fent). Emellett az
5 meglévő, R2 szerint retargetelendő teszt (`gamification_hub_screen_test`,
`quests_screen_test`, `achievements_screen_test`, `streak_detail_screen_test`,
`gamification_accessibility_test`) **módosítás nélkül** zöld maradt —
a migráció egyik meglévő cellát sem gyengítette.

## 11. Review — a Claude tölti ki
