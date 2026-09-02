# E16-R02 — A Progress V2 bekötése és a router placeholder-mentesítése

- **Státusz:** PREPARED (előre megírva 2026-09-02, kód olvasva: `main @ 11d0d2bb`)
- **Típus:** Chapter 16 (Kompozíció és rollout), Kör 2
- **Kör-azonosító:** `E16-R02`
- **Branch:** `<motor>/e16-r02-progress-projection-and-router-placeholders`
- **Előfeltétel:** `E16-R01` merge-elve (a gamification kompozíció mintája és a router-diff ott készül el)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0491` — a szám FOGLALT (Chapter 16 batch-tartomány).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "progress projection dashboard skill detail unreachable screen wiring"` → az `E15-R03` saját mérése (`docs/ui/retirement-plan.md`): „progress_v2 is NOT wired into the router — `/profile/progress` still builds the legacy `ProgressScreen` (app_router.dart:528)", és **[ADR 0353](../adr/0353-caller-fed-compassionate-streak-v2-presentation.md)** (hívó-adta prezentáció). A kör ezt a MÉRT holt ágat élesíti.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd újra, hogy a `/profile/progress` route MÉG a legacy `ProgressScreen`-t építi-e, és hogy a `ProgressOverviewProjection` / `SkillDetailProjection` típusokra a `lib/features/progress_v2/`-n KÍVÜL még mindig **0** hivatkozás van-e.

## 0.0 A MÉRT hiba: kész felület, amihez nincs adatforrás

A `progress_v2` feature **hét** fájlt tartalmaz: két képernyőt (`ProgressDashboardScreen`, `SkillDetailScreen`), négy domain-projekciót (`progress_overview_projection`, `skill_detail_projection`, `progress_trend`, `metric_version_segment`) és egy téma-burkolót. A képernyők „hívó-adta" szerződésűek (`required this.projection`), de **a projekciót SENKI nem állítja elő**: a típusokra a feature-en kívül nulla hivatkozás van, és a router `/profile/progress` útvonala ma is a legacy `ProgressScreen`-t építi. A felület tehát elkészült, de halott kód.

