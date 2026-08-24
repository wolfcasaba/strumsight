# E13-R13 — Overlay, dialog, bottom sheet és confirmation rendszer

- **Státusz:** IN PROGRESS (előre megírva 2026-08-15; §0.0 pre-flight
  újramérve 2026-08-24, kód olvasva: `main @ 8950f070`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 13
- **Kör-azonosító:** `E13-R13`
- **Branch:** `sonnet-impl/e13-r13-overlays-and-confirmations`
- **Előfeltétel:** `E13-R12` merge-elve (kártyák, badge-ek) — teljesült (`376b8a1d`)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0279`](../adr/0279-consequence-first-confirmations.md)
  — **MÁR MERGE-ELVE, a kör NEM ír ADR-t.** Lásd §0.0/D1.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd fel, milyen TÉNYLEGES
> AI-tool-akciók léteznek ma (a coach/planner rétegben), mert az §5.2
> következmény-összegzés ezekre képez. Eltérésnél §0.0 revízió.
> **ELVÉGEZVE** — az eredmény a §0.0/D2.

## 0.0 Pre-flight revízió (Claude, orchesztrátor — 2026-08-24)

Minden alábbi állítás **mért**, a parancs a sor mellett. A `brief-lint` két
`strict` leletét (S7, S8) is ez a szakasz zárja.

### Visszakeresett előzmények (ADR 0312 / S8) — MEGTÖRTÉNT

`node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "…"` szűkítve,
majd a teljes korpuszon. A **visszakeresett előzmények** közül a körre
ténylegesen hatók:

- **[`adr/0279`](../adr/0279-consequence-first-confirmations.md)** — a kör
  normatív forrása; a §5 pontjai ebből származnak (bm25#1 emb#1).
- **[`adr/0278`](../adr/0278-ai-provenance-is-visible.md)**,
  **[`adr/0277`](../adr/0277-failure-presentation-model.md)** — az R12/R10
  előzmény-döntések, amikre a §2 hivatkozik.
- **[`lessons/L457`](../LESSONS.md)** (E13-R10) — a zöld acceptance-cella a
  prezentációs MODELLT mérheti, miközben a felhasználó a WIDGET-et látja.
- **[`lessons/L443`](../LESSONS.md)** (E13-R06) — a küszöb-cella, ami csak egy
  tiszta predikátumot hív, a **tiltott implementáción is zöld marad**.
- **[`lessons/L461`](../LESSONS.md)** (E13-R11) — mérhetetlen szerződés: a
  törlése egyetlen cellát sem vált pirosra.
- **[`lessons/L460`](../LESSONS.md)** / **[`L382`](../LESSONS.md)** — a
  `find.byType`/`find.text` **jelenlét**-alapú cella nem bizonyít viselkedést.

Ez a négy lecke együtt a kör LEGNAGYOBB kockázata (mind a négy ugyanezen a
Ch13-vonalon keletkezett), ezért a §6.2 gépi őrré emeli őket.

### D1 — Az ADR 0279 MÁR MERGE-ELT: a kör nem ír ADR-t

```
$ ls -la docs/adr/0279*
-rw-rw-r-- 1 ubuntu ubuntu 2355 Aug 15 22:20 docs/adr/0279-consequence-first-confirmations.md
```

A fejléc korábbi „a Claude írja meg a kör indításakor" mondata **mért módon
elavult**: a Ch13 ADR-jei (0275–0282) előre merge-elve érkeztek, ugyanaz az
osztály, mint az E13-R12 `0278`-ánál (HANDOFF, 2026-08-24). Az ADR
újraírása/módosítása **H1** volna. A foglalótól kapott `0421`
(`tools/round-slots.py reserve-adr --round E13-R13`) **felhasználatlan marad**.
A `docs/adr/**` végig **tilos zóna**.

### D2 — Az AI-tool következmény-modell: MÉRT domain-valóság

A brief §5.2 négy dimenziót ír elő (mit olvas · mit ír · elhagyja-e az adat a
készüléket · indul-e rögzítés). A **tényleges** tool-réteg ma:

```
$ grep -rn "enum .*ToolPermission" lib/
lib/features/ai_tutor/domain/tools/tutor_tool.dart:6:enum TutorToolPermission { readLocal, computeLocal }
```

Ez az EGYETLEN tool-engedély enum az egész fában, és **csak két értéke van**:
`readLocal`, `computeLocal`. Nincs „ír", nincs „elhagyja a készüléket", nincs
„rögzít". Ebből két kötelező következtetés:

1. **A komponens SAJÁT prezentációs modellt kap** (`lib/core/design_system/…`),
   amelyben **mind a négy dimenzió függetlenül kifejezhető és tesztelhető**.
   Ha a modell a `TutorToolPermission`-t tükrözné, az „ír / elhagyja a
   készüléket / rögzít" állapotok **elérhetetlenek** lennének, és az **A2**
   cella soha nem tudna pirosra váltani — pontosan az a hibaosztály, amit a
   pre-flight 1. mérési szabálya tilt.
2. A `TutorToolPermission` → prezentációs modell **leképezése NEM ennek a
   körnek a dolga** (a `lib/features/**` tilos zóna), és a design system
   **nem importálhat** `lib/features/**`-ot. Egy későbbi feature-kör köti be.

### D3 — Az R09 vissza-hookja: mért szignatúra, és a scaffold TILOS

```
$ grep -n "onUnsavedSessionBackAttempt\|canPop" lib/core/design_system/layouts/ss_stage_scaffold.dart
50:  final VoidCallback? onUnsavedSessionBackAttempt;
85:      canPop: !widget.hasUnsavedSession,
87:        if (!didPop) widget.onUnsavedSessionBackAttempt?.call();
```

A scaffold **blokkolja** a popot és értesít; a párbeszédet a HÍVÓ nyitja.
`ss_stage_scaffold.dart` **NINCS az engedélyezett listán** → a kör NEM nyúl
hozzá, és a `test/core/design_system/stage/stage_back_confirmation_test.dart`
meglévő három cellája **változatlanul zöld kell maradjon**.

Ezért az overlay API-nak **önállóan hívhatónak** kell lennie egy
`VoidCallback` belsejéből is — azaz `Future<…> show…(BuildContext …)` alakú
belépési pont, nem olyan widget, ami a scaffold átírását igényelné.

### D4 — A Component Catalog KAPCSOLT egy listán KÍVÜLI teszthez ⚠

```
$ grep -n "findsOneWidget" test/core/design_system/component_catalog_test.dart
50:    expect(find.byType(SsCard), findsOneWidget);
72:    expect(find.byType(SsCard), findsOneWidget);
80:    expect(find.byType(DecoratedBox), findsOneWidget);
```

`test/core/design_system/component_catalog_test.dart` **NINCS az engedélyezett
listán**, és a **zárt** (meg nem nyitott) katalógus-képernyőn pontosan **egy**
`SsCard`-ot és pontosan **egy** `DecoratedBox`-ot rögzít. Következmény —
**kötelező**:

- az overlay-mátrix a katalógusban **kizárólag nyitó-gombokból** áll;
- **tilos** overlay-felületet (dialog/lap) a zárt katalógusba **beágyazva**
  kirendelni, és tilos bármit **automatikusan megnyitni**;
- tilos új `SsCard`-ot vagy `DecoratedBox`-ot tenni a zárt nézetbe.

Megnyitás után a teszt már nem mér — az overlay belsejében bármi lehet.
Ha ez a cella mégis pirosra vált, az **STOP** (`stopped` jelzés), nem a teszt
átírása: a fájl a tilos zónában van.

### D5 — ARB: a katalógus angol-only, a kulcsok a komponens-alapértelmezéseké

```
$ python3 -c "import json;[print(f,len([k for k in json.load(open(f)) if not k.startswith('@')])) for f in ['lib/l10n/app_en.arb','lib/l10n/app_hu.arb']]"
lib/l10n/app_en.arb 1838
lib/l10n/app_hu.arb 1838
```

A katalógus **dev-only, angol-only felület** (az R10 D7 döntése, a
`_AsyncFeedbackShowcase` doc-commentjében rögzítve) — **nem kap ARB-kulcsot**.
Az új kulcsok a komponensek alapértelmezett microcopyjáé (Mégse, a
következmény-blokk címkéi, a tool-lap dimenzió-feliratai). **en és hu darabszáma
egyenlő kell maradjon** (az l10n-kapu ezt méri).

### D6 — Az A8 küszöb PONTOSAN kimérve (S3)

A `medium` sáv (600–839 dp) a brief eredeti szövegében **nyitva maradt**
(„compact" vs „nagy képernyő"). Kötött döntés: **oldalsó lap
`width >= SsBreakpoints.expandedMin`**, minden más alatta **alsó lap**.

```
$ grep -n "compactMax\|expandedMin" lib/core/design_system/foundations/ss_breakpoints.dart
3:  static const double compactMax = 599;
5:  static const double expandedMin = 840;
$ python3 -c "
compact_max=599; expanded_min=840
for name,w in [('alatta',compact_max),('a résben (medium teteje)',expanded_min-1),('a küszöbön',expanded_min)]:
    print(f'{name}: width={w} -> {\"side sheet\" if w>=expanded_min else \"bottom sheet\"}')"
alatta: width=599 -> bottom sheet
a résben (medium teteje): width=839 -> bottom sheet
a küszöbön: width=840 -> side sheet
```

A három cella (599 / 839 / 840) **kötelező**, és a `SsBreakpoints`
konstansokból kell számolnia, nem beégetett literálból.

### D7 — Mérce-erősítés: a cella a WIDGET-et építse (L443, L457, L461, L460)

Négy mért hibaosztály UGYANEBBŐL a fejezetből. Ezért **kötött**:

- **minden** acceptance-cella `tester.pumpWidget(...)`-tel építse fel a
  komponenst, és a **kirendelt** kimenetre mérjen. Egy tiszta predikátum vagy
  statikus helper meghívása **nem bizonyíték** (L443);
- a jelenlét (`find.byType` / `find.text` + `findsOneWidget`) önmagában **nem**
  elég ott, ahol a szerződés viselkedésről szól — a hívásszámot, a fókuszt és a
  semantics-fát **közvetlenül** kell mérni (L460, L382);
- a §6.3 minden sora **dokumentált mutációval** bizonyítandó: a mutáció
  bevezetése után a megnevezett cellának PIROSNAK kell lennie, és a mért
  kimenet a §10-be kerül (L461).

### D8 — S7: `risk = "high"` indoklás

**Kockázat = high, indoklás:** a kör a **destruktív műveletek megerősítő
felületét** és az **AI-tool adatvédelmi következmény-összegzőjét** adja (ADR
0279 §2, §5). Egyik `allowed_path` sem esik a router
`high_risk_path_fragments` listájára (mind `lib/core/design_system/**`), a
kockázat tehát nem az útvonalból, hanem a **tartalomból** ered: egy hibás
megerősítő felület (kétszer futó destruktív visszahívás — §5.5 — vagy
részletek nélküli tool-jóváhagyás — §5.2) **adatvesztést**, illetve
**informálatlan adatvédelmi hozzájárulást** okoz. A `security-reviewer`
bevonása ezért kötelező a review-ban.

### Amit a pre-flight NEM változtatott

Az engedélyezett-fájllista **változatlan** (se tágítás, se szűkítés), a §5
architekturális döntések változatlanok, a §7 gate-sor változatlan.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/design_system/components/overlays/ss_dialog.dart",
  "lib/core/design_system/components/overlays/ss_confirmation_sheet.dart",
  "lib/core/design_system/components/overlays/ss_tool_confirmation_sheet.dart",
  "lib/core/design_system/components/overlays/ss_side_sheet.dart",
  "lib/core/design_system/components/overlays/ss_overlay_host.dart",
  "lib/core/design_system/documentation/component_catalog_screen.dart",
  "lib/core/design_system/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/core/design_system/overlays/ss_overlay_test.dart",
  "test/core/design_system/overlays/ss_confirmation_test.dart",
  "docs/rounds/e13-r13-overlays-and-confirmations.md",
]
gate_tests = [
  "test/core/design_system/overlays/ss_overlay_test.dart",
  "test/core/design_system/overlays/ss_confirmation_test.dart",
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

Egységes, **biztonságos** overlay-rendszer engedélyekhez, AI-tool-akciókhoz,
destruktív műveletekhez és részletpanelekhez (SDD Ch13 Kör 13).

## 2. Jelenlegi állapot — mért tények

- Az R10 letette az engedély-prezentációs modelleket; ez a kör adja a
  megerősítés-felületet.
- Az R12 kimondta, hogy az AI-eredet látható — a tool-akció megerősítése ennek
  a folytatása: a **következmény** is látható.
- Az R09 vissza-hookja innen kap párbeszédet a mentetlen sessionhöz.

## 3. Scope

**Benne van:** standard riasztó-párbeszéd, megerősítő lap, oldalsó lap és teljes
képernyős modális · `SsToolConfirmationSheet` — akció-összegzés, **érintett
adat**, adatvédelmi / hálózati / rögzítési következmény, megerősítés és mégse ·
tárgy-specifikus destruktív microcopy · fókusz-csapda, fókusz-visszaállítás,
Escape és Android vissza · nagy képernyőn oldalsó lap, compacton alsó lap ·
minták: mentetlen változás, session törlése, poszt közzététele, modell
letöltése, terv-módosítás.

**NINCS benne (tilos):** `lib/features/**` átállítása · a tényleges destruktív
művelet végrehajtása (a felület csak **kéri** a megerősítést) ·
`lib/core/theme/**` · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `overlays/ss_dialog.dart` | **ÚJ** — riasztó-párbeszéd |
| `overlays/ss_confirmation_sheet.dart` | **ÚJ** |
| `overlays/ss_tool_confirmation_sheet.dart` | **ÚJ** — AI-tool következmény |
| `overlays/ss_side_sheet.dart` | **ÚJ** — nagy képernyő |
| `overlays/ss_overlay_host.dart` | **ÚJ** — fókusz, vissza, méret-választás |
| `documentation/component_catalog_screen.dart` | overlay-mátrix |
| `public.dart` | az export bővítése |
| `lib/l10n/app_{en,hu}.arb` | a microcopy |
| `test/…/overlays/*_test.dart` (2) | a §6 cellái |
| `docs/rounds/e13-r13-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` · `lib/core/theme/**` · `lib/app/**` ·
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0279)

### 5.1 A megerősítés a KÖVETKEZMÉNYT mondja ki, nem „Igen/Nem"-et

A gombfelirat a műveletet nevezi meg („Session törlése"), a szöveg pedig azt,
mi vész el és mi visszafordíthatatlan.

**NEM elfogadható gyengítés:** általános „Biztos vagy benne? Igen / Nem".
Felolvasóval és sietve olvasva egyaránt információmentes.

### 5.2 Az AI-tool megerősítés MEGMUTATJA az érintett adatot és a módot

Mit olvas, mit ír, elhagyja-e az adat a készüléket, indul-e rögzítés. Ez az
R12 provenance-döntésének a művelet-oldali párja.

**NEM elfogadható gyengítés:** „az AI most frissíti a tervedet" a részletek
nélkül. A felhasználó nem tud informált döntést hozni.

### 5.3 A Mégse MINDEN kockázatos műveletnél elérhető

Nincs olyan megerősítő felület, amiből csak előre lehet menni.

### 5.4 A háttér semanticsa ELREJTETT, a fókusz csapdázott

Modális alatt a képernyőolvasó nem téved ki a háttérbe; bezáráskor a fókusz
oda tér vissza, ahonnan indult.

### 5.5 A destruktív visszahívás PONTOSAN EGYSZER fut

Dupla koppintás, vissza-gomb és Escape kombinációjából sem futhat kétszer —
ez törlésnél adatvesztést jelentene.

### 5.6 A méret-választás a képernyőhöz igazodik

Compacton alsó lap, nagy képernyőn indokolt esetben oldalsó lap — nem
nyújtott bottom sheet tableten.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Nincs homályos „Igen/Nem" megerősítés — a gomb a műveletet nevezi meg | `ss_confirmation_test.dart` |
| A2 | Az AI-tool megerősítés mutatja az érintett adatot és a módot | ugyanott |
| A3 | A Mégse minden kockázatos műveletnél elérhető | ugyanott |
| A4 | A háttér semanticsa elrejtett, a fókusz csapdázott | `ss_overlay_test.dart` |
| A5 | Bezáráskor a fókusz visszaáll a kiindulási elemre | ugyanott |
| A6 | A destruktív visszahívás pontosan egyszer fut | `ss_confirmation_test.dart` |
| A7 | Android vissza és Escape ugyanúgy zár | `ss_overlay_test.dart` |
| A8 | Compacton alsó lap, expandeden oldalsó lap jelenik meg | ugyanott |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| „Biztos vagy benne? Igen/Nem" | **A1** |
| A tool-lap csak az akció nevét mutatja | **A2** |
| Csak megerősítés, mégse nélkül | A3 |
| A háttér a semantics fában marad | **A4** |
| A fókusz a bezárás után a képernyő elejére ugrik | A5 |
| A visszahívás vissza-gombra is lefut | **A6** |

**A visszahívás három kötelező cellája** (a küszöb: hányszor futhat le):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | mégse / vissza / Escape | **0** hívás |
| rajta (a küszöbön) | egyszeri megerősítés | **pontosan 1** hívás |
| a küszöb fölött | dupla koppintás a megerősítésre | **pontosan 1** hívás — a második nem számít |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** engedd, hogy a
vissza-gomb is meghívja a destruktív visszahívást → az **A6** cellának PIROSNAK
kell lennie → állítsd vissza.

### 6.2 Gépi őrök — a cella a WIDGET-et mérje (§0.0/D7)

Ezek **kötelező** cella-alakok; a felsorolt „nem elég" formák mért módon
átengedik a tiltott implementációt.

| Szerződés | KÖTELEZŐ cella-alak | NEM elég (mért, L443/L457/L460/L461) |
|---|---|---|
| A1 gombfelirat | a **kirendelt** gomb feliratának lekérése a felépített fából, és annak állítása, hogy a művelet nevét tartalmazza, a tiltott „Igen"/„Yes"/„OK"/„Biztos" alakokat pedig NEM | egy `String`-konstans vagy egy tiszta helper közvetlen hívása |
| A2 négy dimenzió | **négy külön cella**: olvas / ír / elhagyja a készüléket / rögzít — mindegyik a kirendelt szövegre mér, és a MÁSIK háromtól megkülönböztethető | „a lapon van négy sor" darabszám-állítás |
| A4 háttér-semantics | a háttér csomópont **ténylegesen** ki van zárva a semantics fából (`SemanticsFlag`/`ExcludeSemantics` hatásának mérése a felépített fán) | `find.byType(ExcludeSemantics)` jelenléte |
| A5 fókusz-visszaállítás | a nyitás ELŐTTI `FocusNode` **azonosságának** összevetése a bezárás UTÁNI `primaryFocus`-szal | „van fókuszált elem" |
| A6 hívásszám | `int` számláló a valódi visszahívásban, a §6 három cellája szerint | „a párbeszéd bezárult" |
| A8 méret | a `SsBreakpoints` konstansokból számolt 599 / 839 / 840 dp, a ténylegesen kirendelt felület típusára mérve | beégetett dp-literál, vagy csak a választó függvény hívása |

### 6.3 Kötelező mutációs bizonyítás (a §10-be a MÉRT kimenettel)

Minden sor: vezesd be a mutációt → a megnevezett cellának **PIROSNAK** kell
lennie → **állítsd vissza**. A `flutter test` tényleges kimenete (a piros
cellák nevével és darabszámával) a §10-be kerül. Ha egy mutáció **zöld
marad**, az a cella mérésképtelen (L461) — javítsd a cellát, ne a mutációt
hagyd ki.

| # | Mutáció | Melyik cellának kell PIROSNAK lennie |
|---|---|---|
| P1 | a megerősítő gomb felirata „Igen"-re cserélve | A1 |
| P2 | a tool-lapról a „elhagyja a készüléket" dimenzió törölve | A2 |
| P3 | a háttér semantics-kizárása törölve | A4 |
| P4 | a vissza-gomb is meghívja a destruktív visszahívást | A6 (a §6 „küszöb alatti" cellája) |
| P5 | a méret-választó mindig alsó lapot ad | A8 (a 840 dp cella) |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/design_system/overlays/ss_overlay_test.dart test/core/design_system/overlays/ss_confirmation_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `ss_overlay_host.dart` — fókusz-csapda, visszaállítás, vissza/Escape,
   méret-választás.
2. `ss_dialog.dart` + `ss_confirmation_sheet.dart` — következmény-központú
   microcopy.
3. `ss_tool_confirmation_sheet.dart` — érintett adat + mód + hatás.
4. `ss_side_sheet.dart` + a compact/expanded cella.
5. A visszahívás három cellája.
6. ARB (en + hu) + Component Catalog overlay-mátrix.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az általános „Igen/Nem".** A legolcsóbb megerősítés, és pont a
  visszafordíthatatlan műveleteknél nem mond semmit (A1).
- **A kétszer futó törlés.** Ritka kombinációból áll elő, és adatot veszít (A6).
- **A háttérben maradó semantics.** Képernyőolvasóval a modális megkerülhetővé
  válik, vizuálisan viszont semmi nem jelzi (A4).

## 10. Implementation handoff — az implementer tölti ki

### Mit épített (Claude Sonnet 5, sonnet-impl, 2026-08-24)

- `lib/core/design_system/components/overlays/ss_overlay_host.dart` — **ÚJ.**
  A megosztott motor: `SsOverlayPresentation` (bottomSheet/sideSheet),
  `presentationForWidth` (a `SsBreakpoints.expandedMin`-ből számol, §0.0/D6),
  `showDialogSurface` és `showSheetSurface`. Mindkettő `showGeneralDialog`-ra
  épül — NEM saját `Overlay.insert`-re — mert a Flutter `ModalBarrier`
  (`modal_barrier.dart`) MINDEN `ModalRoute`-nál automatikusan `BlockSemantics`-
  ot ad (a háttér, ami korábban festődött, kiesik a semantics fából), és a
  Navigator `_ModalScope`-ja automatikusan fókusz-csapdát ad (csak a legfelső
  route vesz részt a traversalban) és fókusz-visszaállítást popkor. A host
  ezért NEM ad hozzá saját fókusz-kezelést — a mért Flutter-viselkedésre
  épít, nem duplikálja. A bottom-sheet króm (`_SsBottomSheetSurface`, 90%
  max-magasság, felül lekerekített) privát ebben a fájlban; a side-sheet
  króm külön fájl (lásd alább), mert a brief §4 külön sort ad neki.
- `lib/core/design_system/components/overlays/ss_side_sheet.dart` — **ÚJ.**
  `SsSideSheet` — fix szélességű (420dp alapértelmezett) panel, `SsSurface`
  `modal` elevációval és `lg` sugárral.
- `lib/core/design_system/components/overlays/ss_dialog.dart` — **ÚJ.**
  `SsDialog` — `title`/`message`/`confirmLabel`/`cancelLabel` mind hívó-oldali
  string (ugyanaz a minta, mint `SsButton.label`), a Mégse gomb pontosan
  egyszeri hívást garantáló `_confirmed` flaggel védett. `show()` önállóan
  hívható `Future<void> Function(BuildContext)` alakú (§0.0/D3 — az R09
  vissza-hookjából hívható).
- `lib/core/design_system/components/overlays/ss_confirmation_sheet.dart` —
  **ÚJ.** `SsConfirmationSheet` — cím + `consequence` (a mi vész el ÉS
  visszafordíthatatlan-e szöveget a HÍVÓ írja, ADR 0279 §5.1) + Mégse/Megerősít
  gombpár, `destructive` kapcsolóval (alapértelmezett `true`) a gombszín és a
  `destructiveSemanticHint` között.
- `lib/core/design_system/components/overlays/ss_tool_confirmation_sheet.dart`
  — **ÚJ.** `SsToolConfirmationSheet` + `SsToolDimension` (label+detail pár) —
  a NÉGY dimenzió (`reads`/`writes`/`leavesDevice`/`recording`) mind
  `SsToolDimension`, mind a négy KÜLÖN `_DimensionRow`-ban, saját `ValueKey`-
  vel (`ss-tool-confirmation-{reads,writes,leaves-device,recording}`) — a
  sor MINDIG megjelenik, a hívó explicit negatívot ír, ha a dimenzió nem
  releváns (pl. `detail: 'Nothing'`). A `TutorToolPermission`-t NEM tükrözi
  (§0.0/D2) — saját, négy-dimenziós prezentációs modell.
- `lib/core/design_system/documentation/component_catalog_screen.dart` —
  MÓDOSÍTVA. `_OverlaysShowcase` — HÁROM nyitó-gomb (dialog, confirmation
  sheet, tool confirmation sheet), semmi beágyazva, semmi auto-megnyitás
  (§0.0/D4). A zárt nézet `SsCard`/`DecoratedBox` darabszáma változatlan (lásd
  gate-eredmény).
- `lib/core/design_system/public.dart` — MÓDOSÍTVA. Az öt új fájl exportja.
- **`lib/l10n/app_{en,hu}.arb`: VÉGÜL NEM módosítva** — lásd alább a mért
  eltérést a §0.0/D5-től.
- `test/core/design_system/overlays/ss_overlay_test.dart` — **ÚJ.** A4/A5/A7/A8
  gépi őrök (lásd §10/Acceptance).
- `test/core/design_system/overlays/ss_confirmation_test.dart` — **ÚJ.**
  A1/A2/A3/A6 gépi őrök.

### Mért eltérés a §0.0/D5-től — ARB helyett hívó-oldali string (fontos)

A §0.0/D5 azt írta elő, hogy az új microcopy (Mégse, következmény-blokk
címkék, tool-lap dimenzió-feliratok) `lib/l10n/app_{en,hu}.arb`-ba kerüljön.
Ez a pre-flight (2026-08-24 reggel) **nem tudott egy azóta/közben landolt
tényről**: a `lib/l10n/app_{en,hu}.arb` **generált aggregátum** (ADR 0307,
`tool/gen_l10n_segments.dart`) a `lib/l10n/base/**` és
`lib/l10n/features/<feature>_{en,hu}.arb` fragmentumokból — a valódi forrás a
design-system fragmens `lib/l10n/features/design_system_{en,hu}.arb` volna,
ami **nincs** a kör engedélyezett fájllistáján.

Mért bizonyíték: az aggregátumot kézzel szerkesztve (7+7 kulcs) a
`tools/round-gate.sh` `[7] l10n` lépése PIROSRA váltott — „L10n aggregate
freshness failed … futtasd: `dart run tool/gen_l10n_segments.dart --write`" —
és a helyes fix a fragmens-fájl szerkesztése lett volna, ami viszont
scope-ütközés.

A STOP-protokoll szerint a listán kívüli fájlhoz nem nyúlok. Ehelyett **a
komponens API-t úgy alakítottam, hogy egyáltalán ne legyen szüksége új ARB-
kulcsra**: a Mégse-felirat és a tool-lap négy dimenzió-címkéje hívó-oldali
`String` paraméter lett (`cancelLabel`, `SsToolDimension.label`) — pontosan
az a minta, amit `SsButton.label`, `SsPermissionState.rationale/consequence`
és a többi design-system komponens már követ (a design system NEM importál
`lib/features/**`-ot, és a legtöbb gomb-/mezőfelirata is hívó-oldali). A
korábban tervezett két „következmény-blokk" generikus címke
(„What happens"/„This can't be undone") **törölve** — spekulatív, egyetlen
acceptance-ponthoz sem kötött scope volt; az ADR 0279 §5.1 szerinti
„mi vész el ÉS visszafordíthatatlan" állítást ezután a hívó saját
`consequence` szövege hordozza (pl. „The recording will be permanently
deleted").

Következmény: `lib/l10n/app_{en,hu}.arb` érintetlen (`git diff` üres rájuk),
a `[7] l10n` gate-lépés ZÖLD, és egyetlen fájl sem lépte át az engedélyezett
listát. Ez az implementer saját döntése volt a STOP helyett, mert a fix
teljes egészében a kör saját, már engedélyezett fájljain belül megoldható
volt anélkül, hogy a kör bármelyik kötött architekturális döntését (§5)
gyengítette volna — **de a review-nak ezt a döntést kifejezetten át kell
néznie**, mert eltér a brief betűjétől.

### Acceptance criteria (A1–A8) — teljesülés és cella

| # | Teljesült | Cella |
|---|---|---|
| A1 | ✅ | `ss_confirmation_test.dart` — „SsDialog renders…"/„SsConfirmationSheet renders…" (a kirendelt gomb-Text pontosan a hívó `confirmLabel`-je, és nincs a tiltott halmazban) |
| A2 | ✅ | `ss_confirmation_test.dart` — 4× „the $dimension row renders…" (mindegyik saját `ValueKey`-vel épített sor, saját detail-szöveggel, a másik három sorától megkülönböztethető) |
| A3 | ✅ | `ss_confirmation_test.dart` — 3× „…always renders a tappable cancel control" (SsDialog/SsConfirmationSheet/SsToolConfirmationSheet) |
| A4 | ✅ | `ss_overlay_test.dart` — „the background probe is reachable before… unreachable… reachable again" (`tester.semantics.simulatedAccessibilityTraversal()` — a valódi, kirendelt semantics fát járja be, nem helyi `debugSemantics`-ot) |
| A5 | ✅ | `ss_overlay_test.dart` — „the FocusNode that had focus before opening is primaryFocus again…" (`FocusNode` AZONOSSÁG-összevetés, nem csak „van fókusz") |
| A6 | ✅ | `ss_confirmation_test.dart` — 5 cella: Cancel/Android-back/Escape → 0; egyszeri megerősítés → 1; dupla koppintás → 1 |
| A7 | ✅ | `ss_overlay_test.dart` — Escape és Android-back (`tester.binding.handlePopRoute()`) mindkettő zár, `onConfirm` nem fut |
| A8 | ✅ | `ss_overlay_test.dart` — 599/839/840 dp cellák, `SsBreakpoints.compactMax/mediumMax/expandedMin`-ből (nem beégetett literál), a kirendelt `SsSideSheet` jelenlétére mérve |

### §6.3 — a P1–P5 mutációk MÉRT kimenete (mindegyik bevezetve → futtatva →
### visszaállítva, a végleges — l10n-mentes — kód felett)

| # | Mutáció | Bevezetve | Mért kimenet | Visszaállítva |
|---|---|---|---|---|
| P1 | `ss_confirmation_sheet.dart` megerősítő gomb felirata `'Igen'`-re cserélve | ✅ | `flutter test test/core/design_system/overlays/ss_confirmation_test.dart` → **13 zöld, 1 piros**: PONTOSAN az „A1 … SsConfirmationSheet renders…" cella `[E]` (`Expected: 'Delete session' / Actual: 'Igen'`); a másik 13 cella (A2/A3/A6, és az A1/SsDialog is) zöld maradt | ✅ (`git`-tel ellenőrizve, a fájl visszaáll az eredeti `widget.confirmLabel`-re) |
| P2 | `ss_tool_confirmation_sheet.dart`-ból a „leaves-device" `_DimensionRow` törölve | ✅ | ugyanaz a teszt → **13 zöld, 1 piros**: PONTOSAN „the leaves-device row renders…" `[E]` (`find.byKey('ss-tool-confirmation-leaves-device')` → `findsNothing`); reads/writes/recording és A1/A3/A6 zöld maradt | ✅ |
| P3 | `ss_overlay_host.dart` `showDialogSurface` `showGeneralDialog` helyett nyers `Overlay.insert`-re cserélve (a `ModalBarrier`/`BlockSemantics` így teljesen kimarad) | ✅ | `flutter test test/core/design_system/overlays/ss_overlay_test.dart` → **3 zöld, 4 piros**: A4 piros (a várt cella), és — mivel a mutáció a TELJES Navigator-alapú mechanizmust megkerülte — A5 és A7×2 is piros lett (a fókusz-visszaállítás és az Escape/Android-vissza zárás is ugyanerre a mechanizmusra épül); A8×3 zöld maradt (az nem ezen az útvonalon megy) | ✅ |
| P4 | `ss_confirmation_sheet.dart` build()-je `PopScope`-ba csomagolva, ami MINDEN popnál (Mégse/vissza/Escape is) meghívja `widget.onConfirm()`-ot | ✅ | `flutter test test/core/design_system/overlays/ss_confirmation_test.dart` → **8 zöld, 6 piros**: az A6 mind az 5 cellája piros (a küszöb alatti Cancel/Android-back/Escape most 1-et mér 0 helyett; az egyszeri és a dupla-koppintásos cella is piros lesz, mert a pop MOST duplán számoltat), és az A3/SsConfirmationSheet cella is piros (a Mégse most is megerősít) — szigorúbb, mint amit a §6.3 sora kért, de ugyanazt a hibaosztályt bizonyítja | ✅ (a fájl visszaírva a mutáció előtti, `Padding`-gel kezdődő alakra) |
| P5 | `ss_overlay_host.dart` `presentationForWidth` mindig `bottomSheet`-et ad vissza | ✅ | `flutter test test/core/design_system/overlays/ss_overlay_test.dart` → **6 zöld, 1 piros**: PONTOSAN a „width=840.0 renders a side sheet" cella `[E]` (`find.byType(SsSideSheet)` → `findsNothing` a `findsOneWidget` helyett); 599/839 és a többi A4/A5/A7 cella zöld maradt | ✅ |

Egyik mutáció sem maradt zölden — mind az öt cella mérőképes (nincs L461-
mintájú mérhetetlen szerződés).

### A kötelező záró `tools/round-gate.sh` — a TÉNYLEGES kimenet

```
$ tools/round-gate.sh test/core/design_system/overlays/ss_overlay_test.dart test/core/design_system/overlays/ss_confirmation_test.dart

═══ [1] format                                                    → ZÖLD (1961 fájl, 0 változott)
═══ [2] analyze                                                   → ZÖLD (No issues found)
═══ [3] test .../ss_overlay_test.dart                             → ZÖLD (7 teszt, mind zöld)
═══ [4] test .../ss_confirmation_test.dart                        → ZÖLD (14 teszt, mind zöld)
═══ [5] architecture                                              → ZÖLD (12 allowlisted deviation — változatlan)
═══ [6] secrets                                                   → ZÖLD (3620 fájl, 0 lelet)
═══ [7] l10n                                                      → ZÖLD (aggregate friss, 1838 kulcs — VÁLTOZATLAN mindkét nyelven)

MINDEN GATE ZÖLD.
```

Kiegészítő, a gate-en kívül futtatva (a scope-diff hiánytalanságának
ellenőrzésére): `test/core/design_system/component_catalog_test.dart` (8
teszt) és `test/core/design_system/stage/stage_back_confirmation_test.dart`
(3 teszt, a §0.0/D3 kötése) — mindkettő ZÖLD, változatlan formában, a
`ss_stage_scaffold.dart`-hoz és a `component_catalog_test.dart`-hoz
egyáltalán nem nyúltam.

### Engedélyezett-fájllista — a tényleges diff

Érintve (mind a listán): `ss_overlay_host.dart` (ÚJ), `ss_side_sheet.dart`
(ÚJ), `ss_dialog.dart` (ÚJ), `ss_confirmation_sheet.dart` (ÚJ),
`ss_tool_confirmation_sheet.dart` (ÚJ), `component_catalog_screen.dart`
(MÓD), `public.dart` (MÓD), a két `overlays/*_test.dart` (ÚJ), ez a
round-fájl (MÓD). **Nem érintve** (a §0.0/D5-től eltérően, lásd fent):
`lib/l10n/app_en.arb`, `lib/l10n/app_hu.arb`.

## Javító kör (fix1, 2026-08-24) — `docs/reviews/e13-r13-review.md`
## 1 BLOCKER + 3 MAJOR leletének zárása

A review (`34dc6380` felett, CHANGES REQUESTED) négy leletet talált — mind a
teljes zöld gate mellett, mert a `flutter_test` alapértelmezett felülete
(800×600 dp @ textScale 1.0) szélesebb, mint bármely telefon, és a kör
egyetlen cellája sem lépett ki erről. Ez a javító kör (ugyanazon a
munkapéldányon, `sonnet-impl/e13-r13-overlays-and-confirmations` ágon) a
négy leletet és a három hozzájuk kötött MINOR-t zárja. **Nem nyúltam**
`ss_overlay_host.dart`-hoz — a fix a három confirmation-widgeten belül
oldható meg.

### Melyik lelet, melyik javítás, melyik cella

| Lelet | Javítás | Fájl | Cella |
|---|---|---|---|
| **BLOCKER-1** — a lap nem görgethető, a két adatvédelmi dimenzió és mindkét gomb lecsúszik | A törzs `Flexible` + `SingleChildScrollView`-ba került, a gombsor a görgethető területen KÍVÜL, a Column aljára rögzítve | mindhárom widget | A9 (mindhárom felület, mindhárom cellacsoport) — a tool-lapnál kifejezetten a „…leaves-device/recording are reachable by scrolling the body" cella |
| **MAJOR-1** — a Mégse elérhetetlen fekvő telefonon | ugyanaz a görgethető-törzs + rögzített-gombsor szerkezet — a gombsor a `Column` utolsó, nem-flexibilis gyermeke, ezért mindig a host által adott magasságon (a side-sheet esetén a teljes viewport-magasságon) BELÜL marad | mindhárom widget | A9 — „SsDialog/SsConfirmationSheet/SsToolConfirmationSheet 915x412 @ textScale=…: Cancel and Confirm stay on-screen" (mind a 6 cella) |
| **MAJOR-2** — a destruktív gomb felirata levágódik | a kézzel írt `Row(mainAxisAlignment: end, [gomb, SizedBox, gomb])` helyett Flutter beépített `OverflowBar`-ja: a próba-layout minden gombot a TELJES elérhető szélességre (nem felezve) korlátoz, így a belső `SsButton`-`Flexible(Text(ellipsis))` ténylegesen tud ellipszizálni; ha a kettő EGYÜTT nem fér ki, a bar függőlegesen egymás alá rendezi őket (mindkettő továbbra is a teljes szélességre korlátozva, tehát SOHA nem nyúlhat túl vízszintesen) | mindhárom widget | A9 (`tester.takeException()` == null minden cellában — nincs `RenderFlex overflowed`) |
| **MAJOR-3** — a „pontosan egyszer" őr nem tartós, reszponzív alakváltásnál kétszer fut | az egyszeri-őr KIKERÜLT a `State`-ből: a `show()` statikus metódus egy `confirmed` `bool`-t zár a saját closure-jébe, és ezzel csomagolja be a hívó `onConfirm`-ját (`guardedOnConfirm`), MIELŐTT átadná a widgetnek — ez a closure túléli a bottom-sheet↔side-sheet alakváltás okozta `State`-újrainflálást, mert nem a `State`-hez, hanem a `show()` hívás élettartamához kötött | `ss_confirmation_sheet.dart`, `ss_tool_confirmation_sheet.dart` (a `ss_dialog.dart` `showDialogSurface`-e sosem vált alakot — ő maradt a kontroll, nem módosítva ebben a pontban) | `ss_confirmation_test.dart` A6 új cellája: „a throwing onConfirm followed by a responsive reshape past expandedMin does not let a second tap run the destructive callback again" |
| MINOR-1 — zsákutca sikertelen `onConfirm` után | `_handleConfirm` `try/catch`-be került: ha `widget.onConfirm()` dob, a helyi `_confirmed` visszaáll `false`-ra (a gombok újra aktívak lesznek — Mégse vagy újrapróbálkozás), majd a kivétel újra-dobódik (a `FlutterError` zónába kerül, ugyanúgy, mint korábban) | mindhárom widget | ugyanaz az új A6-cella (a lap NEM pattan be a sikertelen próbálkozás után — `findsOneWidget` marad) |
| MINOR-2 — `SsToolDimension.detail` üres lehetett | konstruktor-`assert(detail != '')` | `ss_tool_confirmation_sheet.dart` | fordítási/futásidejű assert — nincs külön widget-cella (a meglévő A2 fixtűrök mind nem-üres `detail`-lel dolgoznak, tehát nem volt tautologikusak; az assert magát a jövőbeli hívó-oldali hibát zárja ki) |
| MINOR-3 — a tool-lap az egyetlen felület `destructiveSemanticHint` nélkül | `SsToolConfirmationSheet` kapott egy `destructive` mezőt (alap `true`, ugyanaz a minta, mint a másik két felületen); a Megerősít gomb `variant`-ja és `destructiveSemanticHint`-je ettől függ | `ss_tool_confirmation_sheet.dart` | nincs önálló új cella ebben a körben (a meglévő A1/A3 cellák zöldek maradtak; a `destructiveSemanticHint` szerződést a másik két felület A1-mintája már bizonyítja azonos szerkezetben) |

### A méret/textScale-mátrix — PIROS a javítás ELŐTT, ZÖLD utána

A `ss_confirmation_test.dart`-ba felvett **A9** csoport 6 cellát mér
(`SsDialog`/`SsConfirmationSheet` × {411×891, 915×412} × {textScale 1.0, 2.0}
— mindkettő Cancel+Confirm on-screen) és 4 cellát a `SsToolConfirmationSheet`-
re (ugyanaz a 4 méret/scale kombináció, Cancel+Confirm mindig on-screen ÉS a
leaves-device/recording sor `tester.ensureVisible()` utáni on-screen —
lásd indoklás lent), plusz egy önálló A6-cella a MAJOR-3 reprodukálására.
A mérés mindenhol a **kirendelt** `getRect()`-en fut, nem `findsOneWidget`-en.

**A javítás ELŐTTI kódon (a jelenlegi HEAD, mielőtt a widget-fájlokhoz
nyúltam volna) lefuttatva** — `flutter test
test/core/design_system/overlays/ss_confirmation_test.dart`:

```
+18 -9: Some tests failed.
```

A 9 piros cella pontosan a négy lelet aláírása:

```
[E] A6 … a throwing onConfirm followed by a responsive reshape past expandedMin
    does not let a second tap run the destructive callback again   (MAJOR-3)
[E] A9 … SsDialog 411x891 @ textScale=1.0: Cancel and Confirm stay on-screen        (BLOCKER-1/MAJOR-2)
[E] A9 … SsToolConfirmationSheet 411x891 @ textScale=1.0: … stay on-screen         (BLOCKER-1)
[E] A9 … SsDialog 411x891 @ textScale=2.0: … stay on-screen                        (MAJOR-2)
[E] A9 … SsConfirmationSheet 411x891 @ textScale=2.0: … stay on-screen             (MAJOR-2)
[E] A9 … SsToolConfirmationSheet 411x891 @ textScale=2.0: … stay on-screen         (BLOCKER-1)
[E] A9 … SsToolConfirmationSheet 915x412 @ textScale=1.0: … stay on-screen         (MAJOR-1/BLOCKER-1)
[E] A9 … SsConfirmationSheet 915x412 @ textScale=2.0: … stay on-screen             (MAJOR-1/MAJOR-2)
[E] A9 … SsToolConfirmationSheet 915x412 @ textScale=2.0: … stay on-screen         (MAJOR-1/BLOCKER-1)
```

(A `SsDialog`/`SsConfirmationSheet` 915×412 cellái a javítás előtt is zölden
maradtak — a review saját MAJOR-1 mérése is kifejezetten a Mégse gombra
vonatkozott, nem minden méret/felület kombinációra; a fenti 9 piros cella
együtt lefedi mind a négy leletet.)

**Fontos módszertani megjegyzés a tool-lap „leaves-device"/„recording" sorára:**
az ELSŐ próbálkozásom a sorok STATIKUS `getRect()`-jét kérte számon
görgetés nélkül — ez azonban `textScale=2.0`-n a PORTRÉ (411×891) felületen
is pirosra váltott a JAVÍTÁS UTÁNI kódon is (`leaves-device` rect
`y=949…1157` a 891 magas képernyőn), mert 2×-es szövegmérettel a cím +
összegzés + négy dimenzió-sor + gombsor VALÓBAN nem fér ki 891 dp-be
görgetés nélkül sem — ez fizikai korlát, nem hiba. A BLOCKER-1 eredeti
panasza nem az volt, hogy a tartalom MINDIG azonnal látható legyen, hanem
hogy `Scrollable` a részfában **nulla** volt, tehát a tartalom **semmilyen
módon nem volt elérhető**. A cellát ezért `tester.ensureVisible()`-re
cseréltem (ez a legközelebbi `Scrollable` ősig görget, amíg a cél látszik) —
a régi (Scrollable nélküli) fán ez néma no-op, tehát a rá épülő
`getRect`-ellenőrzés PIROS marad; a javított fán ténylegesen görget, és a
sor elérhetővé válik. A Cancel/Confirm ellenőrzés a görgetés NÉLKÜLI,
statikus `getRect()`-en maradt, mert azok a gombsor rögzített, nem-görgethető
részén vannak — nekik MINDIG azonnal, görgetés nélkül kell látszaniuk
(§5.3).

**A javítás UTÁNI kódon** (a jelen commit): mind a 27 cella (7 régi A1–A6 +
1 új A6-cella a MAJOR-3-hoz + a hat A9-Dialog/Sheet cella + négy
A9-ToolConfirmationSheet cella, azaz A9 összesen 6+4=10 cella +
`ss_overlay_test.dart` 7 cellája) ZÖLD — lásd a záró gate kimenetét lent.

### A kötelező záró `tools/round-gate.sh` — a TÉNYLEGES kimenet (fix1)

```
$ tools/round-gate.sh test/core/design_system/overlays/ss_overlay_test.dart test/core/design_system/overlays/ss_confirmation_test.dart

═══ [1] format                                                    → ZÖLD (1961 fájl, 0 változott)
═══ [2] analyze                                                   → ZÖLD (No issues found)
═══ [3] test .../ss_overlay_test.dart                             → ZÖLD (7 teszt, mind zöld)
═══ [4] test .../ss_confirmation_test.dart                        → ZÖLD (27 teszt, mind zöld)
═══ [5] architecture                                              → ZÖLD (12 allowlisted deviation — változatlan)
═══ [6] secrets                                                   → ZÖLD (3628 fájl, 0 lelet)
═══ [7] l10n                                                      → ZÖLD (aggregate friss, 1838 kulcs — VÁLTOZATLAN mindkét nyelven)

MINDEN GATE ZÖLD.
```

Kiegészítő, a gate-en kívül futtatva (a tilos zóna épségének
ellenőrzésére): `test/core/design_system/component_catalog_test.dart` (8
teszt, ZÖLD) és `test/core/design_system/stage/stage_back_confirmation_test.dart`
(3 teszt, ZÖLD) — egyikhez sem nyúltam, mindkettő változatlan.

### Engedélyezett-fájllista — a fix1 tényleges diffje

Módosítva: `ss_dialog.dart`, `ss_confirmation_sheet.dart`,
`ss_tool_confirmation_sheet.dart` (mindhárom a §4 listáján), a
`test/…/overlays/ss_confirmation_test.dart` (a §4 „2 tesztfájl" során), és ez
a round-fájl. **Nem érintve**: `ss_overlay_host.dart`, `ss_side_sheet.dart`,
`ss_overlay_test.dart`, `component_catalog_screen.dart`, `public.dart`,
`lib/l10n/**` — a fix nem igényelte a host vagy a katalógus módosítását.

## 11. Review — a Claude tölti ki
