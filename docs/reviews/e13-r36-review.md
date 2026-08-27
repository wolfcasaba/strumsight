# E13-R36 review — Vizuális regresszió, eszközös elfogadás és a Chapter 13 lezárása

- **Kör:** `E13-R36` (SDD Ch13, Kör 36 — a fejezet ZÁRÓ köre)
- **Brief:** `docs/rounds/e13-r36-visual-regression-and-closure.md` (§0.0.B indítási pre-flight, B1–B9)
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude (Opus 5), autonóm kör-pipeline orchestrátor/ellenőrző szék
- **Review-lt SHA-k:** `cb774521` (első menet) → `0db1db91` (javító kör)
- **Dátum:** 2026-08-27

> A review READ-ONLY volt: production/teszt kódot NEM írtam. A próbatesztek
> eldobható klónokban futottak (`/tmp/review-e13-r36`, `/tmp/review-e13-r36b`),
> a kör-ág érintése nélkül; a klónok a próbák után `git status` szerint
> tiszták voltak.

## 1. Jelzés és handoff

| | |
|---|---|
| `.codex-round-status` (1. menet) | `status=done`, `head=cb774521`, `dirty_files=1` |
| `.codex-round-status` (javító kör) | `status=done`, `head=0db1db91`, `dirty_files=1` |
| §10 handoff | kitöltve, tételes „mit mértem, milyen paranccsal" listával |

A `dirty_files=1` **kivizsgálva** (ADR 0052 / `docs/LESSONS.md` L21 kötelező
ellenőrzése): mindkét jelzés után a munkapéldány `git status --short` kimenete
**üres** — a számláló a jelzés pillanatában a gitignore-olt saját
`.codex-round-status` fájlt látta. Nincs elveszett vagy be nem commitolt munka.

A handoff **nem** tulajdonít magának nem futtatott mérést: kimondja, hogy a
meglévő 20 golden-PNG tesztet szándékosan NEM futtatta ezen az aarch64 boxon
(L516/L493 ARM↔x86 drift), és hogy a CI-dispatch az orchestrátoré.

## 2. Scope-audit

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e13-r36 \
    --brief docs/rounds/e13-r36-visual-regression-and-closure.md --base 066c97ee
