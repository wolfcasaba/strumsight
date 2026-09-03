# E15-R13 — A sáv lezárása: teljes migrációs mérés, vizuális regresszió és APK-evidencia

- **Státusz:** PRE-FLIGHT KÉSZ (előre megírva 2026-08-28 `main @ 4cb32eb0`; a §0.0 revíziók MÉRVE `main @ 9ba54399`, 2026-09-03)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 13 — a sáv ZÁRÓ köre
- **Kör-azonosító:** `E15-R13`
- **Branch:** `<motor>/e15-r13-ui-closure-and-release-evidence`
- **Előfeltétel:** `E15-R12` merge-elve (és a sáv minden korábbi köre)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — záró/mérési kör.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "visual regression closure migration status golden inventory"` → a `halts/round-status-E07-R30` (epic-záró minta) és **[ADR 0376](../adr/0376-ui-baseline-inventory-contract.md)** (UI baseline inventory és screenshot-corpus szerződés). A záró mérés ennek a szerződésnek a nyelvén beszél.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** futtasd a migrációs mérést és a `tool/check_screen_reachability.dart`-ot (E15-R03), és a §2 számait EZEKKEL írd felül. A kör állítása nem lehet „minden migrálva", ha a mérés mást mond.

## 0.0 Mit jelent itt a „kész"

A sáv célja nem a 96/96 formális szám, hanem hogy a felhasználó által ELÉRHETŐ minden képernyő a design-rendszeren legyen. Az `E15-R03` visszavonási terve szerint „visszavonandó" képernyők migrálatlanul is lezártnak számítanak — de akkor a tervben ott a nevesített visszavonó kör. A záró mérés ezt a KÉT halmazt (migrált + tervezetten visszavont) veti össze az elérhetőségi méréssel.

### 0.0.A Pre-flight revíziók (orchesztrátor, 2026-09-03, `main @ 9ba54399`)

A brief 2026-08-28-i mért állításai avultak; az alábbi öt revízió MÉRÉSBŐL
származik, és az ADR 0087 §2 szerint az orchesztrátor hatáskörében van (a kör
saját, még nem merge-elt briefje; a lista **szűkül**, nem tágul). ADR nem
születik: a `docs/adr/**` a §3 tilos zónája, és a kör mérési/záró kör (§5).

**R1 — a §2 számai lecserélve a MÉRT értékekre.** A parancsok és a kimenetük:

```bash
total=$(find lib/features -name '*_screen.dart' | wc -l)   # 96
for f in $(find lib/features -name '*_screen.dart'); do grep -q design_system "$f" && echo M; done | wc -l   # 91
dart run tool/check_screen_reachability.dart --format json  # measured=96 reachable=71 unreachable=25 flagGated=27
```

**91 / 96 migrált (94,792%), 5 legacy.** Mind az 5 legacy képernyő
**elérhető**, és mind az 5 `retire` verdikttel + nevesített utóddal szerepel a
`docs/ui/retirement-plan.md` §6-ban:

| Legacy képernyő | Verdikt | Utód |
|---|---|---|
| `library/screens/library_screen.dart` | `retire` (owner `E15-R04`) | `library_v2/.../unified_library_screen.dart` |
| `library/screens/session_detail_screen.dart` | `retire` (owner `E15-R04`) | `library_v2/.../library_item_detail_screen.dart` |
| `songs/screens/song_list_screen.dart` | `retire` (owner `E15-R04`) | `song_trainer/.../song_library_screen.dart` |
| `songs/screens/song_builder_screen.dart` | `retire` (owner `E15-R04`) | `song_trainer/.../song_editor_screen.dart` |
| `streak/screens/streak_screen.dart` | `retire` (owner `E15-R04`) | `gamification/.../gamification_hub_screen.dart` |

**R2 — a §0 STOP-protokoll pontosítva, és a visszavonás NYITOTT tétel.** Az
öt fenti képernyő **NEM** `stopped`-ok: a §0.0 második halmaza (tervezetten
visszavont) pontosan rájuk vonatkozik. `stopped` jelzés akkor és csak akkor
jár, ha a mérés olyan **elérhető + migrálatlan** képernyőt talál, amelynek
**nincs** `retire` verdiktje utóddal a `retirement-plan.md`-ben.

Ugyanakkor a terv nevesített gazda-köre (`E15-R04`) **lezárult a visszavonás
végrehajtása nélkül** — az [ADR 0471](../adr/0471-screen-reachability-is-measured-not-assumed.md)
D5 szerint a `retire` verdikt „javaslat egy külön, review-zott körre", nem
felhatalmazás törlésre, tehát ez nem szabálysértés, hanem **nyitott tétel**.
A kör kötelezően rögzíti a `legacy-backlog.md`-ben, dátummal, gazdával és
nevesített körrel, és a zárójelentés kimondja: a sáv záró állítása „minden
elérhető képernyő migrált **vagy** tervezetten visszavont", **nem** „a
visszavonás megtörtént".

**R3 — a mátrix bemeneti halmaza MÉRT, és gépi cella őrzi a teljességét.**
A mátrix bemenete a **mért elérhető halmaz (71)** ∪ `{ProgressDashboardScreen,
SkillDetailScreen}` (lásd R5). A §3 „elérhető halmaz × 16 variáns" előírása
áll; a MÉRT futásidő alapján ez nem robban: az `e13_r36_variant_matrix_test.dart`
**192 cellája 13 s** teszt-idő (`time flutter test …` → `real 0m18.873s`), azaz
~0,07 s/cella → 73 × 16 = 1168 cella ≈ 80–120 s.

A drága rész nem a cella, hanem a **képernyőnkénti fixture**. MÉRVE: a 71
elérhető képernyőből **46**-nak van már merge-elt pump-fixture-je a
`test/ui/goldens/**` alatt, további **24**-nek a `test/features/**` alatt, és
**egyetlennek** (`WrappedPreviewScreen`) nincs sehol. Ezért az implementációs
sorrend kötött (§8): **A-szint** = a 46 golden-fixture-ös képernyő + a két R5-ös,
**B-szint** = a maradék 25. Mindkét szint után külön commit.

A teljességet **gépi cella** őrzi, nem szöveg: a teszt futásidőben újraméri az
elérhető halmazt (ugyanazzal a szabállyal, mint a `check_screen_reachability`
deklaratív+imperatív csatornája, vagy a checker újrahívásával), és állítja, hogy

```
mért elérhető halmaz  ⊆  (mátrix képernyő-halmaza  ∪  dokumentált kizárás-lista)
```

A **kizárás-lista** minden tétele kötelezően hordoz (a) indokot és (b)
nevesített követő kört; az indok „nincs merge-elt fixture" MÉRT módon
kizárólag a `WrappedPreviewScreen`-re igaz. Minden további kizárás a review
mércéje alá esik (indoklás nélküli kizárás = MAJOR). A lista SOHA nem nőhet
csendben: a diffben látszik, és a zárójelentés §-ában tételesen szerepel.

**R4 — a `docs/ui/migration-status.md` KIKERÜL az engedélyezett listáról
(szűkítés).** MÉRVE: a párhuzamos slot köre, az `E16-R02`
(`tools/round-slots.py inflight-list`, indult 18:05:07Z, ág
`sonnet-impl/e16-r02-progress-projection-and-router-placeholders`) ugyanezt a
fájlt sorolja a saját `allowed_paths`-ában. A pipeline-prompt §4.1/2 szerint a
két kör fájlhalmazának **diszjunktnak** kell lennie; az átfedés feloldása itt
nem H3-halt, mert a kör saját, még nem merge-elt listájának **szűkítésével**
elhárul (ADR 0087 §2, „az engedélyezett-fájllista szűkítése"). A záró MÉRT
állapot ezért teljes egészében a `docs/ui/chapter-15-completion-report.md`-be
kerül (egyetlen új fájl, nulla átfedés), a `migration-status.md` érintetlen
marad. Egyetlen acceptance-cella sem hivatkozik rá (A1 → reachability-teszt +
mérés, A5 → zárójelentés), tehát a mérce nem gyengül.

**R5 — két, ma még elérhetetlen képernyő ELŐRE bekerül a mátrixba.** Az
`E16-R02` (fut) a `/profile/progress`-t a `ProgressDashboardScreen`-re köti át
és beköti a skill-detail útvonalat (annak briefje §3/A1–A2), tehát a merge-e
után a `ProgressDashboardScreen` és a `SkillDetailScreen` **elérhetővé válik**.
Az R3 gépi cellája ⊆-t állít, ezért a mátrixban lévő „még nem elérhető"
képernyő nem hiba — a hiányuk viszont a másik kör merge-e után azonnal pirosra
vinné a `main`-t. Mindkettőnek van merge-elt fixture-je
(`test/ui/goldens/e13_r31_screens_golden_test.dart`).

**Visszakeresés (ADR 0312, kötelező).** `--corpus lessons,halts,adr`, majd
teljes korpusz. Beépített találatok: **[ADR 0471](../adr/0471-screen-reachability-is-measured-not-assumed.md)**
(a `retire` nem végrehajtás — R2), **[L558](../LESSONS.md#l558)** (a
`flutter_test` alapértelmezett 800×600-as viewportja szélesebb ÉS magasabb
minden telefonnál → a mátrix minden cellája KÖTELEZŐEN állítsa be a
`tester.view.physicalSize`-t és a `devicePixelRatio`-t, különben a „nincs
túlcsordulás" akár üres fát mérhet), **[L477](../LESSONS.md#l477)** (mérd a
cella BUKÁSI KÉPESSÉGÉT, ne csak a zöldjét → §6.1 valódi-sértés próba),
**[L588](../LESSONS.md#l588)** (a riport-őr a hamis ÁLLÍTÁST méri, az
ELHALLGATÁST nem: a törölt sor minden cellán zöld marad → az A5 őre
**teljességet** is állítson, ne csak a jelen lévő sorok konzisztenciáját).

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "test/ui/goldens/e15_r13_full_variant_matrix_test.dart",
  "docs/ui/legacy-backlog.md",
  "docs/ui/chapter-15-completion-report.md",
  "docs/rounds/e15-r13-ui-closure-and-release-evidence.md",
]
gate_tests = [
  "test/ui/goldens/e15_r13_full_variant_matrix_test.dart",
  "test/ui/ui_inventory_test.dart",
  "test/tooling/screen_reachability_test.dart",
  "test/accessibility/closure_suite_test.dart",
]
native_gate = true
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a mérés migrálatlan, de ELÉRHETŐ képernyőt talál, a kimenet a `stopped` jelzés és a lista — a sáv nem zárható le „majdnem készen".

## 1. Cél

Bizonyítani, hogy minden elérhető képernyő a design-rendszeren van, hogy a felület 200%-os szövegskálán és mindkét locale-on ép, és hogy a felhasználó kap egy telepíthető APK-t, amin ez látszik.

## 2. Jelenlegi állapot — MÉRT tények (`main @ 9ba54399`, 2026-09-03, §0.0.A/R1)

- A sáv indulásakor **43 / 96** volt (44,8%). **MA: 91 / 96 migrált (94,792%), 5 legacy** — mind az 5 elérhető, mind az 5 `retire` verdiktes utóddal (§0.0.A/R1 tábla).
- Elérhetőség (`dart run tool/check_screen_reachability.dart --format json`): **96** mért képernyő, **71 elérhető**, **25 elérhetetlen**, **27 flag-kapuzott**.
- Fixture-fedettség (a mátrix költség-hajtója): a 71 elérhetőből **46**-nak van pump-fixture-je a `test/ui/goldens/**`, **24**-nek a `test/features/**` alatt, **1**-nek (`WrappedPreviewScreen`) sehol.
- `test/ui/goldens/` **22** golden-teszt fájl + **144** PNG; a Ch13 záró variáns-mátrixa (`e13_r36_variant_matrix_test.dart`) **192** cellát mér PNG nélkül, **13 s** teszt-idő alatt (`real 0m18.873s`).
- `docs/ui/legacy-backlog.md` §1: mind a 4+1 tétel **CLOSED** (E15-R02) — 0 nyitott elrendezési tétel. Nyitott marad a §2 (UI-architektúra-őr), §3 (legacy-lista, avult 53-as számmal), §5, §6.
- `test/ui/ui_inventory_test.dart` egzakt horgonya: **96** (`hasLength(96)`) — az A4 ezt méri.
- A `tools/round-gate.sh` és a CI a merge-kapu; az APK-t a `build-apk.yml` dispatch adja (ADR 0053) — a dispatch az orchesztrátoré.

## 3. Scope

**Benne van:** `test/ui/goldens/e15_r13_full_variant_matrix_test.dart` — PNG-mentes variáns-mátrix a MÉRT elérhető képernyő-halmazra (71) ∪ {`ProgressDashboardScreen`, `SkillDetailScreen`} (§0.0.A/R5) × {világos, sötét} × {en, hu} × {compact portrait 412×915, landscape 915×412} × {textScale 1.0, 2.0}, minden cella `RenderFlex`-túlcsordulás és pump-kivétel nélkül, **plusz a §0.0.A/R3 teljesség-cellája** (mért elérhető halmaz ⊆ mátrix ∪ kizárás-lista) · `docs/ui/legacy-backlog.md` lezárása (nyitott tétel csak dátummal, gazdával és nevesített körrel maradhat) · `docs/ui/chapter-15-completion-report.md` (mit szállított a sáv, mit mértünk, mi maradt — **ez hordozza a végleges MÉRT állapotot is**, §0.0.A/R4).

Minden fixture **ebben az EGY teszt-fájlban** él (a `test/support/**` már merge-elt fake-jeinek importja megengedett, ÚJ fájl felvétele oda nem — az a listán kívül esne, H3).

**NINCS benne (tilos):**

- `lib/**` módosítás (a záró kör MÉR, nem javít — talált hiba `stopped` + backlog).
- Új golden PNG felvétele ezen a boxon (ADR 0426).
- A `ui_inventory_test.dart` egzakt számának megváltoztatása.
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `test/ui/goldens/e15_r13_full_variant_matrix_test.dart` | ÚJ — a záró variáns-mátrix (minden fixture ebben a fájlban) |
| `docs/ui/legacy-backlog.md` | lezárás |
| `docs/ui/chapter-15-completion-report.md` | ÚJ — zárójelentés, a végleges MÉRT állapottal |
| `docs/rounds/e15-r13-ui-closure-and-release-evidence.md` | ez a brief (§10 handoff) |

**Tilos zóna:** `lib/**` · `test/ui/goldens/goldens/**` · `docs/adr/**` · `tools/**` · `.github/**` · `test/support/**` (ÚJ fájl) · **`docs/ui/migration-status.md`** (§0.0.A/R4 — a párhuzamos `E16-R02` kör listáján van; hozzáérés = scope-sértés)

## 5. Kötött architekturális döntések

Nincs ADR. Két kötelező szabály:

### 5.1 A záró állítás MÉRÉSBŐL jön

„Minden elérhető képernyő migrált" csak akkor írható le, ha a `check_screen_reachability.dart` + a migrációs mérés együtt ezt adja. **NEM elfogadható gyengítés:** kerekített vagy becsült arány a jelentésben.

### 5.2 A talált hiba LELET, nem javítandó munka

**NEM elfogadható gyengítés:** egy túlcsordulás gyors javítása a `lib/`-ben, ami elrejtené, mit mért a záró kör.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | MINDEN elérhető képernyő migrált **vagy** `retire`-verdiktes utóddal szerepel a `retirement-plan.md`-ben — és ezt a mátrix-teszt teljesség-cellája méri (mért elérhető halmaz ⊆ mátrix ∪ indokolt kizárás-lista, §0.0.A/R3) | `screen_reachability_test.dart` + `e15_r13_full_variant_matrix_test.dart` teljesség-cellája + a mérés kimenete a §10-ben |
| A2 | A záró variáns-mátrix MINDEN cellája túlcsordulás és kivétel nélkül renderel, minden cella a SAJÁT `tester.view.physicalSize`-ával (L558) | `e15_r13_full_variant_matrix_test.dart` |
| A3 | A `legacy-backlog.md`-ben nincs gazdátlan, dátum nélküli vagy kör nélküli nyitott tétel; a §3 avult „53 legacy" szakasza a MÉRT 5-re frissül; az `E15-R04` végre nem hajtott visszavonása NYITOTT tételként szerepel (dátum + gazda + nevesített kör) | a dokumentum + a mátrix-teszt szerkezeti cellája |
| A4 | A `ui_inventory_test.dart` egzakt száma VÁLTOZATLAN (`hasLength(96)`), és a diff nem érint `lib/**`-ot | a §7 gate + `git diff --stat` a §10-ben |
| A5 | A zárójelentés minden állítása parancs- vagy fájl-hivatkozású, **és az őre a TELJESSÉGET is méri** (nem csak a jelen lévő sorok konzisztenciáját — L588: egy törölt sor minden cellán zöld marad) | `docs/ui/chapter-15-completion-report.md` + a mátrix-teszt jelentés-cellái |
| A6 | ZÖLD teljes CI-futás a kör-branchen, és belőle telepíthető APK-artefaktum | orchesztrátor-dispatch linkje a §10-ben |

**Küszöb-cellahármas a szövegskálára** (a kötelező határ `2.0`, INKLUZÍV): a küszöb **alatt** (`1.5`) → minden cella zöld; **pontosan rajta** (`2.0`) → minden cella zöld, EZ az A2 feltétele; a küszöb **fölött** (`2.5`) → nem követelmény, és a `2.0` teljesítése nem hivatkozhat rá.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A mátrix csak a migrált képernyőket méri, az elérhető legacyket kihagyja | A1 |
| A jelentés „100%"-ot ír, miközben a mérés kevesebbet ad | A5 |
| Egy nyitott backlog-tétel gazda nélkül marad | A3 |
| A záró kör „menet közben" javít egy talált túlcsordulást | A4/A6 (a `git diff` a `lib/`-ben scope-sértés) |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vegyél ki egy elérhető képernyőt a mátrix bemeneti listájából, futtasd a §7 gate-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/ui/goldens/e15_r13_full_variant_matrix_test.dart test/ui/ui_inventory_test.dart test/tooling/screen_reachability_test.dart test/accessibility/closure_suite_test.dart
```

A záró mérés (a kimenet a §10-be):

```bash
dart run tool/check_screen_reachability.dart --format table
```

A teljes suite + property gate + APK a CI-ban fut (ADR 0053); a dispatch és a kiadás-link az orchesztrátoré.

## 8. Implementációs sorrend

1. A két mérés futtatása (elérhetőség + migráció) — a §0.0.A/R1 számai a te fádon is reprodukálhatók kell legyenek.
2. `e15_r13_full_variant_matrix_test.dart` **A-szint**: a 46 golden-fixture-ös elérhető képernyő + `ProgressDashboardScreen` + `SkillDetailScreen`, 16 cella/képernyő + a teljesség-cella (a kizárás-lista ekkor még a B-szint 25 képernyőjét tartalmazza, indokkal). **Commit.**
3. Ugyanaz a fájl, **B-szint**: a maradék 25 elérhető képernyő; minden bent maradó kizárás indokkal + nevesített körrel. **Commit.**
4. `legacy-backlog.md` lezárás (A3).
5. `chapter-15-completion-report.md` (A5) + a jelentés-őr cellái.
6. A valódi-sértés próba a §10-be; a CI-dispatch és az APK-link az orchesztrátortól.

## 9. Kockázatok

- **Kozmetikai zárás.** A „minden kész" állítás mérés nélkül (A1, A5).
- **Mátrix-robbanás.** Az elérhető halmaz × 16 variáns sok cella — a teszt fusson `pumpAndSettle` nélkül, ahol lehet, és a §7 futásideje maradjon a gate keretein belül.
- **Javítás-csábítás.** A talált hiba backlogba megy, nem a kör diffjébe (§5.2).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
