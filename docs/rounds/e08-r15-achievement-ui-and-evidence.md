# E08-R15 — Achievement felület és bizonyíték-nézet

- **Státusz:** READY (pre-flight revízió 2026-08-21, kód olvasva: `main @ 6b2bdbe1`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 15
- **Kör-azonosító:** `E08-R15`
- **Branch:** `terra/e08-r15-achievement-ui-and-evidence`
- **Előfeltétel:** `E08-R14` merge-elve (achievement kiértékelő)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** `ADR 0378` — az atomi foglaló adta; az orchestrátor a pre-flightban
  rögzíti a UI-projekció és privacy-safe evidence szerződését.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R13 `hidden` mezőjének és az R14 haladás-projekciójának TÉNYLEGES felületét, valamint a `lib/features/analyze/` eredmény-modelljét (a bizonyíték-nézet NEM mutathat nyers audiót). Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/presentation/screens/achievements_screen.dart",
  "lib/features/gamification/presentation/screens/achievement_detail_screen.dart",
  "lib/features/gamification/presentation/widgets/achievement_tile.dart",
  "lib/features/gamification/public.dart",
  "lib/l10n/features/gamification_en.arb",
  "lib/l10n/features/gamification_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/gamification/presentation/achievements_screen_test.dart",
  "docs/rounds/e08-r15-achievement-ui-and-evidence.md",
]
gate_tests = [
  "test/features/gamification/presentation/achievements_screen_test.dart",
]
native_gate = false
```

## 0.0 Pre-flight revízió — 2026-08-21

- Az R13 tényleges contractja `AchievementDefinition.hidden` boolt,
  `AchievementCategory` enumot és három lowerCamelCase lokalizációs kulcsot
  ad. Az R14 `AchievementProgress.value` mezője kész, normalizált `0..1`
  projekció; a completiont `completedAt` és `rewardLedgerEntryId` jelzi.
  Erőforrás-acquire nincs a presentation hívási láncon (`rg -n "\\.acquire\\(" lib/features/gamification`).
- Az R14 diagnosztikai kódjai fail-closed kiértékelési hibák, nem
  felhasználónak szánt eredmény-magyarázatok. A részletes nézet ezért az ADR
  0378 szerinti caller-fed, zárt `AchievementEvidenceReasonCode` és kizárólag
  aggregált `current`/`target` értékekből épül. Stabil event/session ID,
  `AnalyzeResult`, chord/strum timeline, waveform, audio- vagy vision-adat nem
  része ennek a presentation contractnak.
- A locked hidden elem az `all` nézetben csak lokalizált, generikus titkos
  placeholderként jelenhet meg. Az `unlocked` nézetben csak completion után,
  az `in-progress` és category nézetben pedig completion előtt egyáltalán nem
  szerepelhet, mert a progress vagy kategória is részletet szivárogtatna.
- Az E99-R17 óta a lokalizáció elsődleges forrása a
  `lib/l10n/features/gamification_{en,hu}.arb`; a két `app_{en,hu}.arb`
  determinisztikus aggregátum. Az allowlist ezért név szerint tartalmazza a
  két forrásszegmenst és a generátor két kimenetét; közvetlen aggregate-edit
  tilos. A kötelező első lépés `dart run tool/gen_l10n_segments.dart --write`.
- **STOP-feloldás (Terra session `01a02243-…`).** A generátor által frissített
  `lib/l10n/app_localizations*.dart` és locale-specifikus Dart fájlok
  gitignore-olt Flutter build-outputok, nem tracked kör-diffek. Ezeket a friss
  klón kötelező `tools/prepare-flutter-generated.sh` előfeltétele és a
  `gen_l10n_segments.dart --write` utáni `flutter gen-l10n` állítja elő; nem
  kerülnek az `allowed_paths` listába, nem stage-elhetők és nem commitolhatók.
  A tracked scope változatlan: két feature-szegmens + két generált ARB-
  aggregátum. A wrapper scope-auditja a megálláskor `ok` volt, 9 engedélyezett
  tracked útvonallal; ezért ez nem H3, hanem a brief build-output határának
  dokumentált pontosítása.
- Az Analyze mért modellje `TimelineChord`, `TimelineStrum`, confidence és
  opcionális ML-diagnosztika listákat hordoz. Ezek UI-evidenceként való
  átadása a privacy-határ megsértése lenne; a kör tesztje import- és
  mezőszintű negatív őrt ad.
- A `2.0` text-scale határ körüli ellenőrző pontokat a kötelező
  `python3 -c` számítás adta: `1.99 / 2.0 / 2.01`; a szélesebb layout-mátrix
  továbbra is `1.0 / 2.0 / 3.0`.
- **Visszakeresett előzmény:** `lessons/L366` (a presentation legitim Flutter UI,
  de külön storage-import őr védi), `lessons/L372` (stabil achievement-ID
  folytonosság), `lessons/L374` (a nyers caller-inputot a határ előtt kell
  korlátozni), `adr/0289` (auditálható evidence), `adr/0290` (a UI nem számít
  jutalmat), `adr/0374` (lokalizált katalógus-contract). A teljes korpuszos
  keresés magát az R15 briefet és az R13 contractot hozta; az index friss,
  `HEAD 6b2bdbe1` állapotú.

A visszakeresés a kötelező sorrendben, az alábbi exact parancsokkal futott:

```bash
node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "E08-R15 achievement UI evidence hidden privacy localization presentation"
node tools/knowledge-rag.mjs --corpus lessons,halts --top 5 "achievement hidden semantics leak raw audio evidence UI reason codes"
node tools/knowledge-rag.mjs --top 5 "E08-R15 achievement UI achievements_screen achievement_detail_screen achievement_tile l10n"
```

**Kockázat = high, indoklás:** a felület hidden achievement címét,
leírását, progresszét vagy kategóriáját accessibility/semantics ágon is
kiszivárogtathatná, illetve nyers Analyze timeline-t tehetne audit-evidence
néven láthatóvá. Ez közvetlen privacy és product-truthfulness határ, ezért a
független correctness review mellett külön security review kötelező.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

Jól navigálható eredmény-lista és **közérthető** magyarázat: mindenki érti, miért kapta
(vagy miért nem kapta még) az adott eredményt — érzékeny adat felfedése nélkül.

## 2. Jelenlegi állapot — mért tények

- Az R14 normalizált haladás-projekciót, feloldási időbélyeget és ledger-
  hivatkozást ad; az R13 `hidden`, category és tier mezőket.
- `lib/features/gamification/presentation/screens/achievement*` **nem létezik**.
- A projekt a11y-mintája: `test/features/progress/weekly_bars_a11y_test.dart`.
- Az `ADR 0289` §2 szerint a bizonyíték auditálható; ebben a körben a UI csak
  zárt reason code-ot és aggregált értéket kap, session payloadot nem.
- Az új l10n kulcsok elsődleges forrása a gamification feature-szegmens; az
  `app_*.arb` generált aggregátum.

## 3. Scope

**Benne van:** all / unlocked / in-progress / kategória szűrők · haladás és feloldási dátum ·
a rejtett achievement részletei CSAK feloldás után · a bizonyíték-nézet az indok-kódokból
épít közérthető magyarázatot · üres állapot új felhasználónak · validált útvonal-argumentum.

**NINCS benne (tilos):**

- Nyers hang, felvétel-részlet vagy érzékeny session-adat megjelenítése (§5.2) — abszolút tilos.
- Jutalom-számítás a felületen (ADR 0290 §2).
- A katalógus vagy a kiértékelő módosítása (Kör 13/14).
- `lib/app/routing/**` — az útvonal-regisztráció a Kör 30 dolga; itt a képernyő maga készül el.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/presentation/screens/achievements_screen.dart` | **ÚJ** — a lista, szűrőkkel |
| `lib/features/gamification/presentation/screens/achievement_detail_screen.dart` | **ÚJ** — a részletek és a bizonyíték |
| `lib/features/gamification/presentation/widgets/achievement_tile.dart` | **ÚJ** — a listaelem |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `lib/l10n/features/gamification_en.arb` | elsődleges forrásszegmens — az ÚJ angol kulcsok |
| `lib/l10n/features/gamification_hu.arb` | elsődleges forrásszegmens — az ÚJ magyar kulcspárok |
| `lib/l10n/app_en.arb` | **GENERÁLT** — csak a szegmensgenerátor kimenete |
| `lib/l10n/app_hu.arb` | **GENERÁLT** — csak a szegmensgenerátor kimenete |
| `test/features/gamification/presentation/achievements_screen_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` (az útvonal-regisztráció a Kör 30) · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések (ADR 0378)

### 5.1 A rejtett achievement NEM SZIVÁROG

Feloldás előtt sem a cím, sem a leírás, sem a haladás nem látszik — és a widget-fa
sem tartalmazza őket (a szemantikus fában sem). A „kiszürkítve, de ott van” megoldás
képernyőolvasóval felolvasható, tehát szivárgás.

**NEM elfogadható gyengítés:** a szöveg megjelenítése `Opacity(0)` vagy `Visibility`
mögött. A szemantikus fa attól még tartalmazza.

### 5.2 A bizonyíték PRIVACY-SAFE — nincs nyers hang, nincs érzékeny részlet

A magyarázat az indok-kódokból és összesített metrikákból épül. Nyers felvétel,
hangminta vagy azonosítható session-részlet nem jelenik meg.

**NEM elfogadható gyengítés:** „csak a hullámforma” megjelenítése — az is a felvételből
származó adat.

### 5.3 A felület NEM SZÁMOL — minden érték készen érkezik

Az ADR 0290 §2 alkalmazása: a haladás és a feloldás az application-rétegből jön.

### 5.4 Az útvonal-argumentum VALIDÁLT

Ismeretlen vagy hibás achievement-azonosítóval a részletek képernyő értelmes
üres/hiba állapotot mutat, nem omlik össze — mélylinkről is érkezhet.

### 5.5 A bizonyíték contract ZÁRT és aggregált

A presentation egy zárt reason code-ot, valamint már aggregált current/target
értékeket kap. Nem kap stabil event/session azonosítót, timeline-listát,
waveformot, chord/strum részletet vagy tetszőleges user-szöveget. Az ismeretlen
reason code fordítási hiba helyett lokalizált, privacy-safe általános sort ad.

### 5.6 A locked hidden placeholder nem szivárogtat filteren keresztül

Az `all` nézet generikus placeholdert mutathat. Completion előtt a hidden elem
nem kerülhet `in-progress` vagy category eredménybe, mert már a progressz és a
kategória is részlet. Completion után minden normál szűrőben a valós tartalom
jelenik meg.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A négy szűrő (all / unlocked / in-progress / kategória) helyes halmazt ad | `achievements_screen_test.dart` — szűrő-mátrix |
| A2 | A rejtett achievement részletei feloldás ELŐTT a szemantikus fában SEM jelennek meg | `achievements_screen_test.dart` — szivárgás-cella |
| A3 | A feloldott elem haladást és feloldási dátumot mutat | `achievements_screen_test.dart` |
| A4 | A bizonyíték-nézet zárt indok-kódokból és aggregált értékekből épít szöveget, és NEM fogad vagy tartalmaz nyers audio/session/timeline adatot | `achievements_screen_test.dart` — reason-code + privacy-boundary cella |
| A5 | Üres állapot van új felhasználónak (nem üres lista, nem hiba) | `achievements_screen_test.dart` |
| A6 | Ismeretlen azonosítóval a részletek képernyő értelmes állapotot mutat, nem omlik össze | `achievements_screen_test.dart` |
| A7 | Minden szöveg ARB-kulcsból jön | `achievements_screen_test.dart` + review |
| A8 | 200%-os szövegskálán nincs levágás; a szemantikus címkék teljesek | `achievements_screen_test.dart` — a11y-mátrix |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A rejtett elem `Opacity(0)` mögött megjelenik | **A2** (a szemantikus fa tartalmazza) |
| A bizonyíték hullámformát mutat | **A4** |
| A szűrő a listát nem szűkíti, csak jelöl | **A1** |
| Ismeretlen azonosítón kivétel | **A6** |
| Beégetett angol szöveg | **A7** |
| Fix magasságú csempe | **A8** (200%-on levágás) |
| Locked hidden elem category vagy in-progress szűrőben marad | **A1 + A2** |
| Evidence modell session ID-t, waveformot vagy Analyze timeline-t fogad | **A4** privacy-boundary cella |

**A küszöb három kötelező cellája** (a szövegskála (`textScaleFactor`)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `1.99` | nincs levágás vagy túlcsordulás |
| **rajta** (a küszöbön) | `2.0` (200%, a projekt a11y-mércéje) | **nincs levágás, nincs túlcsordulás** — kötelező cella |
| a küszöb **fölött** | `2.01` | görgethető marad; összeomlás NEM elfogadható |

A hármas tömören: **alatt** → nincs overflow · **rajta** → nincs overflow ·
**fölötte** → görgethető, nincs overflow.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** jelenítsd meg a rejtett achievement címét `Opacity(0)` mögött, futtasd a gate-et →
az **A2** szivárgás-cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/presentation/achievements_screen_test.dart
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. Az ARB-kulcsok felvétele mindkét feature-szegmensbe, majd
   `dart run tool/gen_l10n_segments.dart --write`.
2. `achievement_tile.dart` — a listaelem, rejtett állapot kezelésével.
3. `achievements_screen.dart` — a négy szűrő és az üres állapot.
4. `achievement_detail_screen.dart` — részletek + bizonyíték az indok-kódokból.
5. Az útvonal-argumentum validációja.
6. a11y: szemantikus címkék, 200% szövegskála.
7. A `public.dart` export-sorai; a valódi-sértés próba §10-be.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A rejtett elem „kiszürkítése”.** Vizuálisan meggyőző, és képernyőolvasóval teljesen felolvasható — valódi szivárgás (A2).
- **A „csak a hullámforma”.** Ártalmatlannak tűnik, és a felvételből származó adat (A4).
- **A fix magasságú csempe.** 200%-os skálán levágja a magyar (hosszabb) szövegeket (A8).

## 10. Implementation handoff — az implementer tölti ki

- **Módosított fájlok:** `achievement_tile.dart` a locked hidden elemet
  generikus placeholderre és egyetlen kizárólagos semantics címkére zárja;
  `achievements_screen.dart` caller-fed all/unlocked/in-progress/category
  szűrőket és üres állapotot ad; `achievement_detail_screen.dart` exact ID
  validációt, locked-hidden safe állapotot, completion-dátumot és a zárt,
  aggregált evidence contractot ad. A `public.dart` a három presentation
  contractot exportálja. Az EN/HU gamification-szegmensek és generált ARB
  aggregátumok a UI-copyt tartalmazzák.
- **Tesztbizonyíték:** a filter-mátrix locked hidden elemet kizár az
  in-progress és category nézetből; a screen és detail semantics-cellák nem
  tartalmazzák a hidden title/description/progress értékeit; a privacy-őr
  tiltja az event/session ID-t, Analyze/timeline/waveform/payload mezőket és
  a szabad szöveget az evidence contractból. A 1.99 / 2.0 / 2.01 / 3.0
  text-scale cellák scrollolható ListView-t és kivételmentes futást mérnek.
- **Lokalizáció:** `dart run tool/gen_l10n_segments.dart --write` → EN és HU
  aggregátum írva; az `app_localizations*.dart` output ignore-olt maradt,
  nem staged és nem commitolandó.
- **Valódi-sértés próba:** a locked `Balanced practice week` címét ideiglenesen
  `Opacity(0)` mögé tettem. A célzott A2 teszt piros lett, mert a title
  widgetként megjelent; a privacy-safe `Semantics` + `ExcludeSemantics` fa
  visszaállítása után a célzott suite ismét zöld.
- **Ellenőrzések:** `flutter test
  test/features/gamification/presentation/achievements_screen_test.dart` →
  13/13 zöld; `tools/round-gate.sh
  test/features/gamification/presentation/achievements_screen_test.dart` →
  zöld (format, analyze, célzott test, architecture).

## 11. Review — a Claude tölti ki

- Correctness: `docs/reviews/e08-r15-review.md`
- Security/privacy: `docs/reviews/e08-r15-security.md`
