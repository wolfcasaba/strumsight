# E13-R08 — Adaptive scaffold és primary navigation

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 93a6c19a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 8
- **Kör-azonosító:** `E13-R08`
- **Branch:** `<motor>/e13-r08-adaptive-scaffold-and-navigation`
- **Előfeltétel:** `E13-R07` merge-elve (ikonográfia) + az R01 route-térképe
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0275`](../adr/0275-five-area-shell-behind-a-flag.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a TÉNYLEGES
> `lib/app/routing/` szerkezetét és az R01 `docs/ui/baseline/route-map.md`
> legacy-listáját — a §5.2 redirect-szerződés ezekre épül. A `go_router`
> verziója is számít (tab-stack API). Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/design_system/layouts/ss_adaptive_scaffold.dart",
  "lib/core/design_system/public.dart",
  "lib/app/routing/",
  "lib/app/home_shell.dart",
  "lib/app/config/feature_flags.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "docs/rounds/e13-r08-adaptive-scaffold-and-navigation.md",
]
gate_tests = [
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
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

A Today–Practice–Songs–Coach–Profile célarchitektúra bevezetése **flag mögött**,
compact bottom navigationnel és medium/expanded raillel (SDD Ch13 Kör 8).

## 2. Jelenlegi állapot — mért tények

- Az R01 route-térképe felsorolja a jelenlegi és cél-route párokat, a
  Ch13 §7.5 **tizenkét legacy route**-ot nevez meg.
- `lib/app/config/feature_flags.dart` — a flagek **három** helyen bővülnek
  (konstruktor, `FeatureFlags.forEnvironment`, `toString()`) és az `==`-ben;
  a mért 51 teszt-hívóhely opcionális `= false` defaulttal nem törik el.
- A design system R02–R07 rétegei készen állnak.

## 3. Scope

**Benne van:** `SsAdaptiveScaffold` layout-resolver (compact / medium /
expanded / wide) · az öt cél-destination **flag mögött**, első körben legacy
képernyő-adapterekkel · NavigationRail medium/expanded módban · a legacy
route-ok **redirect/alias térképe deep-link megőrzéssel** · billentyű- és
fókusz-viselkedés expanded módban · Stage Mode route-okon a primary navigation
elrejtése.

**NINCS benne (tilos):** a legacy képernyők tartalmi átírása (Kör 16–35) · a
flag **bekapcsolása** alapértelmezetten (ez user-döntés) · `lib/features/**` ·
`lib/core/theme/**` · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `layouts/ss_adaptive_scaffold.dart` | **ÚJ** — a breakpoint-resolver |
| `public.dart` | az export bővítése |
| `lib/app/routing/` | az öt destination + a redirect-térkép |
| `lib/app/home_shell.dart` | a shell bekötése |
| `lib/app/config/feature_flags.dart` | **egyetlen** új flag, defaultból KI |
| `test/app/navigation/*_test.dart` (3) | a §6 cellái |
| `docs/rounds/e13-r08-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0275)

### 5.1 Az új shell FLAG mögött, alapértelmezetten KIKAPCSOLVA

A teljes információs architektúra nem migrálható egyszerre. A flag
bekapcsolása **user-döntés**, nem ezé a köré.

**NEM elfogadható gyengítés:** az új shell alapértelmezett bekapcsolása „hogy
látszódjon a munka". Az 51 képernyő navigációját kockáztatná egyetlen körben.

### 5.2 EGYETLEN legacy link sem törhet el

Minden legacy route-nak redirect vagy alias jár, a deep-link paraméterek
megőrzésével. Ez acceptance-cella (A2), nem törekvés.

**NEM elfogadható gyengítés:** „ez a route úgysem használt". A megosztott és a
könyvjelzőzött linkek kívül esnek a kódon — nem mérhető, hogy használt-e.

### 5.3 Nincs route-hurok

A redirect-térkép nem vezethet önmagára vagy körbe. Ez gépi cella (A5), nem
szemrevételezés.

### 5.4 A kiválasztott tab állapota megmarad

Tabváltás és visszatérés után a stack nem esik szét. A `go_router` verziója
befolyásolja az API-t — a pre-flight ezt méri.

### 5.5 Stage route alatt NINCS primary navigation

A Stage Mode teljes felületet kap; a bottom nav vagy rail nem vesz el helyet és
nem hív véletlen navigációra játék közben.

### 5.6 A legacy képernyők ADAPTERREL kapcsolódnak

Az öt destination első körben a MEGLÉVŐ képernyőket mutatja. A tartalmi
migráció külön körök dolga — így a shell külön mérhető a tartalomtól.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az öt célterület elérhető, a flag defaultból **KI** | `adaptive_scaffold_test.dart` |
| A2 | Minden legacy route redirectel, a deep-link paraméterek megmaradnak | `legacy_route_redirect_test.dart` |
| A3 | A kiválasztott tab állapota megmarad tabváltás után | `tab_state_restoration_test.dart` |
| A4 | Stage route alatt nincs primary navigation | `adaptive_scaffold_test.dart` |
| A5 | Nincs route-hurok (a redirect-térkép aciklikus) | `legacy_route_redirect_test.dart` |
| A6 | Minden breakpointon a helyes navigációs forma jelenik meg | `adaptive_scaffold_test.dart` |
| A7 | A flag KI állapotában a mai navigáció változatlan | a teljes suite zöld |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A flag defaultból BE | **A1** + A7 |
| Kimarad egy legacy redirect | **A2** |
| A redirect eldobja a query-paramétert | A2 |
| Tabváltáskor a stack elvész | **A3** |
| Stage-en látszik a bottom nav | A4 |
| A → B → A redirect-kör | **A5** |

**A breakpoint három kötelező cellája** (a küszöb: a compact/medium határ,
**600 dp**):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | 599 dp | **compact** — bottom navigation |
| rajta (a küszöbön) | **600 dp** | **medium** — rail (a határ a medium-hoz tartozik) |
| a küszöb fölött | 840 dp | expanded — rail, kiterjesztett címkékkel |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vegyél ki egy legacy
route-ot a redirect-térképből → az **A2** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/legacy_route_redirect_test.dart test/app/navigation/tab_state_restoration_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `ss_adaptive_scaffold.dart` — a négy módú resolver + a három breakpoint-cella.
2. Egyetlen új flag a `feature_flags.dart` **mindhárom** bővülési pontján,
   defaultból KI.
3. Az öt destination legacy adapterekkel.
4. A redirect/alias térkép + az aciklikussági cella.
5. Stage route: primary navigation elrejtve.
6. Tab-állapot megőrzés + a hozzá tartozó cella.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A flag bekapcsolásának kísértése.** Az új shell látványos, és 51 képernyő
  navigációját viszi magával (A1).
- **A „nem használt" legacy route.** Kívülről érkező linkeket a kód nem lát —
  a törött deep-link csak a felhasználónál derül ki (A2).
- **A `go_router` verziófüggő tab-stack API.** A pre-flight mérése nélkül a
  megőrzés csendben nem működik (A3).
- **A flagek háromhelyes bővülése.** Egy kihagyott hely némán régi értéket ad.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
