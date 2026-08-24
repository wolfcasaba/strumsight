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

## 11. Review — a Claude tölti ki
