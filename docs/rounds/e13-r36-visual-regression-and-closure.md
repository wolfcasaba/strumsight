# E13-R36 — Vizuális regresszió, eszközös elfogadás és a migráció lezárása

- **Státusz:** READY (indítási pre-flight 2026-08-27, `main @ 126d0dfc` — lásd §0.0.B;
  előre megírva 2026-08-15, kód olvasva: `main @ 0f7afd9a`)
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
  "test/ui/goldens/",
  "test/accessibility/",
  "docs/ui/chapter-13-completion-report.md",
  "docs/ui/migration-status.md",
  "docs/ui/legacy-backlog.md",
  "HANDOFF.md",
  "docs/rounds/e13-r36-visual-regression-and-closure.md",
]
gate_tests = [
  "test/accessibility/semantics_contract_test.dart",
  "test/accessibility/tap_target_test.dart",
  "test/accessibility/screen_reader_copy_test.dart",
  "test/accessibility/closure_suite_test.dart",
  "test/ui/goldens/e13_r36_variant_matrix_test.dart",
]
native_gate = false
```

## 0.0 BRIEF-REVÍZIÓ — 2026-08-25, batch pre-flight (E13-R17…R36)

A brief 2026-08-15-én készült; ez a pre-flight `main @ 41fbd40` ellen mért.
**Visszakeresett előzmény:** [ADR 0307 §4](../adr/0307-parallel-round-execution.md)
(generált ARB-aggregátum), [L478](../LESSONS.md) (a pre-flight csak szűkíthet),
[L481](../LESSONS.md) (a lánc remote konténerből nem indítható). **Ez a kör az
EGYETLEN a Ch13 sávban, amelyet az R17–R35-öt megállító ARB-csapda NEM érint** —
a listáján nincs `lib/l10n/` útvonal.

**Kockázat = high, indoklás:** a kör a `tool/check_ui_architecture.dart`
mérce-eszközt hozza létre, és a golden-mátrix a teljes UI vizuális
elfogadási kapuja — egy hibás vagy üres mérce itt az egész fejezet
zöldjét hazuggá tenné.

### R1 — a golden-útvonal NEM egyezett a többi körével

**Mérve:** az `E13-R16 … E13-R35` MIND a **`test/ui/goldens/`** könyvtárba írja
a felvételeit (mind a 20 brief `allowed_paths`-án ez szerepel), ez a záró kör
viszont csak a **`test/goldens/`**-t engedte. Egyik könyvtár sem létezik ma;
a `test/goldens/` viszont a lánc végigfutása UTÁN sem fog — vagyis a záró
golden-mátrix egy örökre üres úton nézne, és a fejezet vizuális regressziós
kapuja **némán semmit sem mérne**.

Feloldás — user-engedéllyel (2026-08-25): a `test/ui/goldens/` felvéve. A
`test/goldens/` a listán marad, hogy a kör oda is szervezhesse a mátrixot, ha
úgy dönt — de a **meglévő felvételek helye a `test/ui/goldens/`**, és a
mátrixnak ezeket kell látnia.

### R2 — a `tool/check_ui_architecture.dart` MA nem létezik

A kör hozza létre; a `tool/` (Dart-eszközök) NEM azonos a `tools/`
(pipeline-szkriptek, H-GATEGUARD-védett) könyvtárral, tehát ez rendben van.
A meglévő golden-precedens `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő), az `test/accessibility/` könyvtár pedig
már létezik.

## 0.0.B BRIEF-REVÍZIÓ — 2026-08-27, INDÍTÁSI pre-flight (`main @ 126d0dfc`)

Orchestrátor: Claude (Opus 5), autonóm kör-pipeline (ADR 0087). Az alábbi
kilenc lelet MÉRVE készült; a revízió **kizárólag szűkít** (L478) — a
tágítás H3.