Legacy scope audit OK (066c97ee182d..cb774521525a, 6 changed path(s), 0 generated/ignored)
```

A javító kör után is (`066c97ee..0db1db91`) ugyanez, változatlan fájlhalmazon.
A kör **hat** fájlt érintett, mind az `allowed_paths`-on:

```
M docs/rounds/e13-r36-visual-regression-and-closure.md
A docs/ui/chapter-13-completion-report.md
A docs/ui/legacy-backlog.md
M docs/ui/migration-status.md
A test/accessibility/closure_suite_test.dart
A test/ui/goldens/e13_r36_variant_matrix_test.dart
```

`lib/**` — a kör tilos zónája — **nulla fájl**. Ez a kör egyetlen production
Dart sort sem írt.

## 3. A kötelező gate — SAJÁT kezű újrafuttatás izolált klónban

A brief §7 pontos parancsa, csonkítatlanul, külön klónban mindkét SHA-n:

| Lépés | `cb774521` | `0db1db91` |
|---|---|---|
| [1] format (2154 fájl) | ZÖLD | ZÖLD |
| [2] analyze (`lib/ test/ tool/`) | ZÖLD | ZÖLD |
| [3] `semantics_contract_test.dart` | ZÖLD (13) | ZÖLD (13) |
| [4] `tap_target_test.dart` | ZÖLD (6) | ZÖLD (6) |
| [5] `screen_reader_copy_test.dart` | ZÖLD (8) | ZÖLD (8) |
| [6] `closure_suite_test.dart` | ZÖLD (12) | ZÖLD (12) |
| [7] `e13_r36_variant_matrix_test.dart` | ZÖLD (**192**) | ZÖLD (**192**) |
| [8] architecture | ZÖLD | ZÖLD |
| [9] secrets | ZÖLD | ZÖLD |
| [10] l10n | ZÖLD | ZÖLD |

`MINDEN GATE ZÖLD`, `GATE_EXIT=0` mindkét futáson.

## 4. Próbatesztek — valódi-sértés próbák (a zöld gate NEM bizonyíték)

A kör központi mechanizmusa a **csak zsugorodó kizárólista** (brief §0.0.B/B5).
Három eldobható próbával mértem, hogy nem díszlet. Mindhárom a
`/tmp/review-e13-r36` klónban futott, utána visszaállítva.

### P1 — a dokumentált `lib/**` defekt VALÓDI

Töröltem a `live|light|hu|landscape|2.0` kizárólista-bejegyzést.

```
00:04 +43 -1: live|light|hu|landscape|2.0 [E]
unexpected RenderFlex overflow of 34.0px — either this is a new lib/**
regression (blocked, this round cannot fix lib/**) or a dated _ExcludedCell
entry is missing
```

**A 34 px-es túlcsordulás tőlem függetlenül reprodukálódott**, pontosan azzal
az értékkel, amit a `legacy-backlog.md` §1 3. sora állít. A kizárás nem
kitalált mentesség, hanem mért defekt.

### P2 — a stale-entry őr VALÓDI

Felvettem egy hamis kizárást egy ma is ZÖLD cellára
(`tuner|light|en|compact_portrait|1.0`, 99 px).

```
00:05 +63 -2: tuner|light|en|compact_portrait|1.0 [E]
STALE exclusion-list entry (measured 99.0px on 2026-08-27): this cell no
longer overflows — remove the _ExcludedCell entry and its
docs/ui/legacy-backlog.md mirror
```

A lista tehát **nem tud csendben nőni és nem tud elavulni** — pontosan az
[L180](../LESSONS.md#l180) hibaosztálya ellen véd, amit a B5 előírt.

### P3 — a closure-suite kizárása is MÉR, nem deklarál

A `297` px-es várt értéket `298`-ra írtam:

```
00:02 +7 -1: A4 … DATED EXCLUSION … [E]
STALE exclusion: lib/features/onboarding/screens/permission_primer_screen.dart
no longer overflows …
```

A cella tehát a tényleges `FlutterError` jelentést méri, nem egy konstanst
állít magáról.

### P4 — a `migration-status.md` mért száma reprodukálható

```
$ total=$(find lib/features -name '*_screen.dart' | wc -l)
$ mig=$(for f in $(find lib/features -name '*_screen.dart' | sort); do \
        grep -q design_system "$f" && echo x; done | wc -l)
total=96 migrated=43   → 44.8%
```

Pontosan a jelentés állítása (43/96, 44,8%). A dokumentum a mérőparancsot is
közli, tehát a szám nem bemondás.

## 5. Acceptance criteria — tételesen

| # | Verdikt | Bizonyíték |
|---|---|---|
| **A1** — nulla mérce-gyengítés | **TELJESÜL** | A diffben egyetlen új `skip`, `@Skip`, kikapcsolt cella vagy tolerancia-emelés sincs (`git diff … \| grep -E "skip\|tolerance\|--update-goldens"` csak a TILTÁST kimondó doc-commenteket adja). Meglévő teszt- vagy PNG-fájl **nem** módosult: a diff hat fájlja közül négy dokumentum, kettő ÚJ teszt. |
| **A2** — kritikus képernyők állapotai | **RÉSZBEN, KIMONDVA** | A záró csomag route-, engedély-, állapot-visszaállítás- és 200%-cellákat mér; a per-képernyő betöltés/üres/hiba/**offline** állapotot az R16–R35 saját suite-jai fedik. A jelentés §4 ezt a javító kör után **explicit korlátként kimondja** (NOTE-1 zárva). A cella nem hazudik teljességet. |
| **A3** — golden-mátrix zöld, minden eltérés indokolt | **TELJESÜL** | Új/módosított PNG: **nulla** (a `test/ui/goldens/goldens/` fa érintetlen), tehát nincs indokolandó eltérés — a report §2 ezt ki is mondja. A meglévő 20 golden-teszt zöldje a merge SHA CI-futásának evidenciája (§7), ahogy a §0.0.B/B4 előírta. |
| **A4** — nincs ismert mic/kamera életciklus-regresszió | **TELJESÜL** | `closure_suite_test.dart` A4-csoport: visszakérhető és véglegesen megtagadt mikrofon-engedély, injektált `openSettings`, megtagadott kamera-gateway melletti Vision Setup — mind kivétel nélkül; a fake engine-ek `addTearDown`-nal zárnak. |
| **A5** — 200% text scale + képernyőolvasós kritikus folyamat | **TELJESÜL** | A closure suite MINDEN cellája `textScale: 2.0` mellett megy, és tapint (nem csak renderel): a Settings → Sign in → hitelesítés → visszapop kör végigfut. A mátrix 96 `textScale 2.0` cellája ezen felül van. A screen-reader szerződést a változatlan `screen_reader_copy_test.dart` (8 zöld) őrzi. |
| **A6** — legacy route-ok dokumentáltak vagy migráltak | **TELJESÜL** | A closure suite A6-csoportja öt route-cellát mér (welcome, live, settings, tuner, ismeretlen út → recovery). A `migration-status.md` per-feature bontása + a `legacy-backlog.md` §4 a meglévő `legacy_route_redirect_test.dart` gépi őrre mutat (nem másolja le — helyesen). |
| **A7** — dátumozott backlog | **TELJESÜL** | `legacy-backlog.md`: §1 mind az 5 kizárás (fájl:sor, cella, px, dátum, forrás-teszt, felelős, miért nem javítható), §2 a halasztott UI-architektúra-guard, §3 az 53 megmaradt képernyő felelőssel és dátummal. A lista nem üríthető csendben: a P1/P2/P3 próbák szerint a tükrözött cellák gépi őrrel járnak. |
| **A8** — completion report kiadási ajánlással | **TELJESÜL** | `chapter-13-completion-report.md` §6: „Recommend merge", a §5.5 eszközös kapu kifejezett fenntartásával, és a kimondással, hogy a fejezet nem „teljesen migrált", hanem „a jelenlegi terjedelmén minőségkapuzott". |
| **A9** — mért futásidő + DSP-összevetés + a §5.5 korlát | **TELJESÜL** | §3a: a gate `real 1m50.506s`, lépésenkénti bontással. §3b: `real_audio_dsp_baseline_test.dart` 9/9 zöld, és a mérőfájl `git log`-ja szerint `c4ce2cc0` (2026-08-09) óta érintetlen — a TELJES E13 sáv előtt, alatt és után változatlan forrás. §3c: kimondja, hogy valódi UI-keretidő ezen a boxon nem mérhető, és az eszközös kapu tárgya. Mindhárom kötelező elem megvan (B6). |

## 6. Leletek

| # | Osztály | Állapot |
|---|---|---|
| MINOR-1 | MINOR | **ZÁRVA** (`0db1db91`) |
| NOTE-1 | NOTE | **ZÁRVA** (`0db1db91`) |
| NOTE-2 | NOTE | nyitva hagyva, szándékosan |

### MINOR-1 — elavult doc-comment ellentmondott a kódnak (ZÁRVA)

`test/ui/goldens/e13_r36_variant_matrix_test.dart:174-178` (a `cb774521`
állapotban) a kizárólista fölött ezt írta: *„Empty for now: see §10 handoff for
whether this round's measurement run populated it"* — miközben **négy**
`_ExcludedCell` bejegyzés állt közvetlenül alatta. A repó szabálya, hogy
doc-commentben csak bizonyított állítás szerepel; ez a fájl legfontosabb tényét
mondta rosszul.

**Zárás (`0db1db91`):** a fejléc a MÉRT állapotot írja le (négy bejegyzés,
mind ugyanaz a `live_screen.dart:477` stat-strip defekt, 12 px en / 34 px hu,
2026-08-27). A javításhoz tartozó „őr" maga a P1/P2 próba: a lista tartalma
gépi cellákkal jár, tehát a komment és a kód elcsúszása mostantól látható.

### NOTE-1 — az A2 részleges fedése kimondatlan volt (ZÁRVA)

A `completion-report.md` §4 pontosan sorolta a korlátokat, de az A2 cella
fél-fedettségét nem mondta ki. **Zárás (`0db1db91`):** a §4 új bekezdése
kimondja, mit fed a záró csomag az A2-ből (route, engedély,
állapot-visszaállítás, 200%) és mit NEM (per-képernyő
betöltés/üres/hiba/offline), és hova mutat a maradék.

### NOTE-2 — a két kizárólista szemantikája nem azonos (NYITVA, szándékosan)

A mátrix-fájl **tudatosan** nem px-pontos („a tolerancia emelése tilos, egy
px-pontos újraellenőrzés viszont hamis pozitív lenne, ha a környező elrendezés
független okból elmozdul"), a closure-suite kizárása viszont px-pontos
(`contains('overflowed by 297')`) — a P3 próba szerint 298-ra átírva azonnal
pirosra vált.

**Miért nem kértem javítást:** az eltérés **fail-closed** — elmozdulásnál piros,
sosem hamis zöld —, a szigorúbb alak visszavétele pedig önmagában is
kockázatot hordozna egy záró körben. A leletet a jövő körnek rögzítem, nem
merge-akadálynak.

## 7. Zöld kapu (ADR 0052 / 0086 §2)

| Elem | Állapot |
|---|---|
| Lokális gate (5 teszt-útvonal, 10 lépés) | **10/10 ZÖLD**, saját kezű újrafuttatás izolált klónban, mindkét SHA-n |
| Scope-audit | **OK**, 6 fájl, 0 listán kívüli |
| Full Gate (`full-gate.yml`) a merge SHA-n | lásd §7.1 — a `round-ci-plan.py` terve `full-gate.yml` (`apk_required=false`, tisztán Dart/dokumentum-diff) |
| Router CI (`router-ci.yml`) a merge SHA-n | kötelező (a diff érinti a `docs/rounds/**`-ot, §0.0.B/B9) |

### 7.1 CI-futások

A kör exact-SHA CI-evidenciáját a `0db1db91` head SHA-n futó
`full-gate.yml` + `router-ci.yml` adja; a merge csak mindkettő `success`
állapotában történhet meg. A run-azonosítók és a merge-commit a
`HANDOFF.md`-ben és a PR-ben ([#483](https://github.com/wolfcasaba/strumsight/pull/483)) rögzítettek.

## 8. Végső döntés

**APPROVED** — nyitott BLOCKER/MAJOR/MINOR nincs; az egyetlen MINOR és az
egyetlen javítást kérő NOTE a `0db1db91` javító körrel lezárva, az egyetlen
nyitva hagyott lelet NOTE-2, ami szándékos és nem merge-akadály.

**Amit ez a kör érdemben hozzáadott:** nem egy „minden zöld" pecsét, hanem két
ÚJ, valódi kapu, amelyek a saját futásukon **két addig láthatatlan, valódi
`lib/**` elrendezési hibát mértek ki** (live stat-strip 12/34 px, permission
primer 297 px), és mindkettőt csak-zsugorodó, dátumozott mechanizmusba tették —
úgy, hogy egy csendes javítás és egy csendes regresszió egyaránt teszt-bukásként
jelenik meg. A záró jelentés pedig kimondja, amit a fa valóban mutat: a Ch13
44,8%-ban migrált, a maradék 55,2% dátumozott, felelős-jelölt backlog, a valódi
keretidő pedig továbbra is az eszközös kapu tárgya.