Ez a kör a hiányzó ELŐÁLLÍTÓT írja meg a MEGLÉVŐ adatforrásokból (gyakorlás-történet, gamification-profil, elemzési eredmények), és élesíti a route-ot.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/progress_v2/application/progress_projection_builder.dart",
  "lib/features/progress_v2/application/progress_providers.dart",
  "lib/features/progress_v2/public.dart",
  "lib/app/routing/app_router.dart",
  "test/features/progress_v2/progress_projection_builder_test.dart",
  "test/app/routing/progress_composition_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/ui/ui_inventory_test.dart",
  "docs/ui/migration-status.md",
  "docs/rounds/e16-r02-progress-projection-and-router-placeholders.md",
]
gate_tests = [
  "test/features/progress_v2/progress_projection_builder_test.dart",
  "test/app/routing/progress_composition_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/ui/ui_inventory_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a kör a `/profile/progress` felhasználói útvonalat cseréli át egy másik képernyőre, és tanulási előrehaladást jelenít meg — hibás projekció esetén a felhasználó a saját fejlődéséről kapna téves képet. A `flutter-reviewer` + `flutter-devil-advocate` KÖTELEZŐ.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha egy projekciós mező kiszámításához olyan adat kellene, ami a fán MÉRHETŐEN nem létezik (nincs forrás-repository), a kimenet a `stopped` jelzés és a mező-lista — kitalált vagy szintetikus érték TILOS.

## 1. Cél

A `/profile/progress` a Progress V2 dashboardot mutassa, VALÓS, meglévő adatokból számított projekcióval — a legacy `ProgressScreen` pedig kontrolláltan váltson át (átirányítás vagy visszavonás az `E15-R03` terve szerint).

## 2. Jelenlegi állapot — mért tények

- `lib/features/progress_v2/`: 2 képernyő + 4 domain-projekció + 1 téma-burkoló; **0 provider**, **0 application/data fájl**.
- `ProgressOverviewProjection` és `SkillDetailProjection` hivatkozás a feature-en kívül: **0**.
- `app_router.dart` `/profile/progress` → a legacy `ProgressScreen` (az `E15-R03` audit mérte).
- Elérhető adatforrások: gyakorlás-történet (`lib/features/practice/data/`, 14 fájl), gamification-profil és ledger (`E16-R01` providerei), elemzési eredmények (`lib/features/audio_analysis/data/`, 23 fájl), song-trainer eredmények (`lib/features/song_trainer/data/`, 40 fájl).
- A `legacy_route_redirect_test.dart` a tizenegy legacy útvonal célját pinneli — a route-váltás ezt érinti.

## 3. Scope

**Benne van:** `application/progress_projection_builder.dart` — a `ProgressOverviewProjection` és a `SkillDetailProjection` előállítása a MEGLÉVŐ forrásokból (tiszta Dart, óra és véletlen nélkül) · `application/progress_providers.dart` — a kompozíciós réteg (az `E16-R01` mintájára) · `public.dart` export · a router `/profile/progress` útvonalának átkötése a `ProgressDashboardScreen`-re + a skill-detail útvonal bekötése · a legacy `ProgressScreen` kezelése az `E15-R03` terve szerint (átirányítás; a fájl TÖRLÉSE nem ennek a körnek a dolga) · `migration-status.md` frissítése.

**NINCS benne (tilos):**

- Új metrika vagy pontszám-definíció (`domain/` szabály) — a projekció a MEGLÉVŐ mezőket tölti.
- Szintetikus/„demo" adat bármilyen formában.
- Más feature képernyőinek átírása.
- A legacy `ProgressScreen` fájljának törlése.
- `docs/adr/**` — az ADR 0491-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/progress_v2/application/progress_projection_builder.dart` | ÚJ — a projekció-előállító |
| `lib/features/progress_v2/application/progress_providers.dart` | ÚJ — a kompozíciós réteg |
| `lib/features/progress_v2/public.dart` | export |
| `lib/app/routing/app_router.dart` | a `/profile/progress` átkötése |
| `test/features/progress_v2/progress_projection_builder_test.dart` | a §6 projekció-cellái |
| `test/app/routing/progress_composition_test.dart` | a §6 útvonal-cellái |
| `test/app/navigation/*.dart` (három őr) · `test/ui/ui_inventory_test.dart` | regresszió-őrök — a jogosultság PONTOSAN a `/profile/progress` adapter típusának átírása; cella törlése, `skip`-je vagy gyengítése TILOS |
| `docs/ui/migration-status.md` | a MÉRT állapot |

**Tilos zóna:** `lib/features/progress/**` (a legacy fájl) · `lib/features/progress_v2/domain/**` · `lib/features/{practice,audio_analysis,song_trainer,gamification}/**` (olvasás igen, írás nem) · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0491)

### 5.1 A projekció DETERMINISZTIKUS és tiszta

Azonos bemenet → azonos kimenet; `DateTime.now()` és `Random` a builderben TILOS (a hívó adja az időt). **NEM elfogadható gyengítés:** „az aktuális dátum kell hozzá" — az paraméter, nem mellékhatás.

### 5.2 Hiányzó forrás = EXPLICIT üres állapot

Ha egy készség-tengelyhez nincs mérés, a projekció ezt jelöli, és a képernyő üres állapotot mutat. **NEM elfogadható gyengítés:** nulla értékkel „kitöltött" trend, ami visszaesésnek látszik.

### 5.3 A legacy útvonal átirányít, nem tűnik el

**NEM elfogadható gyengítés:** a `/progress` mélylink csendes megszüntetése.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A `/profile/progress` a `ProgressDashboardScreen`-t rendereli valós projekcióval | `progress_composition_test.dart` |
| A2 | A skill-detail útvonal a `SkillDetailScreen`-re visz, a kiválasztott készség azonosítójával | `progress_composition_test.dart` |
| A3 | A builder determinisztikus: ugyanaz a bemenet kétszer ugyanazt adja | `progress_projection_builder_test.dart` |
| A4 | Mérés nélküli készség EXPLICIT „nincs adat" jelölést kap (nem nullát) | `progress_projection_builder_test.dart` |
| A5 | A legacy `/progress` mélylink továbbra is működik (átirányít) | `legacy_route_redirect_test.dart` |
| A6 | A builderben nincs `DateTime.now()` és `Random` | statikus cella a `progress_projection_builder_test.dart`-ban |
| A7 | A képernyő-leltár és a navigációs őrök VÁLTOZATLANUL zöldek | a §7 gate |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A route átkötve marad a legacy képernyőre | A1 |
| A builder `DateTime.now()`-ot hív | A3 és A6 |
| Hiányzó mérés 0-val töltődik ki (hamis visszaesés) | A4 |
| A `/progress` mélylink 404-re fut | A5 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** cseréld a hiányzó-mérés ágat konstans `0`-ra, futtasd a §7 gate-et → az **A4** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/progress_v2/progress_projection_builder_test.dart test/app/routing/progress_composition_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/legacy_route_redirect_test.dart test/app/navigation/tab_state_restoration_test.dart test/ui/ui_inventory_test.dart
```

## 8. Implementációs sorrend

1. A MÉRÉS: milyen mezőket vár a két projekció, és melyikhez van forrás.
2. `progress_projection_builder.dart` (tiszta Dart, RED-ből).
3. `progress_providers.dart` + `public.dart`.
4. A router átkötése + a legacy átirányítás.
5. A két teszt + `migration-status.md` + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Hamis fejlődés-kép.** Kitöltött nullák visszaesésnek látszanak (A4).
- **Mélylink-törés.** A `/progress` megszüntetése mentett hivatkozásokat törne (A5).
- **Forráshiány.** Ha egy projekciós mezőhöz nincs adat, az `stopped` — nem szintetikus kitöltés.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
