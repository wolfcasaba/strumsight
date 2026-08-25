# E13-R17 — Today, Practice és Profile hubok

- **Státusz:** READY (pre-flight lefutva 2026-08-25, kód mérve: `main @ b28bb1bf` — §0.0/R6)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 17
- **Kör-azonosító:** `E13-R17`
- **Branch:** `<motor>/e13-r17-today-practice-profile-hubs`
- **Előfeltétel:** `E13-R16` merge-elve (onboarding) + az R08 adaptív navigáció
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — az ADR 0275 (flag mögötti shell) érvényes.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd fel, milyen TÉNYLEGES terv- és
> gamifikációs adatforrás érhető el (Chapter 8/9 rétegei), mert a hubok fake
> repository-interfészre épülnek — ha a valódi forrás hiányzik, a §5.5 szerint
> a fake az elfogadott. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/today/",
  "lib/features/practice_hub/",
  "lib/features/profile_hub/",
  "lib/app/routing/",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/today/today_hub_test.dart",
  "test/features/today/hub_navigation_test.dart",
  "test/features/profile/profile_hub_test.dart",
  "test/app/navigation/",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e13-r17-today-practice-profile-hubs.md",
]
gate_tests = [
  "test/features/today/today_hub_test.dart",
  "test/features/today/hub_navigation_test.dart",
  "test/features/profile/profile_hub_test.dart",
  "test/app/navigation/",
  "test/ui/goldens/e13_r17_screens_golden_test.dart",
  "test/ui/ui_inventory_test.dart",
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

**Kockázat = high, indoklás:** az `lib/app/routing/` belépési pontok és route-őrök (authorization-határ) módosulnak, és a hubok a felhasználó teljes adatfelületére navigálnak.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fájából `lib/features/today/`, `lib/features/practice_hub/`, `lib/features/profile_hub/` **még nem létezik** — a képernyőket ez a kör hozza létre, tehát MINDEN szövege új.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `practice_hub` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek
- `profile_hub` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek
- `today` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek

Az aggregátum a listán MARAD, de **kizárólag generált kimenetként**
(`dart run tool/gen_l10n_segments.dart --write`); a merge-elt precedens
egységesen a forrást ÉS a regenerált aggregátumot is commitolja (E09-R26
`df0ad3dd`, E13-R12 `376b8a1d`, E13-R10 `b11ab2ed`). **Új fragmentum NEM
készül**, ezért a `test/l10n/arb_parity_test.dart` beégetett szegmens-listáját
sem kell bővíteni — a felvett források mind szerepelnek benne.

### R2 — a kör SAJÁT feature-fáján élő, ma zöld widget-tesztek (FELVÉVE)

Ezek közvetlenül a migrálandó képernyőkre állítanak, tehát a migráció után
pirosra váltanának, ami a §0 szerint `blocked` lenne:

  - nincs ilyen.

**A jogosultság szűk:** a teszteket az ÚJ widgetekre kell ráállítani. A lefedett
viselkedést gyengíteni, cellát törölni vagy `skip`-elni **TILOS** — az a mérce
meggyengítése, amit a gate-guard emberhez eszkalál.

### R3 — keresztmetszeti tesztek — a „nincs ilyen" MÉRVE HAMIS volt (javítva: H3 önjavító kör, ADR 0112, 2026-08-25)

> ⚠ **Ez a szakasz revideálva.** Az eredeti szöveg azt állította, hogy a kör
> fájára hivatkozó keresztmetszeti tesztből „nincs ilyen". A H3 halt
> pre-flightja és az önjavító kör SAJÁT reprodukciója ezt megcáfolta.

**A mérés** (izolált klón `/tmp/ss-heal-probe-r17`, `main @ 52df92b3`,
`tools/prepare-flutter-generated.sh` után; a kör MAGVA szimulálva: a shell
HÁROM destination-builderét — `/today`, `/practice`, `/profile` — új
hub-képernyőkre átkötve, a `practiceEnabled` kaput változatlanul hagyva):

```
~/flutter/bin/flutter test test/app/navigation/     # bázis
→ 00:07 +33: All tests passed!

~/flutter/bin/flutter test test/app/navigation/     # a három átkötés után
→ 00:06 +30 -3: Some tests failed.
```

A három piros cella — mindhárom a kör ELKERÜLHETETLEN magja, nem
implementációs mellékhatás:

| # | Fájl | Cella | Mért hiba |
|---|---|---|---|
| 1 | `test/app/navigation/adaptive_scaffold_test.dart` | A1 — *the five destinations render their legacy adapter screens* | `Found 0 widgets with type "ProgressScreen"` (`/today`) |
| 2 | `test/app/navigation/adaptive_scaffold_test.dart` | A1 — *each destination path is registered exactly once: /practice resolves to the shelled adapter…* | `PracticeHubScreen` nem található |
| 3 | `test/app/navigation/tab_state_restoration_test.dart` | *pushing a sub-route, switching tabs, and switching back…* | `PracticeHubScreen` nem található (`:105`, `:134`) |

`test/app/navigation/legacy_route_redirect_test.dart` a MÉRÉS SZERINT **zöld
marad** (a tizenegy legacy redirect célja változatlan) — a listára a
`test/app/navigation/` könyvtár-előtaggal együtt kerül fel, de **hozzá nyúlni
nem kell, és nem is szabad**: ha ez pirosra vált, az valódi regresszió.

**A JOGOSULTSÁG PONTOSAN** a lecserélt destination-adapter TÍPUSÁNAK átírása a
fenti három cellában (`ProgressScreen` → az új Today-hub, `PracticeHubScreen` →
az új Practice-terület-hub, `SettingsScreen` → az új Profile-hub). Minden más
állítás — a primary navigation megléte (`NavigationBar`/`NavigationRail`), a
tizenegy alútvonal-adapter, a tab-visszaállítás mechanikája, a Stage-route
rejtés, a redirect-aciklikusság — **érintetlen marad**. Cella törlése, `skip`-je,
küszöb-lazítása vagy a `find.byType` állítás gyengítése **TILOS**: az a mérce
meggyengítése, amit a gate-guard emberhez eszkalál.

Ami továbbra is a listán KÍVÜL van (`test/core/**`, más feature-ek fái): ha egy
elbukik, az `blocked` jelzés és célzott brief-revízió, nem csendes átírás.

### R4 — a képernyő-leltár őre (H3 önjavító kör, ADR 0112, 2026-08-25)

A `test/ui/ui_inventory_test.dart` **repó-szintű** őr: a `tool/ui_inventory.dart`
a `lib/features/**` fa `_screen.dart` végű fájljait számolja, a teszt pedig
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/practice_hub/`, `lib/features/profile_hub/`, `lib/features/today/` könyvtár-előtag
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

### R5 — a `/practice` destination `practiceEnabled` kapuja MARAD (döntés, H3 önjavító kör, 2026-08-25)

A H3 pre-flight nyitva hagyott egy tervezési kérdést, és az önjavító körnek
kellett eldöntenie. **A döntés: a kör NEM nyúl a kapuhoz.**

**A mai állapot.** A shell `/practice` destinationje az `app_router.dart`-ban
`if (practiceEnabled)` mögött van, és ez az E13-R08 **D15 javító körének
szándékos** döntése volt (review MINOR-1): *„an adaptive-shell navigation flag
must not itself grant access to a distinct product rollout."* Az
`adaptive_scaffold_test.dart` két cellája pinneli is — köztük az A7
(`practiceEngineV2Enabled: false` → `/practice` a `/today`-re esik).

**Miért marad.** A kapu elmozdítása egy LEZÁRT kör mért viselkedésének
megváltoztatása lenne (H2 osztály), nem adapter-csere — a saját reprodukcióm
szerint a kapu érintetlenül hagyásával a kör magja **három** cellát vált
pirosra, a kapu elmozdításával **négyet**. Ez a kör a Ch13 tartalmi migrációja,
nem a shell rollout-politikájának újratárgyalása; a jogosultsága ezért PONTOSAN
az adapter-típus átírása marad.

**A nyitott termék-kérdés (átadva, nem eltemetve).** A
`FeatureFlags.forEnvironment` mérve `practiceEngineV2Enabled: nonProd`, azaz
**production alatt `false`**, miközben az `adaptiveShellEnabled` MINDEN
környezetben `false`. Amikor tehát a shellt élesítik, egy ELSŐDLEGES
nav-destination hiányozhat: a `/practice` a `/today`-re esne vissza. Ez a
Practice **terület-hub** (navigációs felület) és a Practice **Engine V2**
(termék-rollout) összecsúszása. A §3 „képesség-kapui" a hubon BELÜLI
katalógus-belépőkre vonatkoznak — azok ettől függetlenül a kör dolgai.

**Aki eldönti:** a shell-flag bekapcsolását vivő kör (Ch13 zárás, E13-R36) vagy
egy önálló ADR — nem ez a kör és nem az implementer csendes választása. Az
implementer a mai kaput **változatlanul** hagyja; ha a hub tartalma
elérhetetlenné válna emiatt, az **`blocked` jelzés**, nem kerülőút.

### R6 — indítás előtti pre-flight mérés (Claude orchestrátor, 2026-08-25, `main @ b28bb1bf`)

Az R1–R5 állításai **újramérve, mind IGAZ** a mai fán. A mérés parancsai és
kimenetei:

| Állítás | Parancs | Mért eredmény |
|---|---|---|
| R1 — a három hub-könyvtár még nem létezik | `ls -d lib/features/{today,practice_hub,profile_hub}` | mind **MISSING** ✔ |
| R1 — a hub-kulcsok forrása a `base/` szegmens | `ls lib/l10n/features/` | `community, design_system, gamification, onboarding, tuner` — **nincs** `today/practice_hub/profile_hub` fragmentum ✔ |
| R1 — a `arb_parity` szegmens-listát nem kell bővíteni | `grep -n "base/app" test/l10n/arb_parity_test.dart` | `('base/app', …)` már szerepel ✔ |
| R3 — a lecserélendő adapterek | `grep -rn "class \(ProgressScreen\|PracticeHubScreen\|SettingsScreen\)" lib/` | `lib/features/progress/screens/progress_screen.dart:19`, `lib/features/practice/presentation/screens/practice_hub_screen.dart:35`, `lib/features/settings/screens/settings_screen.dart:24` ✔ |
| R4 — a leltár-szám elmozdul | `grep hasLength test/ui/ui_inventory_test.dart` ↔ `find lib/features -name '*_screen.dart' \| wc -l` | `hasLength(81)` ↔ **81** — ma egyezik, tehát MINDEN új `_screen.dart` elmozdítja ✔ |
| brief-lint | `python3 tools/brief-lint.py --brief … --level strict` | **nincs lelet** ✔ |

**Visszakeresés (ADR 0312, szűkítve → majd teljes korpuszon).**
[ADR 0275](../adr/0275-five-area-shell-behind-a-flag.md) §3 (egyetlen legacy
route sem törhet el) és §4 (aciklikus redirect-térkép) · [L485](../LESSONS.md)
(ennek a körnek a saját H3-ja: a navigációs őrök a destination-adapterek
TÍPUSÁT pinnelik) · [L465](../LESSONS.md)/[L483](../LESSONS.md)/[L397](../LESSONS.md)
(a `ui_inventory` egzakt `hasLength` — háromszor mért CI-only bukás) ·
**[L452](../LESSONS.md) — a golden-cellák szempontjából a legfontosabb**:
widget-tesztben a `MediaQuery(data: MediaQueryData(size: …))` **NEM** méretezi a
layoutot, a deklarált 412×915 sosem áll elő. A követendő minta a
`tester.view.physicalSize` + `tester.view.devicePixelRatio` — pontosan ezt
csinálja az előző kör futó precedense (lásd lent).

### R6.1 — A brief kötelező pre-flight kérdése MEGVÁLASZOLVA: milyen TÉNYLEGES terv- és gamifikációs adatforrás érhető el

A fejléc ⚠-blokkja ezt a mérést írta elő. Mérve, a **prezentációs rétegből
tényleges elérhetőség** szerint (nem a réteg-diagram alapján — §1.2):

| Adat | Van-e Riverpod-provider? | Mért bizonyíték |
|---|---|---|
| **Gyakorlási terv (Chapter 8)** | **NINCS** | `grep -rl "Provider(" lib/features/practice_generator/` → **0 találat**. A `TodayPlanController`/`ActivePlanController` létezik (`public.dart`), de egyetlen provider sem szolgáltatja őket a UI-nak. |
| **Gamifikációs profil / questek / jutalmak (Chapter 9)** | **NINCS** (a preferencián kívül) | `find lib/features/gamification -name "*provider*.dart"` → egyetlen fájl: `presentation/providers/gamification_preferences_provider.dart` (`gamificationPreferencesProvider`). A `GamificationProfile`, quest- és reward-adat provider nélküli. |
| Gyakorlási napló + napi cél | **VAN** | `lib/features/progress/public.dart` → `practice_log_provider.dart`, `daily_goal_provider.dart` |
| Széria | **VAN** | `lib/features/streak/public.dart` → `providers/streak_provider.dart` |

**Következmény — az §5.5 feltétele TELJESÜL:** a terv- és a gamifikációs
adat a prezentációs rétegből ma **nem elérhető**, tehát a hubok
**repository-interfészt** használnak, és a **teszt** adja a fake
implementációt. Ez a brief saját, előre kimondott feloldása (§5.5), nem
lista-tágítás.

**Amit ez NEM enged meg:** az A8 változatlanul tiltja a kitalált statisztikát.
Hiányzó adat = üres/„még nincs adat" állapot, **nem** kitalált szám. Ha az
implementer a `progress`/`streak` VALÓS providereit olvassa, azt kizárólag a
más feature-ök `public.dart` barreljén át teheti (import, nem szerkesztés — a
tilos zóna érintetlen marad).

### R6.2 — A4 (mikrofon/kamera) — a TÉNYLEGES erőforrás-birtoklás mérve (§1.2)

A hubok tiltása így falszifikálható konkrétan; ezek a hívások **nem
jelenhetnek meg** a három hub fájában:

| Erőforrás | A mai megszerző (mért hívási lánc) |
|---|---|
| Mikrofon (élő stream) | `liveFrameProvider` — `lib/features/live/providers/live_providers.dart:19` (`StreamProvider.autoDispose`) |
| Mikrofon (felvétel) | `AnalyzeController.startRecording()` — `lib/features/analyze/providers/analyze_providers.dart:162` |
| Kamera | `coordinator.acquire(…)` — `lib/features/vision/application/vision_session_controller.dart:157`, `vision_setup_controller.dart:163` |
| Képernyő-ébrentartás | `WakelockPlus.enable()` — `lib/core/platform/screen_wakelock.dart:21` |

Az A4 `grep`-je ezt a négy aláírást keresi a kör diffjében.

### R6.3 — Az A9 golden-cellák futó precedense a `test/ui/goldens/` fában

A §7 a `test/features/live/chord_timeline_golden_test.dart`-ot nevezi meg
mintaként; az **közvetlenebb és azonos szerződésű** precedens viszont az előző
kör már merge-elt fájlja: **`test/ui/goldens/e13_r16_screens_golden_test.dart`**
(+ 10 commitolt PNG a `test/ui/goldens/goldens/` alatt). Ez ugyanazt a két
keretet adja (412×915 compact és ugyanaz `textScaler: 2.0` mellett), valódi
kapuként (nem `GOLDENS=1`-re kapcsolt opt-in eszközként), és a méretezést az
L452-nek megfelelően `tester.view.physicalSize`-zal állítja be. **Ezt kell
követni** — ez pontosítás, nem új követelmény.

### R6.4 — ADR: ez a kör NEM oszt új ADR-számot

A sor-fájl (`docs/execution/pipeline-queue.tsv:450`) `adr` oszlopa `nincs`, a
brief fejléce ugyanezt mondja (az [ADR 0275](../adr/0275-five-area-shell-behind-a-flag.md)
érvényes), és a §3/§4 a `docs/adr/**`-ot kifejezetten **tilos zónába** teszi.
Precedens ugyanerre a sávra: az E13-R15 szintén `nincs` ADR-rel zárult
`done`-ként. Új ADR írása tehát a brief saját scope-ját sértené — az
orchestrátor nem foglal számot.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az UI-05–UI-07 cél-hubok bevezetése **flag mögött**, a legacy tartalmak
fokozatos összefogásával (SDD Ch13 Kör 17).

## 2. Jelenlegi állapot — mért tények

- Az R08 létrehozta az ötterületes shellt flag mögött, legacy adapterekkel — ez
  a kör tölti meg tartalommal a Today, Practice és Profile területet.
- Az R12 kártyái, az R10 állapotai és az R11 űrlapelemei készen állnak.
- Az ADR 0276 tiltja, hogy prezentációs réteg erőforrást nyisson — a hubokra ez
  külön acceptance-cella (A4).

## 3. Scope

**Benne van:** Today Hub összegzés-központú elrendezés · Practice Hub katalógus
és gyors eszközök **képesség-kapukkal** · Profile Hub helyi / bejelentkezett /
közösség-engedélyezett állapotai · adapter a meglévő Live/Analyze/Learn/Library/
Settings route-okhoz · offline cached, terv nélküli, új felhasználó,
sync-várakozó és letiltott képesség állapotok · compact/medium/expanded
elrendezés.

**NINCS benne (tilos):** Stage / Live / Tuner / Song képernyők migrációja
(Kör 18+) · a shell-flag **bekapcsolása** · mikrofon vagy kamera indítása ·
`lib/core/design_system/**` módosítása · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/today/` | **ÚJ** — Today Hub |
| `lib/features/practice_hub/` | **ÚJ** — Practice Hub |
| `lib/features/profile_hub/` | **ÚJ** — Profile Hub |
| `lib/app/routing/` | a három hub bekötése a shellbe |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — a hub-szövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/**` (3) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r17-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a három hub KIVÉTELÉVEL ·
`lib/core/design_system/**` · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A hubok NEM indítanak mikrofont vagy kamerát

Áttekintő felületek. Az erőforrás a Stage-en indul, felhasználói szándékra
(ADR 0276 folytatása).

**NEM elfogadható gyengítés:** a hangoló előnézetének „élővé tétele" a Practice
Hubon. Az háttérben futó mikrofont jelentene egy listaképernyőn.

### 5.2 A Today EGY egyértelmű elsődleges akciót ad

Az R11 „egy képernyő — egy primary CTA" szabálya. A hub célja az irányítás, nem
a választék bemutatása.

### 5.3 A Profile fiók NÉLKÜL is értelmes

A termék logout állapotban teljesen használható. A Profile ilyenkor a helyi
adatokat és beállításokat mutatja, nem bejelentkezési falat.

**NEM elfogadható gyengítés:** bejelentkezési fal a Profile területen. Az egy
offline-first terméket tesz feltételessé.

### 5.4 A legacy route ELÉRHETŐ marad

Az ADR 0275 §3 szerint: a hubok nem szüntetik meg a régi utakat.

### 5.5 A hiányzó adatforrás FAKE interfésszel pótolt, nem kitalált adattal

Ha a terv- vagy gamifikációs adat még nem elérhető, a hub interfészt használ, és
a **teszt** adja a fake implementációt. A felületen nem jelenik meg kitalált
statisztika.

### 5.6 A letiltott képesség MEGMONDJA, miért

A Vision kártya letiltott állapotban elmagyarázza az okot — nem tűnik el némán,
és nem is kattinthatatlan rejtély.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A Today egyetlen egyértelmű elsődleges akciót ad | `today_hub_test.dart` |
| A2 | A Practice eszközei két érintésen belül elérhetők | `hub_navigation_test.dart` |
| A3 | A Profile fiók nélkül is értelmes tartalmat mutat | `profile_hub_test.dart` |
| A4 | A hubok NEM indítanak mikrofont/kamerát | `today_hub_test.dart` + `grep` a diffben |
| A5 | A legacy route-ok elérhetők maradnak | `hub_navigation_test.dart` |
| A6 | Offline állapotban a cached tartalom látszik (ADR 0277) | `today_hub_test.dart` |
| A7 | A letiltott képesség kártyája megmondja az okot | ugyanott |
| A8 | Nincs kitalált statisztika hiányzó adatforrás mellett | `today_hub_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r17_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Három egyenrangú primary gomb a Todayen | **A1** |
| A hangoló élő előnézete a Practice Hubon | **A4** |
| Bejelentkezési fal a Profile-on | **A3** |
| A legacy route törlése | **A5** |
| Offline → üres képernyő | A6 |
| A Vision kártya némán eltűnik | A7 |
| Nulla helyett kitalált „7 napos széria" | **A8** |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A gyakorlási eszköz elérési mélységének három kötelező cellája** (a küszöb:
**2 érintés**):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | 1 érintés (közvetlen gyors eszköz) | elfogadva |
| rajta (a küszöbön) | **2 érintés** | **elfogadva** (a határ inkluzív) |
| a küszöb fölött | 3 érintés | **elutasítva** — a cella PIROS |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** tedd a metronómot egy
harmadik szint mögé → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/today/today_hub_test.dart test/features/today/hub_navigation_test.dart test/features/profile/profile_hub_test.dart test/app/navigation/ test/ui/goldens/e13_r17_screens_golden_test.dart test/ui/ui_inventory_test.dart
```

A `test/app/navigation/` a §0.0/R3 szerinti shell-destination őr: a három
átírandó cellán kívül minden állítása **zölden** kell maradjon — a
`legacy_route_redirect_test.dart` érintetlenül.

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r17_screens_golden_test.dart
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

1. A három hub repository-interfésze (fake implementáció a tesztben).
2. Today Hub — összegzés + EGY elsődleges akció.
3. Practice Hub — katalógus, gyors eszközök, képesség-kapuk + a mélység-cella.
4. Profile Hub — helyi / bejelentkezett / közösségi állapot.
5. Legacy adapterek + route-elérhetőség cellája.
6. Offline, terv nélküli, új felhasználó, sync-várakozó állapotok.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A kitalált statisztika.** Üres állapotban „szebb" egy nullánál, és
  hazugság — a projekt legveszélyesebb hibaosztálya (A8).
- **A bejelentkezési fal.** Kézenfekvő a Profile-on, és megtöri az
  offline-first ígéretet (A3).
- **Az élő előnézet.** Látványos, és háttérben futó mikrofont jelent egy
  áttekintő képernyőn (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