**Visszakeresett előzmény (ADR 0312, szűkített korpusz először):**
[L507](../LESSONS.md#l507) (a golden RÖGZÍT, nem ÍTÉL — a reviewer nézze meg a
PNG-t), [L516](../LESSONS.md#l516) (golden-teszt a lokális `round-gate.sh`
argumentumlistájában ezen a boxon MEGÁLL — ARM↔x86 drift),
[L517](../LESSONS.md#l517) (a `textScaler 2.0` keret két körben mért ki VALÓDI,
addig láthatatlan elrendezési hibát — köztük a kör ELŐTTI kódban),
[L486](../LESSONS.md#l486)/[L493](../LESSONS.md#l493) +
[ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md) (a
felvétel helye a kapu architektúrája), [L02](../LESSONS.md#l02) (ne írj elő
viselkedést lezárt fájlra / elérhetetlen állapotra),
[L180](../LESSONS.md#l180) (a deklarált osztályt néző allowlist gyengébb, mint
a neve sugallja), [ADR 0280](../adr/0280-accessibility-contract.md) (a
`test/accessibility/` hármas gépi szerződése).

### B1 — Előfeltétel: TELJESÜL

`docs/execution/pipeline-queue.tsv` E13 sorai: **36 sor, 35 `done`, 1
`pending`** — az egyetlen `pending` maga az `E13-R36`. Az R01–R35 tehát mind
merge-elve; a záró kör mércéje teljes rendszeren értelmes.

### B2 — `test/goldens/` TÖRÖLVE az `allowed_paths`-ból (brief-lint **S13**)

**Mérve:** `test/goldens/` a fában NEM létezik és a lánc végigfutása után sem
jött létre; a fa MÉRT golden-rétege a **`test/ui/goldens/`** — 20 kör-teszt
(`e13_r16…e13_r35_screens_golden_test.dart`) és a `test/ui/goldens/goldens/`
alatti PNG-készlet. A `test/goldens/` bejegyzés tehát NULLA fájlt fedett: néma
ellentmondás, amitől a lint zöldje semmit nem bizonyít.

**Feloldás:** a bejegyzés törölve. A `test/ui/goldens/` a listán marad — ez
**szigorúan kevesebb**, mint a szomszéd kör (E13-R33/R34/R35) user-jóváhagyott
listája, amely ugyanezt a könyvtárat ÉS a `test/ui/ui_inventory_test.dart`-ot
is tartalmazta.

### B3 — `tool/check_ui_architecture.dart` TÖRÖLVE (szűkítés) — nem huzalozható be

**Mérve:** a fában PONTOSAN két kapu-belépési pont futtat `tool/`-eszközt —
`tools/round-gate.sh:233` (`dart run tool/check_architecture.dart`) és
`.github/actions/flutter-gates/action.yml:21` (ugyanaz) —, és a meglévő
eszközök gépi őrei a `test/tooling/` alatt élnek
(`architecture_allowlist_guard_test.dart`). **Mind a három hely a brief SAJÁT
tilos zónája** (`tools/**`, `.github/**`, és a `test/tooling/` nincs a listán).

Egy olyan mérce-eszköz, amit semmi nem futtat és semmi nem őriz, **díszlet** —
pontosan az a hazug zöld, amit a §5.1 tilt. A behuzalozáshoz szükséges
lista-tágítás **H3** volna, ezért a helyes lépés a szűkítés.

**A követelmény nem vész el:** a `legacy-backlog.md` DÁTUMOZOTT tételt kap
(felelős + a szükséges governance-kör: `tools/round-gate.sh` architecture-lépés
és `.github/actions/flutter-gates` az `allowed_paths`-on), és a
`chapter-13-completion-report.md` nevesíti mint a fejezet egyetlen halasztott
mérce-elemét. **Az A7 cella ezt méri.**

### B4 — A golden-mátrix ALAKJA: állítás-mátrix + LEGFELJEBB 12 új PNG

A §3 „kockázat-alapú" mátrixa nem PNG-robbanás. Két MÉRT ok:

1. **Minden új PNG drága és architektúra-érzékeny.** Az ADR 0426 óta a
   felvétel útja `tools/golden-x86.sh record` (qemu-emulált x86 konténer); a
   `--update-goldens` ezen az aarch64 boxon TILOS. Az L516 azt is kimérte, hogy
   golden-teszt a lokális `round-gate.sh` argumentumlistájában MEGÁLL.
2. **Az L517 szerint a valódi hibákat nem a PNG fogta meg, hanem a keret.**
   Két egymást követő körben a `textScaler 2.0` keret mért ki 137 px-es,
   1577 px-es és 41 px-es `RenderFlex` túlcsordulást, amit a teljes CI-suite
   zölden átengedett.

**Ezért a kör két külön fájlt szállít a `test/ui/goldens/` alatt:**

| Fájl | Tartalom | Hol mérik |
|---|---|---|
| `e13_r36_variant_matrix_test.dart` | **PNG NÉLKÜL**: a kockázat-alapú képernyő-készlet × {light, dark} × {en, hu} × {compact portrait, landscape, medium, expanded} × {textScale 1.0, 2.0} — minden cella állítása: NINCS `RenderFlex` túlcsordulás, NINCS pumpolás közbeni kivétel | lokális `round-gate.sh` (§7) ÉS CI |
| `e13_r36_screens_golden_test.dart` | **LEGFELJEBB 12** új golden PNG a legkockázatosabb cellákra | **NEM** a lokális gate-ben (L516) — `tools/golden-x86.sh record` + `check`, majd CI |

Ha a kör egyetlen új PNG-t sem tesz fel, a második fájl **elhagyható** — az
A3 kötelező bizonyítéka ekkor a MEGLÉVŐ 20 golden-teszt zöldje a merge SHA
CI-futásán. Új vagy módosított PNG esetén a `tools/golden-x86.sh record` +
`check` lokális futása a push ELŐTT kötelező.

### B5 — A `lib/**`-ban TALÁLT elrendezési hiba: dátumozott, CSAK ZSUGORODÓ kizárólista

A `lib/**` a kör tilos zónája (§4), tehát egy a mátrix által kimért valódi
elrendezési hiba ebben a körben **nem javítható**. A `skip` és a
tolerancia-emelés tilos (§5.1). A feloldás a repó bevett idiómája
(`architectureAllowlist`, `tool/check_architecture.dart`): a
`e13_r36_variant_matrix_test.dart` egyetlen, a fájl tetején deklarált
**kizárólistát** kap, amelyre HÁROM megkötés áll:

- **elavult bejegyzésre PIROSRA vált** — egy megjavult cella nem maradhat
  elrejtve a listán (ez az `architectureAllowlist` saját szabálya);
- minden bejegyzés a **MÉRT hibát** hordozza (képernyő + cella + a mért
  túlcsordulás px-ben) és a **dátumot**, nem csak egy nevet — [L180](../LESSONS.md#l180)
  hibaosztálya pontosan a „deklarált osztályt néző" lista;
- minden bejegyzés tételesen megjelenik a `legacy-backlog.md`-ben is.

**Ez NEM A1-gyengítés, és a különbség mérhető:** a variáns-mátrix MA nem
létező mérce (nulla cella), tehát kizárólistával is szigorúan TÖBB fedést ad,
mint a mai állapot; egyetlen MEGLÉVŐ teszt sem kerül `skip`-be, egyetlen
meglévő tolerancia sem emelkedik, és a 20 meglévő golden-teszt érintetlen. Az
A1 cella tárgya továbbra is a MEGLÉVŐ mérce — az arra tett `skip`/tolerancia
változatlanul `blocked`.

### B6 — A9 szűkítése arra, ami ezen a boxon MÉRHETŐ

**Mérve:** a fában nincs keretidő-harness — `grep -rln
"FrameTiming|frameTime|frame_time|jank"` a `lib/`, `test/`, `tool/` fákon
egyetlen, nem ide tartozó találatot ad (`analyze_providers.dart`). Eszköz és
emulátor nincs, a `lib/**` tilos, a kamera/audio teljesítménye pedig §5.5
szerint eleve emberi kapu.

**A9 tehát arra szűkül, ami MÉRHETŐ, és a falszifikációja élesedik:** a
`completion-report.md`-nek tartalmaznia kell (a) a záró csomag MÉRT
futásidő-adatait, (b) a meglévő DSP-baseline mérés eredményét
(`test/tooling/real_audio_dsp_baseline_test.dart`) a migráció előtti értékkel
összevetve, ÉS (c) egy kimondott bekezdést arról, hogy a valódi UI-keretidő az
eszközös kapu tárgya (§5.5). **Bármelyik hiánya → A9 PIROS.** Kitalált vagy
nem reprodukálható „mért" érték szintén A9 PIROS.

### B7 — `token-debt.md` helye MÉRVE, és NINCS a listán

A §2 által hivatkozott fájl valódi útvonala **`docs/ui/baseline/token-debt.md`**
(nem `docs/ui/token-debt.md`), és az `allowed_paths`-on NEM szerepel. A kör
tehát **hivatkozza**, de nem írja — a baseline egy dátumozott
állapotrögzítés, átírása történelemhamisítás volna.

### B8 — ADR: nincs, és a pre-flight sem oszt

A záró kör nem hoz új architekturális döntést; a §5 normái merge-elt ADR-ekre
támaszkodnak ([0052](../adr/0052-ci-green-gate.md) zöld kapu,
[0053](../adr/0053-ci-full-test-suite.md) a teljes suite a CI-ban,
[0280](../adr/0280-accessibility-contract.md) a11y-szerződés,
[0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md)
golden-raszterizáció). Precedens ugyanebben a sávban: az **E13-R34** szintén
ADR nélkül zárult. `tools/round-slots.py reserve-adr` hívás tehát nem történt.

### B9 — Router CI a zöld kapu része

A kör hozzáér a `docs/rounds/**`-hoz, ami a `router-ci.yml` trigger-útvonala,
ezért a merge SHA-n a `router-ci` `success` volta is merge-feltétel (ADR 0086
§2, [L113](../LESSONS.md#l113)).

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
| `test/ui/goldens/` | a variáns-mátrix és a golden-referenciák (§0.0.B/B2, B4) |
| `test/accessibility/` | a záró accessibility-csomag |
| `docs/ui/chapter-13-completion-report.md` | **ÚJ** — a záró jelentés |
| `docs/ui/migration-status.md` | a migráció végállapota |
| `docs/ui/legacy-backlog.md` | **ÚJ** — dátumozott maradék |
| `HANDOFF.md` | a fejezet lezárása |
| `docs/rounds/e13-r36-…md` | a §10 handoff |

**Tilos zóna:** `lib/**` (MINDEN) · `docs/adr/**` · `docs/sdd/**` ·
`tools/**` · `.github/**` · `tool/**` (§0.0.B/B3) · `test/tooling/**` ·
`test/ui/` a `test/ui/goldens/`-en KÍVÜL · `docs/ui/baseline/**` (§0.0.B/B7).

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
| A3 | A golden-mátrix zöld, és minden eltérés indokolt a jelentésben | CI-futás + `completion-report.md`; új/módosított PNG esetén `tools/golden-x86.sh check` kimenete is (§0.0.B/B4) |
| A4 | Nincs ismert mikrofon/kamera életciklus-regresszió | a záró csomag |
| A5 | 200% text scale és képernyőolvasós kritikus folyamat működik | `test/accessibility/` + a variáns-mátrix `textScale 2.0` cellái |
| A6 | A legacy route-ok dokumentáltak vagy biztonságosan migráltak | `migration-status.md` |
| A7 | A megmaradt legacy elemek dátumozott backlogba kerültek — **beleértve a §0.0.B/B3 szerint elhalasztott UI-architektúra-guardot és a B5 kizárólista MINDEN tételét** | `legacy-backlog.md` |
| A8 | A completion report elkészült, kiadási ajánlással | `completion-report.md` |
| A9 | A jelentés a MÉRT futásidő-adatokat, a DSP-baseline összevetést ÉS a valódi keretidő eszközös korlátjának kimondását is tartalmazza (§0.0.B/B6) | `completion-report.md` mért, reprodukálható értékekkel |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA | Melyik őr méri |
|---|---|---|
| `skip` egy elbukó goldenre | **A1** | review-diff + CI |
| Golden-tolerancia emelése | **A1** | review-diff (a komparátor nulla toleranciájú) |
| A referencia frissítése indoklás nélkül | **A3** | `completion-report.md` szakasz + review |
| A legacy lista csendes ürítése | **A7** | `legacy-backlog.md` + review |
| A jelentés kihagyja a mért keretidőt, a DSP-összevetést vagy a §5.5 korlátot | **A9** | review (B6) |
| Egy kritikus képernyő offline állapot nélkül | **A2** | a záró csomag |
| Egy variáns-cella `RenderFlex` túlcsordulással, listára vétel NÉLKÜL | **A2/A5** | `e13_r36_variant_matrix_test.dart` (unit-cella) |
| Egy megjavult képernyő BENNMARAD a B5 kizárólistán | **A7** | a kizárólista elavult-bejegyzés-őre (piros) |
| A kizárólista bejegyzése nem hordoz mért px-értéket és dátumot | **A7** | a kizárólista alak-őre + review (L180) |

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
tools/round-gate.sh test/accessibility/semantics_contract_test.dart test/accessibility/tap_target_test.dart test/accessibility/screen_reader_copy_test.dart test/accessibility/closure_suite_test.dart test/ui/goldens/e13_r36_variant_matrix_test.dart
```

**A sor KÉT fájlt előre nevesít, amit ennek a körnek KELL létrehoznia:**
`test/accessibility/closure_suite_test.dart` (a §3 záró csomagja: route-,
engedély-, állapot-visszaállítás- és 200%-os text-scale cellák) és
`test/ui/goldens/e13_r36_variant_matrix_test.dart` (§0.0.B/B4). Hiányzó fájlnál
a gate megáll — ez szándékos: a kettő a kör gépi mércéje. Ha a kör további
teszt-fájlt vesz fel az engedélyezett könyvtárakba, a §7 sort ÉS az
`ai-router` `gate_tests` listáját EGYÜTT kell bővítenie.

**A golden-teszt (`e13_r36_screens_golden_test.dart`) ebbe a sorba NEM kerül
be** — az ARM↔x86 raszterizációs drift miatt ezen a boxon megállna a későbbi
lépések előtt ([L516](../LESSONS.md#l516)). Ha a kör új vagy módosított PNG-t
tesz fel, a push ELŐTT ez a két hívás kötelező (ADR 0426, §0.0.B/B4):

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r36_screens_golden_test.dart
tools/golden-x86.sh check test/ui/goldens/e13_r36_screens_golden_test.dart
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

1. A MEGLÉVŐ 20 golden-teszt (`test/ui/goldens/e13_r16…r35_*.dart`) állapotának
   felmérése — a zöldjük az A3 alapja; a felvételi környezet az ADR 0426 útja.
2. A `e13_r36_variant_matrix_test.dart` felépítése (§0.0.B/B4 mátrix).
   Az eltérések osztályozása: szándékos vs. regresszió — a regresszió NEM
   referencia-frissítés, és `lib/**` tilos, ezért a B5 kizárólistába megy,
   mért px-értékkel és dátummal.
3. A teljes semantics / érintési cél / túlcsordulás / route / engedély /
   állapot-visszaállítás csomag a `test/accessibility/` alatt.
4. A mérhető futásidő-adatok + DSP-baseline összevetés (§0.0.B/B6).
5. A legacy engedélyezőlista csökkentése (**docs-only**, `lib/**` tilos); a
   maradék dátumozott backlogba, a B3 halasztott guardot is beleértve.
6. `chapter-13-completion-report.md` — szándékos eltérések, korlátok, ajánlás.
7. A valós eszközös ellenőrzőlista előkészítése (kitöltés: emberi lépés).
8. `tools/round-gate.sh` a §7 szerint (+ `golden-x86.sh`, ha PNG változott).

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
