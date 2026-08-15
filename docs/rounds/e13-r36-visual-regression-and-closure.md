# E13-R36 — Vizuális regresszió, eszközös elfogadás és a migráció lezárása

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 0f7afd9a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 36 — **a fejezet ZÁRÓ köre**
- **Kör-azonosító:** `E13-R36`
- **Branch:** `<motor>/e13-r36-visual-regression-and-closure`
- **Előfeltétel:** `E13-R01`–`E13-R35` MIND merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a záró kör nem hoz új architekturális döntést.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd, hogy MIND a 35 korábbi
> kör merge-elve van (`docs/execution/pipeline-queue.tsv` E13 sorai `done`).
> Ha bármelyik nyitott, `blocked` jelzéssel állj meg — a záró kör mércéje csak
> teljes rendszeren értelmes. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "test/goldens/",
  "test/accessibility/",
  "tool/check_ui_architecture.dart",
  "docs/ui/chapter-13-completion-report.md",
  "docs/ui/migration-status.md",
  "docs/ui/legacy-backlog.md",
  "HANDOFF.md",
  "docs/rounds/e13-r36-visual-regression-and-closure.md",
]
gate_tests = [
  "test/accessibility/semantics_contract_test.dart",
  "test/accessibility/tap_target_test.dart",
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

A Chapter 13 UI-rendszerének **minőségkapus lezárása**: golden-mátrix, a legacy
függőségek csökkentése és a valós eszközös elfogadás előkészítése
(SDD Ch13 Kör 36).

## 2. Jelenlegi állapot — mért tények

- Az R01–R35 lefedte a teljes design-rendszert és mind a migrációs képernyőket.
- Az R01 `token-debt.md`-je és az R02 `migration-status.md`-je adja a kiindulási
  legacy-listát — ez a kör méri, mennyi maradt.
- A CLAUDE.md szabálya: a **teljes** suite és az APK a CI-ban fut, nem ezen a
  boxon; a merge-küszöb változatlan.

## 3. Scope

**Benne van:** a kockázat-alapú golden-mátrix futtatása és stabilizálása
(dark / light / high contrast × en / hu × compact / landscape / medium /
expanded × kritikus text-scale) · a teljes semantics-, érintési cél-, túlcsordulás-,
route-, engedély- és állapot-visszaállítási csomag · a UI keretidő mérése aktív
Live/Song/Vision sessionben · a legacy téma-, route- és import-engedélyezőlista
**csökkentése**, a maradékhoz **dátumozott** backlog · a
`chapter-13-completion-report.md` a szándékos golden-eltérésekkel, ismert
korlátokkal és kiadási ajánlással · a valós eszközös ellenőrzőlista
**előkészítése** (a kitöltés emberi lépés).

**NINCS benne (tilos):** **a mérce gyengítése** — golden-küszöb lazítása, teszt
kikapcsolása vagy `skip` (H-GATEGUARD, emberi döntés) · új funkció · `lib/**`
bármely fájlja **a legacy-engedélyezőlista csökkentésén kívül, ami ebben a
körben CSAK dokumentációs** · `docs/adr/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `test/goldens/` | a golden-mátrix és a referenciák |
| `test/accessibility/` | a záró accessibility-csomag |
| `tool/check_ui_architecture.dart` | a UI-token és import guard |
| `docs/ui/chapter-13-completion-report.md` | **ÚJ** — a záró jelentés |
| `docs/ui/migration-status.md` | a migráció végállapota |
| `docs/ui/legacy-backlog.md` | **ÚJ** — dátumozott maradék |
| `HANDOFF.md` | a fejezet lezárása |
| `docs/rounds/e13-r36-…md` | a §10 handoff |

**Tilos zóna:** `lib/**` (MINDEN) · `docs/adr/**` · `docs/sdd/**` ·
`tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A mérce NEM gyengíthető a zöldért

Ez a kör a legnagyobb nyomás alatt áll: a záró kapunál minden piros teszt
kikapcsolásra hív. A küszöb lazítása, a `skip` és a golden-tolerancia emelése
**emberi döntés** (H-GATEGUARD) — az implementer ilyenkor `blocked` jelzéssel
megáll.

**NEM elfogadható gyengítés:** a golden-tolerancia emelése „a renderelési
eltérés miatt". Ha a környezet ingadozik, a környezetet kell rögzíteni.

### 5.2 A golden-eltérés SZÁNDÉKOSKÉNT dokumentált, nem csendben elfogadott

Minden megváltozott referencia mellé indoklás kerül a jelentésbe. Az „elfogadtam
az újat" önmagában nem bizonyíték.

### 5.3 A legacy maradék DÁTUMOZOTT backlogot kap

Ami nem migrálódott, az nem tűnhet el a listáról. Minden megmaradt elem
felelőssel és dátummal szerepel.

### 5.4 A teljes suite és az APK a CI-ban fut

A CLAUDE.md és az ADR 0053 szabálya: itt csak az érintett terület fut, a teljes
mérce a CI-é. A jelentés a CI-futás linkjére hivatkozik.

### 5.5 A valós eszközös próba EMBERI lépés

Az emulátoron mért kamera- és audio-teljesítmény nem bizonyíték. A kör az
ellenőrzőlistát **előkészíti**; az aláírt eredmény a kiadási kapu része, nem
merge-feltétel.

### 5.6 A design-refaktor NEM ronthatja a DSP/ML késleltetést

A keretidő-mérés összeveti az aktív session teljesítményét a migráció előtti
állapottal; indokolatlan romlás a jelentésben nevesítve jelenik meg.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | **Nulla mérce-gyengítés** — nincs új `skip`, kikapcsolt teszt vagy emelt tolerancia | `git diff` + review |
| A2 | Minden kritikus képernyőnek van betöltés/üres/hiba/offline/engedély állapota, ahol releváns | a záró csomag |
| A3 | A golden-mátrix zöld, és minden eltérés indokolt a jelentésben | CI-futás + `completion-report.md` |
| A4 | Nincs ismert mikrofon/kamera életciklus-regresszió | a záró csomag |
| A5 | 200% text scale és képernyőolvasós kritikus folyamat működik | `test/accessibility/` |
| A6 | A legacy route-ok dokumentáltak vagy biztonságosan migráltak | `migration-status.md` |
| A7 | A megmaradt legacy elemek dátumozott backlogba kerültek | `legacy-backlog.md` |
| A8 | A completion report elkészült, kiadási ajánlással | `completion-report.md` |
| A9 | A keretidő nem romlott indokolatlanul aktív sessionben | `completion-report.md` mért értékekkel |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `skip` egy elbukó goldenre | **A1** |
| Golden-tolerancia emelése | **A1** |
| A referencia frissítése indoklás nélkül | **A3** |
| A legacy lista csendes ürítése | **A7** |
| A jelentés kihagyja a mért keretidőt | A9 |
| Egy kritikus képernyő offline állapot nélkül | A2 |

**A záró kapu három kötelező cellája** (a küszöb: a golden-mátrix állapota):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | egy vagy több golden piros, indoklás nélkül | a kör **nem zárható** — `blocked` |
| rajta (a küszöbön) | **minden golden zöld, minden eltérés indokolt** | a kör zárható |
| a küszöb fölött | zöld + valós eszközös ellenőrzőlista aláírva | kiadásra ajánlható |

**Falszifikáció (docs-only rész, KÖTELEZŐ):** a `completion-report.md`-ből a
„szándékos golden-eltérések" szakasz törlése teszi az **A3** cellát
bizonyíthatatlanná; a `legacy-backlog.md` dátum-oszlopának törlése az **A7**-et.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/accessibility/semantics_contract_test.dart test/accessibility/tap_target_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

A **teljes** suite, a golden-mátrix és az APK a CI-ban fut (ADR 0053) —
a dispatch és a futás-link a Claude oldala:

```bash
gh workflow run build-apk.yml --ref <kör-branch>
```

## 8. Implementációs sorrend

1. A golden-mátrix futtatása; a rögzített font/render környezet ellenőrzése.
2. Az eltérések osztályozása: szándékos vs. regresszió — a regresszió JAVÍTÁS,
   nem referencia-frissítés.
3. A teljes semantics / érintési cél / túlcsordulás / route / engedély /
   állapot-visszaállítás csomag.
4. Keretidő-mérés aktív Live/Song/Vision sessionben.
5. A legacy engedélyezőlista csökkentése; a maradék dátumozott backlogba.
6. `chapter-13-completion-report.md` — szándékos eltérések, korlátok, ajánlás.
7. A valós eszközös ellenőrzőlista előkészítése (kitöltés: emberi lépés).
8. `tools/round-gate.sh` a §7 szerint + CI-dispatch.

## 9. Kockázatok

- **A záró kör gyengítési nyomása.** Itt a legnagyobb a kísértés `skip`-re és
  toleranciára; ez H-GATEGUARD, emberi döntés (A1).
- **A platformfüggő golden.** Rögzített font/render környezet nélkül ingadozik
  — a környezetet kell rögzíteni, nem a küszöböt (A3).
- **Az emulátoros „bizonyíték".** A kamera- és audio-teljesítmény valós
  eszközön dől el; a jelentés ezt kimondja (§5.5).
- **A csendben ürített legacy lista.** Késznek látszó fejezet, ami valójában
  elrejtett adósság (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
