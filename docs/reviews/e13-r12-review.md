# E13-R12 review — Kártyák, badge-ek, insight és status komponensek

- **Kör:** `E13-R12` (SDD Ch13, Kör 12) · **PR:** [#439](https://github.com/wolfcasaba/strumsight/pull/439)
- **Branch:** `sonnet-impl/e13-r12-cards-badges-and-status` · **Review-HEAD:** `91b0fc72`
- **Implementer:** Claude Sonnet 5 (`sonnet-impl`) · **Reviewer:** Claude Opus 5 (orchesztrátor)
- **Kötelezően bevont:** `security-reviewer` subagent (a brief `risk = "high"`)
- **Dátum:** 2026-08-24
- **Verdikt (1. kör): CHANGES REQUESTED — 4 MAJOR, 2 MINOR, 3 NOTE**

A review READ-ONLY, izolált klónban futott (`/tmp/e13r12-review`, a
munkapéldány klónja `91b0fc72`-n), minden mérés ott készült; a
munkapéldányhoz a review nem nyúlt.

## 0. Ami MÉRVE rendben van

| Mit | Bizonyíték |
|---|---|
| A kör saját kapuja | `tools/round-gate.sh` az izolált klónban **8/8 ZÖLD** (format, analyze, 3 teszt-útvonal, architecture, secrets, l10n) — a jelzésfájl `gate_shape=ok`, és én ezt FÜGGETLENÜL újrafuttattam |
| Scope | `scope_audit=ok`, 16 fájl, mind az `allowed_paths`-on; `docs/adr/**`, `lib/features/**`, `lib/core/theme/**`, `tools/**` érintetlen |
| A7 | `check_architecture.dart` zöld; a 7 új komponens **egyetlen** `lib/features/**` importot sem tartalmaz |
| A8 | 7 új kulcs, mind a **fragmentumban** (`design_system_{en,hu}.arb`), en+hu paritással; nulla hardkódolt user-string a komponensekben; `l10n` gate-lépés zöld |
| §0.0/D3 | a katalógus-mátrix nem adott új `SsCard`-ot / `DecoratedBox`-ot, nincs skeleton-demó — a **fagyott** `component_catalog_test.dart` zöld |
| §0.0/D5 | `SsMetricCard` a `SsTypography.metric*` tokeneket OLVASSA, `SsTypography.metricLabel`-lel; nincs hardkódolt `fontFamily`/`FontFeature` |
| ADR 0278 §5 | a komponensek tiszta `StatelessWidget`-ek; nulla hálózat / I/O / logolás / analytics / perzisztencia (a `security-reviewer` tételes mintakeresése + a `secrets` gate: `3598 file, 0 finding`) |
| Felolvasó-paritás | a provenance külön, felolvasott semantics-csomópont, nem esik `ExcludeSemantics` alá; `SsModelStatusCard` → `["Chord detector…", "Cloud", "Offline", "Low confidence"]` |
| Biztonságos default-irány | nincs olyan default, amely felhő-tartalmat helyinek mutatna (`SsModelStatusCard.provenance` **kötelező**) |

### 0.1 A kötelező valódi-sértés próbák — mind FÜGGETLENÜL reprodukálva

A §6.1 mátrix által nevesített sértéseket az izolált klónban magam
állítottam elő, majd visszaállítottam:

| Próba | Mutáció | Eredmény |
|---|---|---|
| **A3** (kötelező, §6.1) | a kártya-háttér `InkWell`-be csomagolva 2 akció mellett | **PIROS** — „two or more actions: the background is not tappable … [E]" |
| **A6** | az `Expanded` törölve az `SsContentCard` fejléc-sorából | **PIROS mindkét sűrűségben** (compact + expanded) |
| **A2** | a három confidence-fokozat AZONOS feliratot kap (= csak szín különbözteti) | **PIROS** — „every SsStatusBadgeKind renders a unique (icon, text) pair [E]" |
| **A5** | a skeleton metrika-doboza 6 dp-vel alacsonyabb | **PIROS mindkét sűrűségben** |

Négy őr tehát valóban mér. Az **A1 őre viszont VAK** — lásd F3 és F4.

## 1. Leletek

### F1 — MAJOR: a `syncPending` badge a saját háttérszínével íródik, azaz LÁTHATATLAN (1.01:1 a default témában)

**Hely:** `lib/core/design_system/components/feedback/ss_status_badge.dart:43-47`
(`colors.syncPending`), kirendelés `:72-74`.

A `SsColorScheme.syncPending` értéke `palette.track` — **ugyanaz az érték**,
amit a séma `surfaceSunken`-ként, azaz HÁTTÉRKÉNT használ. Előtérbe irányítva
a badge ikonja ÉS felirata is beleolvad a kártyába.

**Saját mérésem** (a pumpolt fából kiolvasott tényleges `Text.style.color` vs.
`SsElevation.raised` háttér, WCAG-arány):

```
PROBE light  status.syncPending: ratio=1.21
PROBE dark   status.syncPending: ratio=1.01      ← a DEFAULT téma
PROBE highContrast status.syncPending: ratio=1.01
```

**Failure scenario:** `SsStatusBadge(kind: SsStatusBadgeKind.syncPending)` —
a felhasználó a „Szinkronizálás függőben" badge helyén **üres helyet lát**,
mindhárom témában, a magas kontrasztúban is. Nem kap jelzést arról, hogy az
adatai még nem szinkronizálódtak. A `component_catalog_screen.dart:431` ma
is így rendeli ki.

**Sértett szabály:** ADR 0278 §2 / brief §5.2 — a badge jelentését ikonnak
vagy szövegnek kell hordoznia; itt egyik sem látszik. A §0.0/D4 betűje
(„a SZÍNT a `syncPending` tokenből veszi") teljesült, de az utasítás egy
háttérnek szánt tokent irányított előtérbe — **ezt a pre-flight nézte el,
nem az implementer**.

### F2 — MAJOR: a provenance-felirat a világos témában 2.18–2.72:1-en van, a projekt saját 4.5:1-es mércéje alatt

**Hely:** `ss_provenance_badge.dart:52-58` és `ss_status_badge.dart:69-75` —
`Text(label, style: …copyWith(color: color))`, ahol a `color` a
státusz-token (`colors.localAi` / `cloudAi` / `confidence*`).

**Saját mérésem** (ugyanaz a próba):

| Téma | badge | arány | ≥ 4.5 |
|---|---|---|---|
| light | `provenance.cloud` („Cloud" / „Felhőben") | **2.18** | ✗ |
| light | `provenance.local` („On-device" / „A készüléken") | **2.72** | ✗ |
| light | `status.confidenceHigh` | 4.34 | ✗ |
| dark | `status.confidenceLow` | 3.48 | ✗ |
| dark / highContrast | provenance local / cloud | 5.97 / 7.45 | ✓ |

Ráadásul a két provenance-szín **egymáshoz** képest `1.25:1` (mindhárom
témában) — a színcsatorna a helyi/felhő megkülönböztetésről gyakorlatilag
nulla információt hordoz, ami önmagában rendben lenne (ezért van ikon+szöveg),
de éppen ezért kell a SZÖVEGNEK olvashatónak lennie.

**A projekt mércéje normatív és GÉPI:** `ContrastCheck.meetsTextContrast`
(`tool/ui_contrast_check.dart`), a küszöb 4.5:1
(`test/core/design_system/themes/contrast_test.dart:14`), és az SDD Ch13
§13 kimondja: „WCAG AA célkontraszt" (939. sor), valamint „**local AI és
cloud AI ne csak színnel különbözzön**" (580. sor).

**Fairness-mérés — a minta ebben a körben született:** végignéztem, hogy
státusz-/brand-színnel festett SZÖVEG előfordul-e a korábbi
design-system-komponensekben:

```
$ grep -rn "color: colors.brand" lib/core/design_system/components/ lib/core/design_system/layouts/ \
    | grep -v "cards/|ai/ss_|ss_status_badge"
(nincs találat)
```

Tehát ez **nem** örökölt minta — a kör hozta be, és a legrosszabb helyre: arra
a feliratra, amelyet az ADR 0278 §1 kifejezetten adatvédelmi ténynek nevez.

**Miért maradt a kapu zöld:** a `contrast_test.dart` egyetlen státusz-/AI-tokent
sem fed (`localAi`, `cloudAi`, `syncPending`, `confidence*` → nulla találat) —
lásd NOTE-1.

### F3 — MAJOR: a provenance-felirat levágódik `textScale ≥ 2.0`-n, és az A1 cella VÉGIG ZÖLD marad

**Hely:** `ss_provenance_badge.dart:49-59`, `ss_status_badge.dart:69-75` —
`Row(mainAxisSize: MainAxisSize.min, [Icon, Text])`, a `Text` nincs
`Flexible`/`Expanded`-ben, nincs `maxLines`/`overflow`. A vágást az `SsSurface`
`Material(clipBehavior: Clip.antiAlias)` végzi.

**Saját mérésem** (`SsInsightCard` + `provenance: local`, magyar felirat,
a repó saját skála-létráján — `SsSemantics.maximumTextScale = 2.0` **pinnelt
projekt-dimenzió**, tehát a 2.0 a TÁMOGATOTT tartomány, nem szélsőség):

```
PROBE w=320 scale=1.0 byType=1 findText=1 visibleFraction=100% overflow=false
PROBE w=320 scale=2.0 byType=1 findText=1 visibleFraction=84%  overflow=true
PROBE w=320 scale=2.5 byType=1 findText=1 visibleFraction=67%  overflow=true
PROBE w=200 scale=1.3 byType=1 findText=1 visibleFraction=74%  overflow=true
PROBE w=200 scale=2.0 byType=1 findText=1 visibleFraction=48%  overflow=true
PROBE w=200 scale=2.5 byType=1 findText=1 visibleFraction=39%  overflow=true
```

**Failure scenario:** a felhasználó a rendszerben a legnagyobb betűméretet
állítja (≈2.0), és egy kétoszlopos hubon 200 dp széles kártyát lát. „A
készüléken" feliratból „A kés…" marad (48%), a maradék információt pedig az
ugyancsak alacsony kontrasztú ikon hordozná (F2). Debug buildben a
sárga-fekete overflow-sáv a feliratra rajzolódik.

**Ez az A1 vakfoltja, pontosan az [L460](../LESSONS.md) osztály:** az
`ss_badges_test.dart:29-30` és `:49-50` cellái `find.byType(SsProvenanceBadge)`
+ `find.text(...)` alapúak — **mind a hat fenti sorban zöldek maradnak**. A
brief §6.1 az A2-re előírta a tulajdonság-szintű mérést; az A1-et
jelenlét-szintűnek hagyta, és pont ott nyílt a rés.

### F4 — MAJOR: az AI-eredetű insight-kártya provenance NÉLKÜL is kirendelhető, és a kör SAJÁT A1 cellája ezt szentesíti

**Hely:** `ss_insight_card.dart:11` (class-doksi: „**An AI-derived
observation** about the player's practice"), `:23` + `:31`
(`SsProvenanceKind? provenance` — opcionális, default `null`), `:70-73`
(`if (provenance != null)`).

**Saját próbám** (eldobható teszt az izolált klónban):

```
PROBE A1: SsInsightCard rendered AI content with 0 provenance badge(s)
00:00 +1: All tests passed!
```

A kártya a teljes AI-tartalmat kirendeli (cím + üzenet), a felhasználó pedig
**semmit nem tud meg arról, hol futott a modell** — miközben a típus saját
doksija AI-eredetűnek nevezi magát. Ez az ADR 0278 §1 / brief §5.1 „NEM
elfogadható gyengítés" pontja: formálisan nem elrejtés, hanem a
kötelezettség teljes áthárítása a hívóra, típus-szintű kényszer nélkül.

**A súlyosbító körülmény:** a kör saját A1 csoportjának harmadik cellája
(`ss_badges_test.dart:54-70`) **kimondottan azt állítja**, hogy provenance
nélkül nincs badge (`findsNothing`) — az őr tehát nem egyszerűen vak, hanem
**bebetonozza** a rést. Ez az [L457](../LESSONS.md) osztálya: a cella a
modellt méri („ha át van adva, megjelenik"), nem az invariánst („AI-tartalom
mindig visel provenance-t").

**Miért javítható most, olcsón:** `grep -rn "SsInsightCard" lib/ | grep -v
"^lib/core/design_system/"` → **nulla fogyasztó**. A `provenance` kötelezővé
tétele ma egy kulcsszó; az első `lib/features/**` fogyasztó után már
migráció lenne. Nem-AI tartalomra ott a `SsContentCard`.

### F5 — MINOR: az `SsCoachActionCard`-on nincs is provenance-slot

**Hely:** `ss_coach_action_card.dart:19-31` — a konstruktorban egyáltalán
nincs `provenance` paraméter, holott a doksi „A coach-suggested next step",
és az ADR 0278 Kontextus-szakasza épp a **coach-réteget** nevezi meg
felhő-hívóként. A katalógus (`component_catalog_screen.dart:394-401`) ma is
kirendel egy coach-javaslatot nulla provenance-jelöléssel.

Vagy kapjon slotot, vagy a §10 handoff nevezze meg, melyik kör kapja — nyitva
hagyni nem szabad.

### F6 — MINOR: az `SsProvenanceKind` zárt kétértékű, `unknown` nélkül

**Hely:** `ss_provenance_badge.dart:13` — `enum SsProvenanceKind { local, cloud }`.

Vegyes pipeline vagy gyorsítótárazott felhő-válasz esetén a hívónak két rossz
opciója van: kihagyja (F4 útja) vagy tippel; ha `local`-t tippel felhő-tartalomra,
az **hamis adatvédelmi állítás**. Kimondom viszont, mert jó: a default irány
biztonságos — nincs olyan default, amely felhő-tartalmat helyinek mutatna.

## 2. NOTE-ok (nem blokkoló)

- **NOTE-1** — a `contrast_test.dart` egyetlen státusz-/AI-tokent sem fed
  (`localAi`, `cloudAi`, `syncPending`, `confidence*` → nulla találat). Ezért
  lehetett az F1/F2 teljesen zöld kapu mellett. A tokenek fájlja tilos zóna
  ebben a körben, de a **cella bővítése** a `ss_badges_test.dart`-ban
  engedélyezett útvonal.
- **NOTE-2** — az A6 cella csak `SsContentCard`-ot mér, csak `textScale = 1.0`-n,
  badge nélkül; a repó máshol az 1 / 1.3 / 2 / 2.5 létrát használja
  (`text_scale_overflow_test.dart:17`).
- **NOTE-3** — a `SsProvenanceBadge` semantics-címkéje csupasz „Cloud" /
  „Felhőben"; egy `offline` badge mellett hálózati állapotnak is érthető, nem
  modell-helynek. A látó és a felolvasót használó felhasználó ugyanazt kapja
  (paritás rendben), de mindkét csatornán egyértelműbb lenne egy
  „Felhő-modell adta" jellegű címke.

## 3. Javító kör — a kötelező zárás

Mind a négy MAJOR a kör SAJÁT, engedélyezett fájljain belül javítható; a tilos
zónához (`ss_colors.dart`, `lib/core/theme/**`, `docs/adr/**`) nem kell nyúlni.

| Lelet | Elvárt zárás | KÖTELEZŐ új őr |
|---|---|---|
| **F1** | a `syncPending` badge ikonja+szövege olvasható tokenből fessen | a kontraszt-cella (lásd F2) fedje le a `syncPending`-et is |
| **F2** | a badge SZÖVEGE (és ikonja) szöveg-tokenből (`textPrimary`/`textSecondary`); a státusz-token maradhat chip-háttérnek vagy akcentusnak | **tulajdonság-cella:** minden `SsStatusBadgeKind` ÉS `SsProvenanceKind` felirata mindhárom témában ≥ 4.5:1 — `ContrastCheck.meetsTextContrast` (`import '../../../../tool/ui_contrast_check.dart';`), a kirendelt fából kiolvasott TÉNYLEGES színnel |
| **F3** | a badge `Text`-je `Flexible` + `maxLines: 1` + `TextOverflow.ellipsis` alá | **geometria-cella:** a felirat festett doboza a kártya dobozán BELÜL van, és nincs overflow-kivétel, az 1 / 1.3 / 2 / 2.5 létrán, 320 és 200 dp szélességen |
| **F4** | `SsInsightCard.provenance` **kötelező** (`required`), az `if (provenance != null)` ág megszűnik | az A1 harmadik cellája („nincs provenance → nincs badge") **törlendő/megfordítandó**: a helyére olyan cella jöjjön, amely azt méri, hogy az AI-kártya MINDIG visel provenance-t |
| **F5** | vagy `provenance`-slot az `SsCoachActionCard`-on, vagy a class-doksi ne állítsa AI-eredetűnek + a §10 nevezze meg a követő kört | — |
| **F6** | döntés + indoklás a §10-ben (marad zárt kétértékű, vagy `unknown`) | — |

**A javító kör után a review-t frissítem, és a zárást SAJÁT méréssel
igazolom** (a javított alakot visszamutálva az új celláknak PIROSRA kell
váltaniuk).

## 4. Review — 2. kör (fix1 után): **APPROVED**

- **Review-HEAD:** `933aa285` (a fix1 négy commitja + az `origin/main`
  beolvasztása, ADR 0087 §0.3)
- **Fix1 commitok:** `d0957944` (F1/F2/F3) · `464fece4` (F4/F5 + `actionLabel`) ·
  `c4198fda` + `51b1d9b5` (§10.1 handoff, őr-elnevezések)
- **Dátum:** 2026-08-24 · **Reviewer:** Claude Opus 5 (orchesztrátor)
- Friss, izolált klón (`/tmp/e13r12-review2`), minden mérés ott készült; a
  munkapéldányhoz a review nem nyúlt.

### 4.1 Freshness — a branch a fix1 UTÁN sem volt naprakész

A fix1 a régi bázison készült, ezért review előtt beolvasztottam az
`origin/main`-t (`2c0f9842`, E09-R23/R24). Konfliktus nélkül ment; az
`git merge-base --is-ancestor origin/main HEAD` **0**. Ez nem formalitás: a
merge hozta be azt az ÚJABB `tools/brief-lint.py`-t (S9, E09-R24 heal),
amellyel a kör briefjét a pre-flight még nem mérhette — lásd 4.3.

### 4.2 A kapu — SAJÁT, független újrafuttatás a merge-elt HEAD-en

`tools/round-gate.sh test/…/ss_cards_test.dart test/…/ss_badges_test.dart`,
exit **0**, **10/10 ZÖLD**: format · analyze · `ss_cards_test.dart` ·
`ss_badges_test.dart` · architecture · secrets · l10n · backend ruff format ·
backend ruff check · backend pytest.

### 4.3 Scope és brief-lint

| Mérés | Eredmény |
|---|---|
| `scope-audit.py --base 2c0f9842` (= `origin/main`) | **OK** — 17 útvonal, 1 generated/ignored (a saját review-fájlom), mind az `allowed_paths`-on |
| `brief-lint.py --level strict` a **merge utáni, újabb** linterrel | **nincs lelet** (az S9 képernyő-leltár-ellenőrzést is beleértve) |
| Tilos zóna | `docs/adr/**`, `lib/features/**`, `lib/core/theme/**`, `tools/**`, `.github/**` — mind érintetlen |

> A `--base 69679bb5` (a merge ELŐTTI elágazási pont) `FAILED`-et ad, de az
> **mérési műtermék**: onnan nézve a már merge-elt E09-R23/R24 munkája is
> „változott útvonalnak" látszik. A kör tényleges hozzájárulását az
> `origin/main` bázis méri.

### 4.4 A leletek zárása — mindegyik SAJÁT valódi-sértés próbával igazolva

A javított alakot visszamutáltam, és megköveteltem, hogy az új őr PIROSRA
váltson. Minden mutáció után `git status` = **0 piszkos fájl**.

| Próba | Mutáció | Eredmény |
|---|---|---|
| **P1 → F1+F2** | a badge felirata/ikonja ismét a saját státusz-tokenjéből fest (`textPrimary` → `syncPending`) | **PIROS**, exit 1 — a kontraszt-csoport **15 cellája** bukik (5 `SsStatusBadgeKind` × 3 téma) |
| **P2 → F3** | a `Flexible` + `maxLines: 1` + `ellipsis` törölve a provenance-badge-ből | **PIROS**, exit 1 — **5 cella** bukik, PONTOSAN azok, amelyeket az 1. kör mért: 320@2.0, 320@2.5, 200@1.3, 200@2.0, 200@2.5 |
| **P3 → F4** | `SsInsightCard` provenance NÉLKÜL megkonstruálva (eldobható teszt, a javított kód ellen) | **PIROS FORDÍTÁSI IDŐBEN** — `Error: Required named parameter 'provenance' must be provided.` |

**A P3 a legerősebb zárás, amit ez a lelet kaphatott:** az F4 sértése futásidőben
nem is *kifejezhető* többé — a típusrendszer fogja meg, nem egy cella, amit egy
későbbi kör átírhatna. A régi, rést betonozó A1-cella („nincs provenance → nincs
badge") eltűnt; a helyén a `SsProvenanceKind.values`-en végigfutó invariáns-cella
áll (`ss_badges_test.dart:80-99`).

| Lelet | Zárás | Ítélet |
|---|---|---|
| **F1** MAJOR | ikon+felirat `colors.textPrimary`-ből; a `syncPending` token szöveget nem fest | **ZÁRVA** (P1) |
| **F2** MAJOR | ugyanaz mindkét badge-en **és** az `SsCoachActionCard.actionLabel`-jén (`colors.brand` → `textPrimary`, a copper 2.72:1 volt) | **ZÁRVA** (P1) |
| **F3** MAJOR | `Flexible` + `maxLines: 1` + `TextOverflow.ellipsis`; a `Wrap` véges szélesség-korlátja a keretrendszer forrásából igazolva | **ZÁRVA** (P2) |
| **F4** MAJOR | `required SsProvenanceKind provenance`, feltétel nélküli kirendelés, nulla fogyasztó volt érintve | **ZÁRVA** (P3) |
| **F5** MINOR | opcionális `provenance`-slot az `SsCoachActionCard`-on, indoklással (nem minden coach-javaslat modell-eredetű), a katalógus demonstrálja | **ZÁRVA** |
| **F6** MINOR | marad zárt kétértékű; indoklás a §10.1-ben (nulla vegyes-pipeline fogyasztó, a biztonságos default-irány áll) | **ZÁRVA — a döntést elfogadom** |

**NOTE-1 zárva:** a kontraszt-fedettség hiánya volt az oka, hogy F1/F2 zöld
kapu mellett átcsúszhatott — az új `fix1/F1+F2` csoport most **21 cellával**
(3 téma × [5 status + 2 provenance]) fedi le pontosan azokat a tokeneket,
amelyeket a `contrast_test.dart` nem lát. NOTE-2 és NOTE-3 nyitva marad,
nem blokkoló.

### 4.5 Amit ebben a körben ÉN mértem újra, és rendben van

- **A2** — a három confidence-fokozat ugyanazt az ikont ÉS (fix1 után) ugyanazt
  a színt kapja; a megkülönböztetést kizárólag a FELIRAT hordozza. Ez a §5.2-nek
  megfelel („ikon **vagy** szöveg"), és színvakság mellett is egyértelmű.
- **A7/A8** — architecture zöld; a 7 komponens nulla `lib/features/**` importot
  tartalmaz; az ARB-kulcsok a fragmentumban, en+hu paritással, `l10n` gate zöld.
- **D4 HELYESBÍTVE** — a pre-flight §0.0/D4 utolsó mondata („a SZÍNT a
  `syncPending` tokenből veszi") MÉRVE hibás volt, és pontosan ez okozta F1-et.
  A briefbe helyesbítő blokk került (a kör saját, még nem merge-elt
  artefaktuma, ADR 0087 §2), hogy egy későbbi kör ne olvassa normatív
  igazságként. Az implementert ezért nem érte marasztalás.

### 4.6 Verdikt

**APPROVED.** Nyitott BLOCKER/MAJOR: **nincs**. A négy MAJOR mindegyike a kör
saját, engedélyezett fájljain belül zárult, tilos zóna érintése nélkül, és
mindegyikhez tartozik olyan gépi őr, amely a hibát PIROSRA fogta volna —
ezt nem bemondásra fogadtam el, hanem visszamutálva magam mértem.
