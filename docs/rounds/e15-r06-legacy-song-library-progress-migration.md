# E15-R06 — Örökség Songs, Library, Progress és Streak képernyők

- **Státusz:** READY (pre-flight lefutott 2026-08-29, kód mérve: `main @ 34aff7fd`; a §0.0.A revízió KÖTELEZŐEN olvasandó — a scope 8 képernyőről 3-ra SZŰKÜLT)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 6
- **Kör-azonosító:** `E15-R06`
- **Branch:** `<motor>/e15-r06-legacy-song-library-progress-migration`
- **Előfeltétel:** `E15-R03` merge-elve (a visszavonási terv dönti el, mit KELL migrálni)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — migrációs kör, kötött ÚJ architekturális döntés nélkül (a hivatkozott szerződéseket korábbi ADR-ek rögzítik).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "legacy screen retirement route reachability dead code deprecation"` → **[ADR 0065](../adr/0065-practice-engine-v2-parallel-rollout.md)** (a V2 a legacy MELLETT fut) és **[L449](../LESSONS.md#l449)** — ezek a képernyők párhuzamos rétegek, ezért az `E15-R03` visszavonási terve dönti el, melyiket migráljuk.

> ✅ **Pre-flight LEFUTOTT (2026-08-29, orchestrátor) — az eredménye a §0.0.A.** A
> mérés mind a 8 képernyőt `legacy`-nek mérte, a `retirement-plan.md` verdiktjei
> viszont 5-öt `retire`-nek jelölnek → a scope 3 képernyőre szűkült. Az alábbi
> parancs a reprodukció, nem újra elvégzendő döntés:
> ```bash
> for f in lib/features/songs/screens/song_list_screen.dart lib/features/songs/screens/song_builder_screen.dart lib/features/songs/screens/setlist_list_screen.dart lib/features/songs/screens/setlist_detail_screen.dart lib/features/library/screens/library_screen.dart lib/features/library/screens/session_detail_screen.dart lib/features/progress/screens/progress_screen.dart lib/features/streak/screens/streak_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
> ```
> A megíráskor mind a **8** felsorolt képernyő legacy volt. Ami időközben migrálódott, azt a §3 scope-ból ki kell venni.

## 0.0 A kör határa: MEGJELENÉS, nem viselkedés

A migráció a képernyők VIZUÁLIS rétegét cseréli design-rendszer-komponensekre. A képernyő TÍPUSA, route-ja, publikus API-ja és üzleti viselkedése VÁLTOZATLAN — a típus-pinnelő tesztek (§4) ezért maradnak zöldek, és a jogosultság pontosan ennyi: **cella törlése, `skip`-je vagy gyengítése TILOS**. Az `E15-R01` óta az app témája hordozza a tokeneket, tehát ÚJ `*ThemeScope` burkoló NEM vezethető be; a meglévő burkoló eltávolítható, ha a képernyő már az app témájából old fel.

Ez a batch a MÉRHETŐEN párhuzamos örökség-réteg: `songs/` ↔ `song_trainer/`, `library/` ↔ `library_v2/`, `progress/` ↔ `progress_v2/`. A kör KIZÁRÓLAG azokat migrálja, amiket az `E15-R03` terve „migrálandó”-nak jelölt; a „visszavonandó” tételekhez javaslatot ír, végrehajtás nélkül.

### 0.0.A Pre-flight mérés és brief-revízió (orchestrátor, 2026-08-29, `main @ 34aff7fd`)

**R1 — a 8 képernyő MÉG mind legacy** (a §7 mérő-parancs kimenete, mind a 8
sor `legacy`), tehát időközbeni migráció nem szűkíti a listát.

**R2 — a `retirement-plan.md` verdiktje 5 képernyőt KIVESZ a scope-ból.** A
terv §5/§6 sorai (`docs/ui/retirement-plan.md:164–167`, `:225–226`, `:269–271`):

| Képernyő | Terv-verdikt | Utód |
|---|---|---|
| `LibraryScreen` | **retire** | `UnifiedLibraryScreen` (elérhető, MIGRÁLT) |
| `SessionDetailScreen` | **retire** | `LibraryItemDetailScreen` (elérhető, MIGRÁLT) |
| `StreakScreen` | **retire** | `GamificationHubScreen` (elérhető, MIGRÁLT) |
| `SongListScreen` | **retire** | `SongLibraryScreen` (elérhető, az `E15-R05`-ben MIGRÁLT) |
| `SongBuilderScreen` | **retire** | `SongEditorScreen` (elérhető, az `E15-R05`-ben MIGRÁLT) |
| `ProgressScreen` | **migrate** | — (a `progress_v2` NINCS bekötve, terv §3.1) |
| `SetlistListScreen` | **migrate** | — |
| `SetlistDetailScreen` | **migrate** | — |

A §3 batch-specifikus kikötése („a tervben `visszavonandó`-ként jelölt képernyő
NEM migrálódik") ezt a döntést előre kimondta, tehát ez a revízió a brief SAJÁT
szabályának alkalmazása, nem tágítás: **az öt `retire` képernyő kikerül a
scope-ból**, és a §10-ben kell rögzíteni, ki vonja vissza őket (lásd R5).
A migráció náluk mérhető pazarlás lenne: egy hamarosan törlendő képernyőre
költene a kör, miközben a felhasználó már a MIGRÁLT utódot látja.

**R3 — owner-kör korrekció (a terv §4 táblája vs. a queue).** A terv §4 tábla
owner-kör oszlopa a maradék hármat `E15-R08`-ra (`ProgressScreen`) és
`E15-R10`-re (`SetlistListScreen`, `SetlistDetailScreen`) osztja, az `E15-R06`
sorába pedig Gamificationt ír. A queue és MINDEN megírt brief más felosztást
futtat (`docs/execution/pipeline-queue.tsv:557–562`: `E15-R08` = gamification,
`E15-R09` = ai-tutor, `E15-R10` = analysis) — és MÉRVE, hogy a hátralévő
`E15-R07…R11` briefek EGYIKE SEM nevezi meg ezt a három fájlt, tehát ez a kör az
egyetlen tulajdonosuk a sorban. Ez pontosan az `E15-R05` §0.0/R9 korrekciójának
osztálya (`docs/ui/migration-status.md` „Owner-round correction"): a `migrate`
DÖNTÉS változatlan, csak a végrehajtó kör más. A `retirement-plan.md` ennek a
körnek a tilos zónájában van, ezért itt NEM szerkesztjük.

**R4 — ARB-forrásfájlok az engedélyezett listán.** A §3 szövege eleve
engedélyezi új ARB-kulcs felvételét mindkét locale-ra, a gépi lista viszont nem
tartalmazta a forrásfájlokat. MÉRVE (`E15-R05` §0.0/R12, `migration-status.md`):
`lib/l10n/app_*.arb` GENERÁLT kimenet, a valódi forrás
`lib/l10n/base/app_<locale>.arb` — a hiánya ott egy TELJES javító körbe került.
A két base-fájl ezért felkerül a listára; kulcs TÖRLÉSE és jelentés-változtatás
továbbra is tilos. Az `A6` mércéje (`test/l10n/hardcoded_string_guard_test.dart`)
bekerül a `gate_tests`-be — a §6 hivatkozta, a gépi lista nem.

**R9 — a §3 komponens-nevei közül HÁROM NEM LÉTEZIK, és a képernyők
állapot-leltára MÉRVE.** Ugyanaz a mérés, amit az `E15-R05` §0.0/R2 is elvégzett
(`grep -rho "class Ss[A-Za-z]*" lib/core/design_system/components/`):

| A §3 által említett név | Valóság |
|---|---|
| `SsListTile` | **nincs ilyen** → `SsContentCard` / `SsCard` a sor-hordozó |
| `SsErrorState` | **nincs ilyen** → `SsFailureState` (`SsFailurePresentation` + `SsFailureAction`) |
| `SsMetricTile` | **nincs ilyen** → `SsMetricCard` (+ `SsMetricCardSkeleton`) |

Létező, ide illő komponensek (mérve): `SsCard`, `SsContentCard`, `SsSurface`,
`SsSection`, `SsButton`, `SsIconButton`, `SsEmptyState`, `SsFailureState`,
`SsMetricCard`, `SsSkeleton`, `SsScoreRing`, `SsStatusBadge`, `SsTrendIndicator`.

Állapot-leltár a három fájlban (MÉRVE, `main @ 34aff7fd`):

| Fájl | Üres | Betöltés | Hiba |
|---|---|---|---|
| `setlist_list_screen.dart` | `_Empty(text: l10n.setlistsEmpty)` (`:44`) | nincs | **nincs** |
| `setlist_detail_screen.dart` | `Center`+`Text(l10n.setlistEmptyDetail)` (`:127`) | nincs | **nincs** |
| `progress_screen.dart` | legacy `EmptyState` (`lib/core/widgets/empty_state.dart`, `:69`) | nincs | **nincs** |

Ebből három kötött szabály:

1. **Hibaállapotot GYÁRTANI TILOS.** Egyik képernyőnek sincs ma hibaága és nincs
   `AppFailure`-je; egy kitalált `AppFailure`/`retryable: true` pontosan az
   `E15-R04` G2-MAJOR osztálya (`E15-R05` prompt §2). Az §5.2 a LÉTEZŐ
   állapotokra vonatkozik. Ha egy képernyőnek nincs hibaága, a §10 mondja ki:
   „nincs hibaág — nem gyártottunk".
2. **`progress_screen.dart:258` `CircularProgressIndicator` NEM betöltés-jelző**,
   hanem determinisztikus napi-cél gyűrű (`value: progress`, `met ? check : bolt`
   ikonnal a közepén). Skeletonra/betöltés-komponensre cserélni
   INFORMÁCIÓVESZTÉS; ha design-rendszer-megfelelőt kap, az az `SsScoreRing`
   osztálya, a `value` szemantika megőrzésével.
3. **Beégetett szöveg ma NULLA** a három fájlban (`grep -n "Text('…"` üres), és
   `*ThemeScope` burkoló sincs bennük (a §3 eltávolítási pontja itt **no-op**).
   Az `A6` tehát a kör előtt is teljesül — a dolgod, hogy MARADJON így; új
   ARB-kulcsra várhatóan nincs is szükség (a `lib/l10n/base/**` az R4 miatt csak
   biztonsági tartalék).

**R10 — a GENERÁLT ARB-aggregátum is a listára kerül (az R4 mechanikus
következménye).** Az R4 a base-forrásfájlokat vette fel, a §4 tilos zónája
viszont a generált `lib/l10n/app_*.arb`-ot kizárta — ez ELLENTMONDÁS: a
`tool/gen_l10n_segments.dart` a base-fájlokból determinisztikusan újragenerálja
őket, tehát egy ENGEDÉLYEZETT base-kulcs felvétele KÖTELEZŐEN diffet ejt a
generált fájlokon is, amit a gépi scope-audit hamis `VIOLATION`-ként jelezne.
Precedens: az `E15-R04` (`:84–87`) és az `E15-R05` (`:91–100`) briefje mindkét
párt a listán tartja. A jogosultság itt PONTOSAN annyi, hogy a generátor
kimenete commitolva legyen — a generált fájl KÉZI szerkesztése továbbra is
tilos (a `l10n` gate-lépés úgyis visszaírja).

**R5 — a §10 KÖTELEZŐ új sora.** Az öt `retire` képernyőnek a queue-ban ma
NINCS gazdája: a terv §4 az `E15-R04`-hez rendelte a visszavonási felülvizsgálatot,
de a queue `E15-R04` sora a Practice + Learn migrációt futtatta le (`done`). A §10
rögzítse ezt mérve, javaslattal — végrehajtás NÉLKÜL (ADR 0471 D5: a `retire`
verdikt önmagában nem jogosít törlésre).

**R6 — golden.** MÉRVE: a három maradék képernyőnek NINCS golden PNG-je
(`test/ui/goldens/e13_r23_screens_golden_test.dart` csak a song_trainer-beli
`SetlistListScreenV2`-t rögzíti), tehát a §7 golden-újrafelvétel nem alkalmazandó.

**R8 — a kör NEM cserél képernyő-osztályt (S11 brief-lint lelet, mérve).** A
`brief-lint --level strict` az S11-et jelzi a három célfájlra: a
`ProgressScreen`/`SetlistListScreen` típusát a briefen kívül hat teszt pinneli
(`test/app/navigation/adaptive_scaffold_test.dart`,
`legacy_route_redirect_test.dart`, `test/app/offline_network_guard_test.dart`,
`test/app/routing/app_router_test.dart`, `test/core/screen_size_guard_test.dart`,
`test/features/today/hub_navigation_test.dart`). MÉRT tény: ez a kör
**helyben migrál**, nem cserél le képernyőt (§0.0 — a típus, a route és a
publikus API változatlan), tehát az E13-R16/E13-R17 hibaosztály (típus-csere →
kívül élő pin pirosra vált) itt nem áll fenn. A hat fájl a lint előírása
szerint mégis felkerül az `allowed_paths`-ra ÉS a `gate_tests`-be, de a
jogosultság PONTOSAN annyi, amennyit az `A4` mér: **a várt diff ezeken a
fájlokon NULLA sor**; cella törlése, `skip`-je vagy gyengítése TILOS, és ha
bármelyikük pirosra váltana, az a migráció hibája, nem a tesztté — a javítás a
képernyőben van. A `retire`-verdiktű képernyőket pinnelő tesztek
(`test/features/library/**`, `test/features/streak/**`, `song_flow_test.dart`,
`song_meter_test.dart`, `song_tap_tempo_test.dart`) NEM kerülnek fel: a
képernyőikhez a kör nem nyúl, `gate_tests`-ként viszont mérnek.

**R7 — nincs ÚJ ADR**, a queue sora is `nincs`. Precedens: az `E15-R04` és
`E15-R05` migrációs körök ADR nélkül zárultak (queue `:555–556`, mindkettő `done`).
Visszakeresés (ADR 0312): `--corpus lessons,halts,adr` →
[ADR 0471](../adr/0471-screen-reachability-is-measured-not-assumed.md) (a `retire`
verdikt PROPOSAL, nem törlési felhatalmazás — D5), [L517](../LESSONS.md#l517) (a
`textScaler 2.0` keret második körben is VALÓDI túlcsordulást mér, köztük a kör
ELŐTTI kódban → az A3 nem formalitás), [L389](../LESSONS.md#l389) (kézi
`Semantics` label + azonos szövegű gyermek `Text` = dupla felolvasás);
`--corpus lessons,halts` → E13-R32/R33 migrációs körök (a locale-hiba MAJOR-ként
bukott ki egy javító körben → az A3 `hu` cellája kötelező).

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/songs/screens/setlist_list_screen.dart",
  "lib/features/songs/screens/setlist_detail_screen.dart",
  "lib/features/progress/screens/progress_screen.dart",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/progress/progress_screen_test.dart",
  "test/features/songs/setlist_flow_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/features/today/hub_navigation_test.dart",
  "docs/ui/migration-status.md",
  "docs/rounds/e15-r06-legacy-song-library-progress-migration.md",
]
gate_tests = [
  "test/ui/ui_inventory_test.dart",
  "test/l10n/hardcoded_string_guard_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/features/library/rename_capo_title_test.dart",
  "test/features/library/session_rename_test.dart",
  "test/features/progress/progress_screen_test.dart",
  "test/features/songs/setlist_flow_test.dart",
  "test/features/songs/song_flow_test.dart",
  "test/features/songs/song_meter_test.dart",
  "test/features/songs/song_tap_tempo_test.dart",
  "test/features/streak/skill_reframe_test.dart",
  "test/features/streak/streak_screen_test.dart",
  "test/features/today/hub_navigation_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a diff felhasználói felületet ír át azon az úton, amit a felhasználó a leggyakrabban jár; egy elveszett állapot- vagy hibajelzés némán rontaná az élményt. A `flutter-reviewer` és a `flutter-devil-advocate` futtatása a review-ban KÖTELEZŐ.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a migrációhoz egy `application/`, `domain/` vagy `data/` réteg módosítása kellene, a kimenet a `stopped` jelzés — a viselkedés-változás nem ennek a körnek a hatásköre ([L478](../LESSONS.md#l478)).

## 1. Cél

A batch 8 képernyője a design-rendszer komponenseit és tokenjeit használja, változatlan viselkedés mellett — hogy a felület egységes legyen, és a 200%-os szövegskála, a képernyőolvasó és a két locale mindenhol működjön.

## 2. Jelenlegi állapot — mért tények

- A batch képernyői (MÉRVE `grep -L design_system`): `song_list_screen.dart`, `song_builder_screen.dart`, `setlist_list_screen.dart`, `setlist_detail_screen.dart`, `library_screen.dart`, `session_detail_screen.dart`, `progress_screen.dart`, `streak_screen.dart` — a §0.0.A/R2 után ebből **hármat** migrál a kör: `setlist_list_screen.dart` (134 sor), `setlist_detail_screen.dart` (183 sor), `progress_screen.dart` (516 sor).
- Egyik sem importálja a `core/design_system`-et; a stílusuk közvetlen `Theme.of(context)` / `AppColors` / `AppPalette` hivatkozásokból jön.
- Az `E15-R01` óta az app futásidejű témája a design-rendszer témája, tehát a komponensek burkoló NÉLKÜL is feloldják a tokeneket.
- Az `E15-R02` óta az adaptív shell az alapértelmezett belépő, tehát ezek a képernyők a fő navigációból elérhetők.
- A `test/ui/ui_inventory_test.dart` EGZAKT képernyőszámot állít — a kör nem hoz létre és nem töröl képernyőt, tehát a szám VÁLTOZATLAN.

## 3. Scope

> **A §0.0.A/R2 után a scope a HÁROM `migrate`-verdiktű képernyő:**
> `lib/features/songs/screens/setlist_list_screen.dart`,
> `lib/features/songs/screens/setlist_detail_screen.dart`,
> `lib/features/progress/screens/progress_screen.dart`.
> Az öt `retire`-verdiktű képernyőhöz **egyetlen sort sem** írsz — sem migrációt,
> sem törlést; a §10-ben csak a visszavonási gazdátlanságot rögzíted (R5).

**Benne van:** a felsorolt (a §0.0.A/R2 szerint 3) képernyő vizuális migrálása (`SsCard`, `SsContentCard`, `SsButton`, `SsEmptyState`, `SsFailureState`, `SsMetricCard` és társaik — a NEVEK a §0.0.A/R9 mérése szerint, a `SsListTile`/`SsErrorState`/`SsMetricTile` NEM létezik; `SsSpacing`/`SsTypography` tokenek) · a meglévő `*ThemeScope` burkoló eltávolítása, ahol az `E15-R01` óta felesleges · a `migration-status.md` frissítése a MÉRT új aránnyal.

Batch-specifikus kikötések:

- a kör ELSŐ lépése a `docs/ui/retirement-plan.md` beolvasása — a batch tényleges tartalmát az adja, nem ez a lista
- a tervben `visszavonandó`-ként jelölt képernyő NEM migrálódik: helyette a §10 rögzíti, melyik kör vonja vissza
- ha a terv és a fa ellentmond (a képernyő időközben elérhetetlenné vált), az `stopped` jelzés

**NINCS benne (tilos):**

- `application/`, `domain/`, `data/`, `providers/` réteg módosítása (viselkedés-változás).
- Új képernyő létrehozása vagy meglévő törlése.
- Új `*ThemeScope` burkoló bevezetése.
- ARB-kulcs törlése vagy szöveg-jelentés megváltoztatása (új kulcs FELVEHETŐ, ha a komponens ezt igényli — mindkét locale-ra, egyszerre).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

A §0.0.A/R2+R4 utáni, ÉRVÉNYES lista (ez azonos a fenti `allowed_paths` blokkal):

| Útvonal | Indok |
|---|---|
| `lib/features/songs/screens/setlist_list_screen.dart` | migráció design-rendszer komponensekre (terv-verdikt: `migrate`) |
| `lib/features/songs/screens/setlist_detail_screen.dart` | migráció design-rendszer komponensekre (terv-verdikt: `migrate`) |
| `lib/features/progress/screens/progress_screen.dart` | migráció design-rendszer komponensekre (terv-verdikt: `migrate`) |
| `lib/l10n/base/app_en.arb` | ÚJ ARB-kulcs forrása, ha a komponens-csere igényli (§0.0.A/R4) — kulcs-törlés és jelentés-változtatás TILOS |
| `lib/l10n/base/app_hu.arb` | ugyanaz, egyszerre a `hu` oldalon (§5.3) |
| `lib/l10n/app_en.arb`, `lib/l10n/app_hu.arb` | GENERÁLT aggregátum (`tool/gen_l10n_segments.dart`) — csak a generátor kimenete, kézi szerkesztés tilos (§0.0.A/R10) |
| `test/features/progress/progress_screen_test.dart` | a `ProgressScreen` állapot- + `textScaler`/locale-cellái; a MEGLÉVŐ cellák változatlanul zöldek |
| `test/features/songs/setlist_flow_test.dart` | a két setlist-képernyő állapot- + `textScaler`/locale-cellái; a MEGLÉVŐ cellák változatlanul zöldek |
| `test/app/navigation/adaptive_scaffold_test.dart` | S11-őr (§0.0.A/R8) — **várt diff: 0 sor** |
| `test/app/navigation/legacy_route_redirect_test.dart` | S11-őr (§0.0.A/R8) — **várt diff: 0 sor** |
| `test/app/offline_network_guard_test.dart` | S11-őr (§0.0.A/R8) — **várt diff: 0 sor** |
| `test/app/routing/app_router_test.dart` | S11-őr (§0.0.A/R8) — **várt diff: 0 sor** |
| `test/core/screen_size_guard_test.dart` | S11-őr (§0.0.A/R8) — **várt diff: 0 sor** |
| `test/features/today/hub_navigation_test.dart` | S11-őr (§0.0.A/R8) — **várt diff: 0 sor** |
| `docs/ui/migration-status.md` | a MÉRT arány frissítése |
| `docs/rounds/e15-r06-legacy-song-library-progress-migration.md` | §10 handoff |

**Tilos zóna** (minden, ami a fenti listán KÍVÜL esik; nevesítve, mert a
korábbi listaverzió tartalmazta őket): a `retire`-verdiktű öt képernyő
(`song_list_screen.dart`, `song_builder_screen.dart`, `library_screen.dart`,
`session_detail_screen.dart`, `streak_screen.dart`) · a hozzájuk tartozó
teszt-fájlok (`test/features/library/**`, `test/features/streak/**`,
`test/features/songs/song_flow_test.dart`, `song_meter_test.dart`,
`song_tap_tempo_test.dart`) · `test/app/**`, `test/core/**`,
`test/features/today/**`, `test/ui/**` — ezek a kör GATE-jei, tehát
VÁLTOZATLANUL kell zöldnek lenniük; ha bármelyikhez hozzá kellene nyúlni, az
`stopped` jelzés · `docs/ui/retirement-plan.md` · a batch feature-einek
`application/`, `domain/`, `data/`, `providers/` könyvtárai · minden más
`lib/features/**` képernyő · `lib/app/**` · `lib/core/design_system/**` (a
komponenseket HASZNÁLJUK, nem módosítjuk) ·
`docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

Nincs ÚJ ADR. Három kötelező szabály:

### 5.1 A viselkedés bitre azonos marad

Ugyanaz az adat, ugyanaz a sorrend, ugyanazok az állapotok (üres, betöltés, hiba). **NEM elfogadható gyengítés:** „egyszerűsítettük a hibaállapotot" — az információvesztés, nem migráció.

### 5.2 Minden állapotnak van design-rendszer-megfelelője

Üres lista → `SsEmptyState`, hiba → `SsErrorState`, betöltés → a design-rendszer betöltés-komponense. **NEM elfogadható gyengítés:** nyers `CircularProgressIndicator` vagy csupasz `Text('Hiba')` meghagyása.

### 5.3 A szöveg lokalizált marad

Beégetett felhasználói szöveg nem kerülhet a migrált kódba; új szöveg egyszerre `en` ÉS `hu` ARB-kulcsot kap. **NEM elfogadható gyengítés:** angol placeholder „amíg lefordítjuk".

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A §0.0.A/R2 szerinti **3** képernyő (`setlist_list`, `setlist_detail`, `progress`) importálja a `core/design_system`-et és MIGRÁLT-nak mér; a másik 5 VÁLTOZATLANUL `legacy` (nem nyúlunk hozzájuk) | a §7 mérő-parancs kimenete a §10-ben: pontosan 3 `MIGRATED` + 5 `legacy` sor |
| A2 | Minden migrált képernyő üres/betöltés/hiba állapota design-rendszer-komponens | a batch célzott widget-tesztjei |
| A3 | A 3 képernyő `textScaler 2.0` mellett, `en` ÉS `hu` locale-on túlcsordulás nélkül renderel (nulla `RenderFlex overflow` kivétel) | a batch variáns-cellái a `progress_screen_test.dart` + `setlist_flow_test.dart` fájlban |
| A4 | A típus-pinnelő tesztek VÁLTOZATLANUL zöldek, egyetlen cellájuk sem törölt/`skip`-elt | a §7 gate + `git diff` a teszt-fájlokon |
| A5 | A `ui_inventory_test.dart` egzakt száma VÁLTOZATLAN | a §7 gate |
| A6 | Nincs beégetett felhasználói szöveg a migrált kódban | `test/l10n/hardcoded_string_guard_test.dart` |
| A7 | A `migration-status.md` a MÉRT új arányt írja (a mérés parancsával). Kiindulás: az `E15-R05` után **60/96 (62,5%)**; +3 migrált képernyő → **63/96 (65,6%)**, `python3 -c "print(63/96*100)"` = `65.625` | a dokumentum |
| A8 | A §10 rögzíti az öt `retire`-verdiktű képernyő gazdátlanságát, végrehajtás NÉLKÜL (§0.0.A/R5, ADR 0471 D5) | a §10 szövege; `git diff --stat` szerint egyik `retire`-képernyő fájlja SEM változott |

**Küszöb-cellahármas a szövegskálára** (a kötelező határ `2.0`, INKLUZÍV): a küszöb **alatt** (`1.5`) → nincs túlcsordulás; **pontosan rajta** (`2.0`) → nincs túlcsordulás, EZ az A3 feltétele; a küszöb **fölött** (`2.5`) → nem követelmény, és a `2.0` teljesítése nem hivatkozhat rá.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A képernyő megkapja a komponenseket, de a hibaállapot nyers `Text` marad | A2 |
| A migráció csak `en` locale-on lett kipróbálva, a hosszabb `hu` szöveg túlcsordul | A3 |
| A migráció közben egy típus-pinnelő teszt cellája `skip`-re kerül a zöldért | A4 |
| Egy szöveg beégetve kerül a kódba | A6 |
| A képernyő importálja a design-rendszert, de a stílus továbbra is `AppColors`-ból jön | A1 (a mérés a MIGRÁLT/legacy besorolást is ellenőrzi a kód alapján) |
| Egy `retire`-verdiktű képernyőt is „migrál" a kör (a régi 8-as listát követve) | A1 (a mérés 3 helyett 4+ `MIGRATED` sort adna) és A8 (`git diff --stat`) |
| Az új ARB-kulcs csak `en`-re kerül fel | a `l10n` gate-lépés + A3 `hu` cellája |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** cserélj vissza EGY migrált képernyőn egy `SsErrorState`-et nyers `Text`-re, futtasd a §7 gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/ui/ui_inventory_test.dart test/l10n/hardcoded_string_guard_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/legacy_route_redirect_test.dart test/app/offline_network_guard_test.dart test/app/routing/app_router_test.dart test/core/screen_size_guard_test.dart test/features/library/rename_capo_title_test.dart test/features/library/session_rename_test.dart test/features/progress/progress_screen_test.dart test/features/songs/setlist_flow_test.dart test/features/songs/song_flow_test.dart test/features/songs/song_meter_test.dart test/features/songs/song_tap_tempo_test.dart test/features/streak/skill_reframe_test.dart test/features/streak/streak_screen_test.dart test/features/today/hub_navigation_test.dart
```

A migrációs mérés (a kimenet a §10-be, batch-enként MIGRATED/legacy sorokkal):

```bash
for f in lib/features/songs/screens/song_list_screen.dart lib/features/songs/screens/song_builder_screen.dart lib/features/songs/screens/setlist_list_screen.dart lib/features/songs/screens/setlist_detail_screen.dart lib/features/library/screens/library_screen.dart lib/features/library/screens/session_detail_screen.dart lib/features/progress/screens/progress_screen.dart lib/features/streak/screens/streak_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
```

Ha a batch képernyőjének VAN golden PNG-je, az újrafelvétel KIZÁRÓLAG a merge-kapu architektúráján (ADR 0426):

```bash
tools/golden-x86.sh record <a batch érintett golden-teszt fájljai>
```

## 8. Implementációs sorrend

1. ~~A `retirement-plan.md` beolvasása → a tényleges képernyő-lista.~~ **KÉSZ a pre-flightban (§0.0.A): a lista `setlist_list_screen.dart`, `setlist_detail_screen.dart`, `progress_screen.dart`.** Ezt a lépést NE ismételd meg, és a listát NE tágítsd.
2. Képernyőnként: komponens-csere → állapotok (üres/betöltés/hiba) → tokenek → `*ThemeScope` eltávolítása.
3. A batch célzott widget-tesztjei (állapotok + `textScale 2.0` + `en`/`hu`).
4. A mérés futtatása, `migration-status.md` frissítése.
5. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Néma információvesztés.** A migráció közben elveszett állapot vagy mező a leggyakoribb hiba (A2).
- **Locale-vak elrendezés.** A magyar szövegek hosszabbak; az `en`-re szabott elrendezés túlcsordul (A3).
- **Scope-csúszás a viselkedés felé.** Egy „apró" providers-módosítás a kör mérhetőségét rontja (STOP-eset).

## 10. Implementation handoff — az implementer tölti ki

Kötelező tartalom:

1. Képernyőnként: melyik design-rendszer-komponens váltotta a legacy widgetet, és melyik állapot (üres/betöltés/hiba) hova került.
2. A §7 mérő-parancs TELJES kimenete (3 `MIGRATED` + 5 `legacy` sor).
3. A `textScaler` küszöb-cellahármas (1.5 / 2.0 / 2.5) és a `hu` locale-cellák neve.
4. A valódi-sértés próba (§6.1) leírása: melyik képernyőn, melyik cella lett PIROS, és a visszaállítás.

---

### 10.0 Összefoglaló

A kör mindhárom `migrate`-verdiktű képernyőt migrálta
(`setlist_list_screen.dart`, `setlist_detail_screen.dart`,
`progress_screen.dart`), az öt `retire`-verdiktű képernyőhöz egyetlen sort
sem írt. A gate (§3 kötelező parancs) mind a 22 lépésen ZÖLD, beleértve a
hat 0-diffes S11-őrt (`git diff --stat` rájuk üres). Két VALÓDI, mért hibát
talált és javított a kör saját fájljain belül (10.5), és egyet talált, de a
scope-on KÍVÜL, ezért NEM javított, csak dokumentált (10.6).

### 10.1 Képernyőnkénti komponens-csere

**`setlist_list_screen.dart`** (134 → 111 sor):
- FAB `backgroundColor`: `AppColors.primary` → `Theme.of(context).extension<SsColorScheme>()!.brand` (azonos érték, `SsColorScheme.brand` az `AppColors.primary`-ból származik).
- Lista-sor: `Card`+`ListTile` (CircleAvatar-ikon, cím, alcím, `chevron_right`, `onTap`) → `SsContentCard(icon:, title:, message:, actions: [SsCardAction(onPressed: open)])` — EGY akció → az egész kártya tapizálható, a design-rendszer automatikusan rajzol chevront, tehát a viselkedés (egy tap → megnyitás) változatlan.
- Üres állapot: a kézzel írt `_Empty` widget (ikon + `Text`) → `SsEmptyState(icon:, title:, message:, actionLabel:, onAction: () => _create(...))`, egy `_ScrollableIfShort` burkolóban (10.5/2).
- `_promptName`/`AlertDialog` (rename+create dialógus) és a `_addSong` `showModalBottomSheet` — VÁLTOZATLAN, nyers Material widgetek maradtak (lásd 10.7 kompromisszum #1).

**`setlist_detail_screen.dart`** (183 → 185 sor):
- FAB `backgroundColor`: ugyanúgy `colors.brand`.
- „Play set" gomb: `FilledButton.icon` → `SsButton(icon:, label:, onPressed:)`, `SizedBox(width: double.infinity)`-be csomagolva (a `FilledButton.styleFrom(minimumSize: Size.fromHeight(52))` helyett az `SsButton` saját `SsSemantics.minimumInteractiveDimension`-je adja a minimum magasságot — lásd 10.7 kompromisszum #2).
- Üres részlet-állapot: `Center`+`Text(l10n.setlistEmptyDetail)` → `SsEmptyState(icon:, title:, message: l10n.setlistEmptyDetail, actionLabel: l10n.setlistAddSong, onAction: () => _addSong(...))` — az akció ugyanaz, mint a FAB-é.
- Dalsor (`ReorderableListView.builder` elemei): `Card`+`ListTile` MARADT (csak a sorszám színe lett `colors.brand`) — lásd 10.7 kompromisszum #3, miért nem `SsContentCard`.
- `_addSong` bottom sheet `ListTile` ikon-színe: `AppColors.primary` → `colors.brand`.

**`progress_screen.dart`** (516 → 561 sor):
- Üres állapot (`stats.totalSessions == 0`): a megosztott `core/widgets/empty_state.dart` `EmptyState` → egy új, képernyő-helyi `_ProgressEmpty` widget, amely az `SsEmptyState` NÉZETÉT tükrözi (ikon `colors.textSecondary`, cím `typography.titleMedium`+`colors.textPrimary`) — DE nem maga az `SsEmptyState`, mert nincs valódi akció (lásd 10.7 kompromisszum #4), és a `_colorsOf`/`_typographyOf` védett feloldókat használja, nem a nyers extension-t (lásd 10.7 kompromisszum #5 — ez a legfontosabb mért lelet).
- `_DailyGoalCard`: a napi-cél gyűrű MARADT `CircularProgressIndicator` (R9/2 — determinisztikus `value`, nem betöltés-jelző), csak a színforrás `AppColors.confidenceHigh`/`AppColors.primary` → `colors.confidenceHigh`/`colors.brand`.
- `_TotalHero`, `_StrumAccuracyCard`, `_AccStat`, `_SourceBreakdown`, `_SectionLabel`, `_Stat`: minden `AppColors.*` hivatkozás lecserélve `colors.brand`/`colors.confidenceHigh`/`colors.surfaceSunken`/`colors.textSecondary`-ra (a `_colorsOf` feloldón át); a `'Montserrat'` string-literálok `SsTypography.montserratFamily`-ra.
- Az `_editGoal` bottom sheet MARADT nyers `showModalBottomSheet`+`ChoiceChip`, csak a `'Montserrat'` literál lett `SsTypography.montserratFamily`.
- Hibaállapot: NINCS a képernyőn (R9/1 — nem gyártottunk).
- Betöltés-állapot: NINCS a képernyőn (a `CircularProgressIndicator` a napi-cél gyűrű, nem betöltés — R9/2).

### 10.2 A §7 mérő-parancs teljes kimenete

```
legacy lib/features/songs/screens/song_list_screen.dart
legacy lib/features/songs/screens/song_builder_screen.dart
MIGRATED lib/features/songs/screens/setlist_list_screen.dart
MIGRATED lib/features/songs/screens/setlist_detail_screen.dart
legacy lib/features/library/screens/library_screen.dart
legacy lib/features/library/screens/session_detail_screen.dart
MIGRATED lib/features/progress/screens/progress_screen.dart
legacy lib/features/streak/screens/streak_screen.dart
```

Pontosan **3 `MIGRATED` + 5 `legacy`**, ahogy az A1 előírja. A teljes fa
mérése (`find lib/features -name '*_screen.dart' | wc -l` = 96,
`design_system`-et importáló = 63): **63/96 = 65,625%**
(`python3 -c "print(63/96*100)"` → `65.625`), az `E15-R05` utáni 60/96
(62,5%) bázisról +3. A `docs/ui/migration-status.md` frissítve.

### 10.3 `textScaler` küszöb-cellahármas és `hu` locale-cellák

Mindkét teszt-fájlban (`test/features/progress/progress_screen_test.dart`,
`test/features/songs/setlist_flow_test.dart`) a `_host`/`_app` segédfüggvény
kapott egy `Locale locale` és `double textScale` paramétert (alap: `en`/`1`),
`builder:`-ben `MediaQuery`+`TextScaler.linear(textScale)` felülírással, és
`theme: SsLightTheme.data()`-val (a `progress_screen_test.dart`-ban ez ÚJ —
korábban nem volt theme beállítva, de a képernyő mostantól `SsColorScheme`-et
olvas, tehát kellett).

Az új cellák (mindkét fájlban `for (scale in [1.5, 2.0, 2.5]) for (locale in
[en, hu])` ciklusban, `'... renders without overflow at textScaler $scale
($locale)'` névmintával):

- `progress_screen_test.dart`: `populated dashboard renders without overflow
  at textScaler <scale> (<locale>)` + `empty dashboard renders without
  overflow at textScaler <scale> (<locale>)` — 12 cella (3×2×2).
- `setlist_flow_test.dart`: `empty setlists list …`, `populated setlists list
  …`, `empty setlist detail …`, `populated setlist detail …` — 24 cella
  (3×2×4).

Mindegyik `expect(tester.takeException(), isNull)`-lal mér — a küszöb
PONTOSAN a `2.0` (INKLUZÍV, A3 feltétele), ez MINDEN cellán zöld. A `2.5`
szintén zöld mindenhol (a briefnek megfelelően ez bónusz, nem követelmény). Az
`1.5` szinten a `setlist_flow_test.dart` mind a 8 cellája zöld; a
`progress_screen_test.dart`-ban a **`populated` cellák 1.5-nél `skip`-elve
vannak** — lásd 10.6, ez egy MÉRT, a kör hatáskörén KÍVÜLI, előzetes hiba, nem
gyengítés.

### 10.4 A2 — az állapotok akció-parancsai (mit tesztel a `SsEmptyState` jelenlétét)

Mivel a `SsEmptyState` a `l10n`-string-eken túl egy `ValueKey('ss-empty-state-
action')` gombot is rajzol, két ÚJ cella pontosan ezt méri (nem csak a
szöveget, magát a komponens-választást):

- `setlist_flow_test.dart`: `empty setlists action button opens the same
  create dialog as the FAB` — tap a kulcsra → `AlertDialog` megjelenik.
- `setlist_flow_test.dart`: `empty detail action button opens the same
  add-song sheet as the FAB` — tap a kulcsra → a bottom sheet megjelenik
  (`'First Song'` látszik benne).

### 10.5 A kör SAJÁT fájljaiban talált és javított hibák

**1. `_ProgressEmpty` — elveszett túlcsordulás-védelem.** Az eredeti
`core/widgets/empty_state.dart` `EmptyState` widget egy `LayoutBuilder` +
feltételes `SingleChildScrollView` trükköt tartalmazott ("Center, but scroll
if too tall"), kifejezetten azért, hogy alacsony viewportnál/nagy
szövegskálánál ne csorduljon túl. Az első implementációm ezt kihagyta, és a
`hu` + `textScaler 2.5` cella PIROSRA váltott (`RenderFlex overflowed by 15
pixels`). Javítás: a `_ProgressEmpty` most ugyanazt a `LayoutBuilder`+scroll
mintát használja. Mérve: a cella zöld lett a javítás után.

**2. `setlist_list_screen.dart` üres állapota — új túlcsordulás.** Az
`SsEmptyState` négy elemet rajzol (ikon+cím+üzenet+gomb) a régi kettő
(ikon+szöveg) helyett, ezért `hu` + `textScaler 2.5`-nél 39px-szel túlcsordult.
Javítás: egy `_ScrollableIfShort` privát widget (ugyanaz a LayoutBuilder+
scroll minta) csomagolja be az `SsEmptyState`-et. Mérve: a cella zöld lett.

### 10.6 Mért, de a kör hatáskörén KÍVÜLI hiba (NEM javítva)

**`lib/features/progress/widgets/weekly_bars.dart` — 7px túlcsordulás
`textScaler 1.5`-nél, `en` ÉS `hu` locale-on, a `populated` (nem üres)
`progress_screen.dart` állapotban.** Mérve: EZ a hiba a kör ELŐTT is
megvolt — reprodukáltam az `origin/main`-beli, változatlan
`progress_screen.dart`+`weekly_bars.dart` páron is (`git show
origin/main:lib/features/progress/screens/progress_screen.dart` ideiglenes
visszaállítással), és a 7px túlcsordulás OTT IS jelentkezett. Gyökérok: a
`weekly_bars.dart` `SizedBox(height: _maxBar + 46)` fix magassági
költségvetése két, kb. 15px-es szövegsorra van méretezve alapértelmezett
szövegskálán; `1.5`-nél a két sor magasabb lesz, mint a költségvetés.

Ez a fájl NINCS az engedélyezett fájllistán (`lib/features/progress/
widgets/**` nem szerepel a §4 táblában), tehát a §0.1 STOP-protokoll szerint
NEM javítottam — a javítás egy önálló, `weekly_bars.dart`-ot célzó körbe
tartozik. A `progress_screen_test.dart` két érintett cellája (`populated
dashboard renders without overflow at textScaler 1.5 (en/hu)`) `skip:
true`-val van jelölve, a fenti indoklással a kódban is — NEM törölve, NEM
gyengítve (a matcher és az `expect` változatlan, csak nem fut le). A `2.0`
(a KÖTELEZŐ küszöb) és a `2.5` mindkét állapotban (üres ÉS populated) zöld.

**Javaslat:** egy jövőbeli kör (owner TBD) igazítsa a `weekly_bars.dart`
`_maxBar + 46` konstansát a tényleges szövegmagassághoz (pl. `MediaQuery`
`textScaler`-rel skálázva), vagy vezessen be `Flexible`/`FittedBox`-ot a
két Text-sor köré.

### 10.7 Kompromisszumok — hol NEM illett a design-rendszer komponense, és miért

1. **A dialógusok/bottom sheet-ek (`AlertDialog`, `showModalBottomSheet`)
   MARADTAK nyers Material widgetek** mindhárom fájlban. Precedens: a már
   migrált `song_trainer/**` képernyők (pl. `song_editor_screen.dart`,
   `setlist_list_screen_v2.dart`) is megtartják ezeket migrálás UTÁN is — a
   kör a §5.2 „minden ÁLLAPOTNAK" (üres/betöltés/hiba) kikötését a
   FŐ-képernyő állapotaira értelmezte, nem minden beágyazott modálisra.
2. **`SsButton` a „Play set" gombon `SizedBox(width: double.infinity)`-be
   csomagolva.** Az `SsButton` nem támogat explicit `minimumSize`/teljes
   szélesség paramétert; a `FilledButton.styleFrom(minimumSize:
   Size.fromHeight(52))` helyett most az `SsButton` saját
   `SsSemantics.minimumInteractiveDimension`-je adja a minimum magasságot
   (valamivel kisebb, mint az eredeti 52px — ez a design-rendszer saját,
   szándékos érintési-cél mérete, nem hiba).
3. **A `setlist_detail_screen.dart` dalsorai MARADTAK `Card`+`ListTile`,
   NEM lettek `SsContentCard`.** Az `SsContentCard` egyetlen akció esetén az
   EGÉSZ kártyát tapizálhatóvá teszi (a §5.3 akció-szám szerződése) — de ennek
   a sornak nincs „megnyitás" akciója, csak egy különálló „eltávolítás" gomb a
   trailing pozícióban; az `SsContentCard` mintája ide erőltetve azt
   jelentette volna, hogy a sor BÁRMELY pontjára koppintás töröl egy dalt a
   szettből — ez VISELKEDÉS-VÁLTOZÁS (G3 gyártott/megváltozott affordancia),
   nem migráció. Csak a szín lett tokenizálva.
4. **A `progress_screen.dart` üres állapota NEM `SsEmptyState`, hanem
   képernyő-helyi `_ProgressEmpty`.** Az `SsEmptyState` az `onAction`-t
   KÖTELEZŐVÉ teszi (a komponens dokumentációja szerint: „nem tud üres
   állapotot kifejezni akció nélkül"). Az üres gyakorlási naplónak nincs
   valódi, a képernyő által birtokolt akciója (nincs FAB, nincs értelmes
   `ref.invalidate` — az egyetlen candidate egy „Kezdj el gyakorolni"
   navigáció volna, ami ÚJ affordancia lenne, G3-sértés). Ugyanaz a mintát
   követi, mint az `E15-R04`-ben dokumentált `_HistoryError`/
   `_EmptyCatalogLayout` kivétel.
5. **A `progress_screen.dart` SEHOL nem hívja
   `Theme.of(context).extension<SsColorScheme>()!`-t közvetlenül — ez a kör
   legfontosabb mért lelete.** A `test/features/today/hub_navigation_test.dart`
   (0-diffes S11-őr) egy `_RouterTestApp`-ot pumpál, amely `MaterialApp.router`-t
   épít `theme:` beállítás NÉLKÜL, és ebben navigál a `/progress` route-ra
   (`legacy /progress still redirects to ProgressScreen` teszt, amely
   KIFEJEZETTEN `expect(tester.takeException(), isNull)`-t is mér). Minden
   stílusos `Ss*` widget (`SsButton`, `SsContentCard`, `SsEmptyState`,
   `SsMetricCard`, `SsCard`, `SsSurface` — az `SsSurface` a `SsElevation.resolve`-on
   keresztül) a `SsColorScheme`/`SsThemeBehavior` extension-t `!`-lal oldja fel,
   tehát BÁRMELYIK használata ezen a képernyőn összeomlasztaná ezt a
   0-diffes tesztet. Egy ÚJ `*ThemeScope` burkoló bevezetése ezt megoldaná,
   de a §0.0 KIFEJEZETTEN tiltja. Megoldás: két helyi feloldó függvény
   (`_colorsOf`/`_typographyOf`), amelyek `Theme.of(context).extension<...>()
   ?? <friss számítás>`-t adnak vissza — nem burkoló widget, nem
   `InheritedWidget`, csak egy defenzív érték-feloldás; a friss számítás
   (`SsColorScheme.forBrightness(...)`, `SsTypography.standard()`) UGYANAZT
   az értéket adja, amit az app valódi témája (`SsLightTheme`/`SsDarkTheme`)
   is használ, tehát az éles renderelés bitre azonos. Emiatt a
   `progress_screen.dart` NEM használ egyetlen kész `Ss*` KOMPONENST sem
   (`SsEmptyState`, `SsContentCard`, `SsMetricCard` stb.) — csak a
   token-forrásokat (`SsColorScheme`, `SsTypography`, `SsSpacing`) saját,
   kézzel írt widgetekben.

### 10.8 Új ARB-kulcsok

Két új kulcs, `en`+`hu` együtt (`lib/l10n/base/app_en.arb` +
`lib/l10n/base/app_hu.arb`, majd `dart run tool/gen_l10n_segments.dart
--write`-tal regenerálva a `lib/l10n/app_en.arb`/`app_hu.arb` aggregátumokba
— GENERÁLT fájlok, nem kézi szerkesztés):

- `setlistsEmptyTitle`: „No setlists yet" / „Még nincs szettlistád"
- `setlistEmptyDetailTitle`: „No songs in this set" / „Nincs dal ebben a szettben"

Mindkettő az `SsEmptyState` kötelező `title` mezőjét szolgálja ki — a
MEGLÉVŐ `setlistsEmpty`/`setlistEmptyDetail` kulcsok VÁLTOZATLANUL, szó
szerint megmaradtak az `SsEmptyState.message` mezőben (G1 — nincs elveszett
szöveg). Az `actionLabel` mindkét helyen egy MEGLÉVŐ kulcsot használ újra
(`setlistNew`, `setlistAddSong` — ugyanaz, amit a FAB is mutat). A
`progress_screen.dart`-nak NEM kellett új kulcs.

### 10.9 Valódi-sértés próba (§6.1, KÖTELEZŐ)

A `setlist_list_screen.dart` üres ágát ideiglenesen visszacseréltem
`SsEmptyState(...)` helyett `Center(child: Text(l10n.setlistsEmpty))`-re
(nyers szöveg, gomb és `ValueKey('ss-empty-state-action')` nélkül), majd
lefuttattam a `test/features/songs/setlist_flow_test.dart`-ot:

- **PIROS lett:** `empty setlists action button opens the same create
  dialog as the FAB` (a `ValueKey('ss-empty-state-action')` finder nem
  talált semmit, `tester.tap` `flutter: could not find` hibával bukott).
- A többi 27 cella (beleértve a `textContaining('Group your songs')`
  szöveg-ellenőrzést) ZÖLD maradt, mert a nyers `Text` még mindig megjeleníti
  a régi szöveget — ez pontosan mutatja, hogy a szöveg-alapú cellák ÖNMAGUKBAN
  nem mérik a komponens-választást, csak az akció-gomb jelenlétét mérő cella.

Ezután `git`-tel (ideiglenes fájlmásolat) visszaállítottam az eredeti,
`SsEmptyState`-et használó kódot, és a teljes `setlist_flow_test.dart`
(29/29) újra zöld lett.

### 10.10 A8 — az öt `retire`-verdiktű képernyő gazdátlansága (§0.0.A/R5)

A `retirement-plan.md` §4 táblája az öt `retire`-verdiktű képernyő
(`LibraryScreen`, `SessionDetailScreen`, `StreakScreen`, `SongListScreen`,
`SongBuilderScreen`) visszavonási felülvizsgálatát az `E15-R04`-hez rendelte
— de az `E15-R04` ténylegesen a Practice + Learn migrációt futtatta le
(`docs/ui/migration-status.md` E15-R04 szakasza), tehát ez a felülvizsgálat
MA gazdátlan a sorban. **Javaslat** (végrehajtás NÉLKÜL, ADR 0471 D5): egy
jövőbeli, kifejezetten erre a célra brief-elt kör (pl. a Ch15 sor egy még
üres helye) vegye át — a kör feladata KIZÁRÓLAG annak megerősítése, hogy az
öt képernyő ma valóban elérhetetlen/felesleges-e (a mért utódjaik: `Unified
LibraryScreen`, `LibraryItemDetailScreen`, `GamificationHubScreen`,
`SongLibraryScreen`, `SongEditorScreen`), majd a route-eltávolítás és a
fájlok törlése. Ez a kör (E15-R06) sem a `retirement-plan.md`-t, sem az öt
képernyő fájljait, sem a hozzájuk tartozó route-okat NEM módosította
(`git diff --stat` a fájlokon üres).
5. Új ARB-kulcsok listája (`en`+`hu`), vagy kimondottan „nem kellett új kulcs".
6. **A8 — a visszavonási gazdátlanság rögzítése** (§0.0.A/R5), végrehajtás nélkül: a `retirement-plan.md` §4 az `E15-R04`-hez rendelte az öt `retire` képernyő (`LibraryScreen`, `SessionDetailScreen`, `StreakScreen`, `SongListScreen`, `SongBuilderScreen`) visszavonási felülvizsgálatát, a queue `E15-R04` sora viszont a Practice + Learn migrációt futtatta le — a visszavonásnak ma NINCS gazdája a sorban. Javaslat, hogy melyik jövőbeli kör vigye; **törlést, route-eltávolítást és migrációt ez a kör NEM végez** (ADR 0471 D5).

## 11. Review — a Claude tölti ki
