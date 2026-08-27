# E13-R31 — Progress Dashboard és Skill Detail UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 0f7afd9a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 31
- **Kör-azonosító:** `E13-R31`
- **Branch:** `<motor>/e13-r31-progress-and-skills`
- **Előfeltétel:** `E13-R30` merge-elve (vision UI)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0289`](../adr/0289-mastery-is-evidence-not-xp.md)
  — **MÁR MERGE-ELVE** (`5b32bd8e`, 2026-08-15): a kör ADR-t **nem ír**, a
  `docs/adr/` TILOS zóna, a módosítása **H1** (§0.0.B/B2).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES haladás- és
> mérőszám-modelleket, kiemelten a **verziózást** — a §5.5 migrációs cella a
> mért verzió-mezőre épül. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/progress_v2/",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/progress_v2/dashboard_states_test.dart",
  "test/features/progress_v2/mastery_evidence_test.dart",
  "test/features/progress_v2/metric_migration_test.dart",
  "test/features/progress_v2/chart_semantics_test.dart",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e13-r31-progress-and-skills.md",
]
gate_tests = [
  "test/features/progress_v2/dashboard_states_test.dart",
  "test/features/progress_v2/mastery_evidence_test.dart",
  "test/features/progress_v2/metric_migration_test.dart",
  "test/features/progress_v2/chart_semantics_test.dart",
  "test/ui/goldens/e13_r31_screens_golden_test.dart",
  "test/ui/ui_inventory_test.dart",
  "test/core/architecture_dependency_test.dart",
  "test/tooling/dio_factory_guard_test.dart",
  "test/tooling/preferences_plugin_import_guard_test.dart",
  "test/tooling/route_literal_guard_test.dart",
]
native_gate = false
```

## 0.0 BRIEF-REVÍZIÓ — 2026-08-25, batch pre-flight (E13-R17…R35)

A brief 2026-08-15-én készült; ez a pre-flight `main @ 41fbd40` ellen mért.
**Visszakeresett előzmény:** [L478](../LESSONS.md) (a pre-flight csak szűkíthet;
a tágítás H3), [ADR 0307 §4](../adr/0307-parallel-round-execution.md) (a
`lib/l10n/app_*.arb` GENERÁLT aggregátum, a forrás a `base/` és a
`features/` szegmens), [L481](../LESSONS.md) (a lánc remote konténerből nem
indítható). A hibaosztályt a **teljes Ch13 sávon** mérte ki egy batch-vizsgálat:
az R17–R35 MIND a generált aggregátumot sorolta fel forrásként (`agg=2, frag=0`).

**Kockázat = high, indoklás:** a fejlődési felület a felhasználó teljes tanulási történetét (személyes adat) aggregálja.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fájából `lib/features/progress_v2/` **még nem létezik** — a képernyőket ez a kör hozza létre, tehát MINDEN szövege új.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `progress_v2` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek

Az aggregátum a listán MARAD, de **kizárólag generált kimenetként**
(`dart run tool/gen_l10n_segments.dart --write`); a merge-elt precedens
egységesen a forrást ÉS a regenerált aggregátumot is commitolja (E09-R26
`df0ad3dd`, E13-R12 `376b8a1d`, E13-R10 `b11ab2ed`). **Új fragmentum NEM
készül**, ezért a `test/l10n/arb_parity_test.dart` beégetett szegmens-listáját
sem kell bővíteni — a felvett források mind szerepelnek benne.

### R2 — a kör SAJÁT feature-fáján élő, ma zöld widget-tesztek (FELVÉVE)

Ezek közvetlenül a migrálandó képernyőkre állítanak, tehát a migráció után
pirosra váltanának, ami a §0 szerint `blocked` lenne:

  - nincs ilyen.

**A jogosultság szűk:** a teszteket az ÚJ widgetekre kell ráállítani. A lefedett
viselkedést gyengíteni, cellát törölni vagy `skip`-elni **TILOS** — az a mérce
meggyengítése, amit a gate-guard emberhez eszkalál.

### R3 — keresztmetszeti tesztek (NEM kerültek listára — figyelmeztetés)

A kör fájára hivatkozó további widget-tesztek közös infrastruktúrán élnek
(`test/app/**`, `test/core/**`, más feature-ek fái) — nincs ilyen. Ezeket a kör
**NEM** szerkesztheti: ha egy elbukik, az `blocked` jelzés és célzott
brief-revízió, nem csendes átírás. A körbe húzásuk a scope-fegyelem feladása
lenne.

### R4 — a képernyő-leltár őre (H3 önjavító kör, ADR 0112, 2026-08-25)

A `test/ui/ui_inventory_test.dart` **repó-szintű** őr: a `tool/ui_inventory.dart`
a `lib/features/**` fa `_screen.dart` végű fájljait számolja, a teszt pedig
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/progress_v2/` könyvtár-előtag
alá képernyőt hoz vagy hozhat, tehát a szám **elmozdul**, és az exact-SHA Full
Gate pirosra vált.

A `test/ui/goldens/` előtag ezt **nem** fedi (az a `test/ui/` fának csak az egyik
ága), a leltárteszt utólagos felvétele pedig tágítás, azaz **H3** — az
orchestrátor a pre-flightban nem oldhatja fel ([L478](../LESSONS.md)). Ezért
kerül a listára MOST, az önjavító körben.

**MÉRVE (E13-R16, 2026-08-25):** pontosan ez a hiány állította meg a sáv első
migrációs körét — [full-gate 32867296946](https://github.com/wolfcasaba/strumsight/actions/runs/32867296946)
6366 passed / 2 failed, `hasLength(79)` a tényleges 81 ellen. A `9acd14e5`
sáv-szintű batch pre-flight azért nem találta meg, mert a `tools/brief-lint.py`
`S9` szabálya csak LITERÁLIS `*_screen.dart` útvonalat nézett, KÖNYVTÁR-előtagot
nem — a predikátumot ugyanez az önjavító kör javította, regressziós teszttel
([L483](../LESSONS.md)).

**A jogosultság PONTOSAN a szám emelése** a kör tényleges képernyőszámára; a
leltárteszt minden más állítása érintetlen marad. Kerülőút (képernyő-átnevezés
vagy a `tool/ui_inventory.dart` szabályának lazítása) **TILOS** — az a mérce
meghamisítása.

### S12 — a fa-szintű őrök a kör LOKÁLIS kapujába (2026-08-25)

A kör lokális kapuja eddig KIZÁRÓLAG a saját céltesztjeit futtatta, ezért a
teljes `lib/` fát pásztázó őrök leletei szerkezetileg csak a ~17 perces
exact-SHA Full Gate-en jelentek meg — javító kör árán. MÉRT eset: **E13-R16/F8**
(`docs/reviews/e13-r16-review.md`), ahol mind a három új képernyő közvetlenül
importálta a `design_system/foundations/**`-ot a `public.dart` helyett — **11
sértés** —, és a review szó szerint rögzíti, miért nem fogta a célzott gate:
a `tools/round-gate.sh` `architecture` lépése a `tool/check_architecture.dart`-ot
futtatja, ami egy MÁSIK, tágabb szabálykészlet; a design-system-határ mércéje
egy külön `test/core/` teszt, amit csak a teljes suite futtat.

Ezért ez a kör mostantól a `gate_tests`-ben futtatja ezeket az őröket:

- `test/core/architecture_dependency_test.dart`
- `test/tooling/dio_factory_guard_test.dart`
- `test/tooling/preferences_plugin_import_guard_test.dart`
- `test/tooling/route_literal_guard_test.dart`

A kiválasztás MÉRT, nem vaktában: a globális őrök a `Directory('lib')` teljes
fát pásztázzák (bármelyik kör diffje elmozdíthatja őket), a szűkített őrök pedig
csak akkor kerülnek fel, ha a kör `allowed_paths`-a metszi a pásztázott
gyökeret.

**Ezek az őrök NEM kerülnek az `allowed_paths`-ra** — és ez szándékos: a kör
futtatja, de NEM szerkesztheti őket, tehát a lelet javítása kizárólag a kör
SAJÁT kódjában történhet. Cella törlése, `skip`-je vagy küszöb-lazítása így
gépileg kizárt, a mérce pedig tiszta erősítést kap.

## 0.0.B — PRE-FLIGHT MÉRÉS, 2026-08-27 (`main @ ab6b5b8e`, orchestrátor Claude)

Az alábbi leletek a kör INDÍTÁSA előtt, a fán MÉRVE keletkeztek. A `brief-lint`
`S13` lelete a B1-ben oldódik fel; a többi a §1.1 két kötelező mérési szabálya
(elérhetetlen cél-státusz, erőforrás-tulajdonlás) és a merge-elt precedens
ütköztetése.

**Visszakeresett előzmény** (ADR 0312, `tools/knowledge-rag.mjs`, szűkítve →
teljes korpusz): [L403](../LESSONS.md#l403) (az E08-R23 „valódi-sértés próbája"
widget-TÍPUS szinten átengedett egy TARTALMI XP↔mastery összemosást — a próbának
a FELIRATOT és az ADATFORRÁST kell mérnie), [ADR 0378](../adr/0378-achievement-presentation-and-privacy-safe-evidence.md)
§1 (caller-fed presentation: a képernyő nem olvas repositoryt, storage plugint
és faliórát), [ADR 0388](../adr/0388-mastery-milestone-multi-session-evidence-and-explainable-badge.md)
(a több-sessionös, XP-mentes mastery-mérföldkő — EZ a merge-elt modell),
[ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md) +
[L486](../LESSONS.md#l486)/[L493](../LESSONS.md#l493) (golden csak x86-on),
[L478](../LESSONS.md#l478) (a pre-flight csak SZŰKÍTHET),
[L497](../LESSONS.md#l497) (nem létező `allowed_paths` előtag).

### B1 — `lib/features/progress_v2/` a fán NEM létezik: EZT A KÖNYVTÁRAT EZ A KÖR HOZZA LÉTRE (`S13` feloldva)

Mérve: `ls lib/features/` → 26 gyerek, közte `progress` (legacy), de
`progress_v2` **nincs**. A `brief-lint` `S13` két feloldást enged; itt a
**második** érvényes, és ez a §0.0 mondja ki: **a könyvtárat ez a kör hozza
létre, minden fájlja új.**

**Merge-elt precedens ugyanerre a mintára, ugyanezen a sávon:**
`lib/features/library_v2/` — az E13-R28 hozta létre a semmiből (18 fájl:
`domain/`, `data/`, `providers/`, `screens/`, `widgets/`, `public.dart`), a
`_v2` névadás tehát bevett, nem újítás.

**Miért nem tágítás (L478):** az előtag ma **nulla** verziókövetett fájlt fed,
tehát merge-elt kódot gépileg NEM tud elmozdítani. Szűkebb, mint a szomszéd kör
user-jóváhagyott listája (E13-R30: `lib/features/vision/presentation/`, ami
létező fát fedett). A legacy `lib/features/progress/` **tilos zóna marad** — a
§4 tilalma („`lib/features/**` a `progress_v2/` KIVÉTELÉVEL") ezt fedi.

### B2 — a kiosztott ADR `0289` MÁR MERGE-ELVE VAN: a kör ADR-t NEM ír

Mérve: `docs/adr/0289-mastery-is-evidence-not-xp.md` a fán van,
`git log` → `5b32bd8e` („docs(ch13): E13-R30..R36 briefek + ADR 0288-0292",
2026-08-15). A `docs/adr/` tilos zóna. Módosítása **H1**.

Ez a sávon a **tizennegyedik** ADR nélküli kör egymás után (E13-R17…R31). A
`tools/round-slots.py reserve-adr` lefutott és `0432`-t adott; mivel nincs új
döntés, a foglalás **vissza lett engedve** — a `0432` szabad marad. Ne keress
`0432`-es ADR-t ebben a diffben.

### B3 — a §6.1 trend-küszöb (5) ELÉRHETETLEN a merge-elt `TrendBuilder`-rel (§1.1/1. szabály)

A §1.1 első szabálya szerint nem az átmenettáblát, hanem a **tényleges inputot**
mértem:

```
grep -n "minimumSessionsForTrend" lib/features/audio_analysis/engine/comparison/trend_builder.dart
→ 9: const int minimumSessionsForTrend = 3;
→ 67: if (rawPoints.length < minimumSessionsForTrend) → TrendAvailability.unavailable
```

Tehát ha a felület a merge-elt `TrendBuilder`-t használná, **3 adatpont már
trendet adna**, és a §6.1 „a küszöb alatt" cellája (3 pont → nincs trend)
soha nem lenne előállítható.

**Feloldás — a küszöb 5 MARAD, de a saját felületén.** A mért `3` egy MÁSIK
mérce: az `audio_analysis` metrika-trendjéé
([ADR 0246](../adr/0246-analysis-session-comparison-and-trend-contract.md) §3/OD-02), aminek a
bemenete `AnalysisDocument`, nem a fejlődési idősor. Az `5` forrása a
**merge-elt [ADR 0289](../adr/0289-mastery-is-evidence-not-xp.md) §4** („a kör
mérce-mátrixában 5 adatpont, a határ inkluzív"), ezért nem alkuképes és nem is
csökkenthető.

Következmény, ami KÖTELEZŐ a kör kódjára:

- a fejlődési trend minimum-küszöbe a `lib/features/progress_v2/` fán él,
  **saját nevesített konstansként**, `5` értékkel, inkluzív határral;
- a `TrendBuilder`-t és a `minimumSessionsForTrend`-et a kör **nem hívja, nem
  importálja és nem módosítja** (§3 tiltja a számítás módosítását, a fájl
  ráadásul tilos zóna);
- a §6.1 „a küszöb alatt" cellája ezért **pontosan 3 adatpont** — nem véletlen
  szám: ez az az érték, amelynél a HIBÁS implementáció (a `TrendBuilder`
  konstansának átvétele) trendet rajzolna. A cella így falszifikációs őr, nem
  dekoráció.

### B4 — A2 „session route": a bizonyíték-hivatkozás `extra`-alapú, és a kör NEM drótozhat routert (§1.1/2. szabály)

Az erőforrás-tulajdonlást a tényleges hívási láncon mértem:

```
grep -n "librarySession\|profileLibrarySession" lib/app/routing/app_route.dart lib/app/routing/app_router.dart
→ AppRoutes.librarySession        = '/library/session'          (extra: AnalyzedSession)
→ AppRoutes.profileLibrarySession = '/profile/library/session'  (extra: LibraryItem, E13-R28)
```

Mindkét session-route a példányt **`state.extra`-ban** kapja (nincs `:id`
path-paraméter), és rossz típusú `extra` esetén a listára redirektál. Az
UI-50 SDD-route (`/profile/progress/skills/:skillId`) a fán **nem létezik**
(`grep -n "skill" lib/app/routing/app_route.dart` → 0 találat), és a
`lib/app/routing/**` **nincs** az `allowed_paths`-on.

**Ebből az A2 mércéje:**

- a képernyők **route-mentesek**: közvetlenül példányosíthatók (a teszt és a
  golden így pumpálja őket), pontosan úgy, mint az E13-R30 route-nélküli
  `VisionResultScreen`-je;
- a bizonyíték-hivatkozás **hívó által adott callbacket** hív, és a cél-route-ot
  az `AppRoutes` katalógus konstansából adja tovább — string-literál **TILOS**
  (`test/tooling/route_literal_guard_test.dart`, a `gate_tests`-ben fut);
- az A2 „megnyitható" bizonyítéka tehát: a bizonyíték-elem **megnyomható**, és a
  megnyomás a session azonosítójával EGYÜTT adja tovább a cél-route-ot. Egy
  callback nélküli, dísz-bizonyíték a cellát pirosra váltja (§9 „dísz-
  bizonyíték" kockázat).

### B5 — az SDD kilenc kötelező komponenséből HAT nem létezik; a `design_system` tilos zóna marad

Mérve (`grep -rl "class Ss…" lib/core/design_system/`):

| SDD-komponens | Van? | Mért helyettesítő |
|---|---|---|
| `SsMetricCard` | ✅ | `components/cards/ss_metric_card.dart` |
| `SsInsightCard` | ✅ | `components/cards/ss_insight_card.dart` |
| `SsCoachActionCard` | ✅ | `components/cards/ss_coach_action_card.dart` |
| `SsComparisonChart` | ❌ | `analytics/ss_chart_text_summary.dart` (+ `ss_event_list.dart`) — az E13-R27 merge-elt mintája |
| `SsTrendChip` | ❌ | `analytics/ss_trend_indicator.dart` (`SsTrendDirection.{up,down,flat,unknown}`) |
| `SsChoiceChip` | ❌ | `inputs/ss_choice.dart` (`SsChoice<T>`, `SsChoiceStyle.chip`) |
| `SsProgressIndicator` | ❌ | `analytics/ss_score_ring.dart` (`SsScoreRingState.{measured,notApplicable,unavailable}`) |
| `SsEvidenceCard` | ❌ | `surfaces/ss_card.dart` / `cards/ss_content_card.dart` + feature-lokális widget |
| `SsAiModeBadge` | ❌ | `ai/ss_provenance_badge.dart` (`SsProvenanceKind.{local,cloud}`) |

**Új DS-komponens NEM készül** — ugyanaz a szűkítés, mint az E13-R28/B5-ben és
az E13-R30-ban. A `SsScoreRingState.unavailable` / `SsTrendDirection.unknown`
ág **közvetlenül az A3-at szolgálja**: a hiányzó adatnak van saját, nem-nulla
megjelenítése a merge-elt komponensben.

A design-system importja **kizárólag** a `lib/core/design_system/public.dart`
barrelen át mehet — ezt a `test/core/architecture_dependency_test.dart` méri
(E13-R16/F8: 11 sértés, §0.0/S12).

### B6 — §7: a `flutter test --update-goldens` ütközik a merge-elt ADR 0426-tal

A brief §7-e ARM-en rögzítene goldent, amit az x86-os merge-kapu nulla
toleranciájú komparátora MINDIG pirosra vált
([ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md) §2–§3,
[L486](../LESSONS.md#l486), [L493](../LESSONS.md#l493)). A merge-elt
E13-R23…R30 precedens egységesen a `tools/golden-x86.sh record|check` alakot
használja — a §7 erre vált (lásd lentebb).

### B7 — a képernyők CALLER-FED-ek: nincs repository-, storage- és falióra-olvasás

A merge-elt [ADR 0378](../adr/0378-achievement-presentation-and-privacy-safe-evidence.md)
§1 precedense köti ezt a felületet is: a képernyő immutable projekciót kap a
hívótól, és **nem** olvas repositoryt, `SharedPreferences`-t vagy `DateTime.now()`-ot.

Miért ez a mérce ennek a körnek:

- az A6 („offline fejlődés látható") így a projekció **mezője**, nem egy
  hálózati mellékhatás — teszteléshez nem kell plugin-mock;
- a `test/tooling/preferences_plugin_import_guard_test.dart` (a `gate_tests`-ben
  fut) gépileg fogja meg a storage-plugin importot;
- a `risk = "high"` indoklása (a felület a teljes tanulási történetet
  aggregálja) így a legszűkebb: a kör kódja **nem** nyit új adat-utat.

### B8 — a `MasteryMilestone`/`MasteryProgress` a MERGE-ELT bizonyíték-modell; a kör ezt MEGJELENÍTI, nem újraszámolja

Mérve — `lib/features/gamification/domain/mastery/`, exportálva a
`lib/features/gamification/public.dart`-ból (11., 35–37. sor):

| Mért típus / mező | Mit ad a körnek |
|---|---|
| `MasteryEvidence.sessionId` | az A2 auditálható hivatkozásának azonosítója (dedup-kulcs is) |
| `MasteryEvidence.origin` (`vision`/`analysis`/`device`), `observedAt`, `confidence?` | az UI-50 „evidence date és source felolvasott" követelménye |
| `MasteryProgress.evidenceSessionCount` + `progressValue(milestone)` | az elsajátítottság **mért teljesítményből** — XP nem szerepel benne (A1) |
| `MasteryProgress.catalogVersion` (`int`, ≥1) | **az A5 verzió-mezője** — a §5.5 migrációs cella ERRE épül |
| `MasteryMilestone.minEvidenceSessions` (≥2, „single-session proof is not mastery") | az A2/A4 elégtelen-bizonyíték állapota |
| `MasterySkill` (4 érték), `MasteryMetric` (3), `MasteryDifficulty` (3), `MasteryTempoRange` | a képesség-részletnézet tengelyei |

**A brief fejléce a „verziózás" mérését írta elő — itt a mért válasz:** a
fejlődési oldalon a verzió-mező a `MasteryProgress.catalogVersion`. (A
`MetricTrend.metricVersion` a MÁSIK, `audio_analysis`-beli felületé — lásd B3;
a kettőt összekeverni A5-bukás.)

A kör ezeket a típusokat **olvassa** (a `public.dart` barrelen át) vagy
saját, ekvivalens presentation-projekcióba képezi — de a
`mastery_evaluator.dart`-ot és a `domain/mastery/**`-ot **nem módosítja** (tilos
zóna, §3).

### B9 — a képernyő-leltár őre: a mért kiindulási szám **92**

```
grep -n "hasLength" test/ui/ui_inventory_test.dart → 19: hasLength(92)
find lib/features -name '*_screen.dart' | wc -l    → 92
```

A jogosultság PONTOSAN a szám emelése a kör tényleges képernyőszámára (92 → 92 +
az új `lib/features/progress_v2/**/*_screen.dart` fájlok száma), a hozzá tartozó
magyarázó kommenttel — a teszt minden más állítása érintetlen marad (§0.0/R4).
Kerülőút (képernyő-átnevezés, a `tool/ui_inventory.dart` lazítása) **TILOS**.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

**STOP-protokoll scope-ütközésre:** ha a feladat elvégzéséhez a §4
`allowed_paths`-on KÍVÜLI fájlt kellene szerkesztened, **NE tedd meg** —
`tools/codex-signal.sh stopped "<mit és miért>"`, és a §10-be írd le, pontosan
melyik fájl és melyik acceptance-cella miatt. A lista tágítása az
orchestrátornak sem jár (H3, [L478](../LESSONS.md#l478)).

**A brief §8 a terved** — nincs külön task-lista, ne készíts sajátot.

**Doc-commentben csak tesztben bizonyított állítás** szerepelhet (`const`,
`immutable`, „soha nem X"): ha a mondat nincs cellával fedve, ne írd le.

**A munkádat commitold a branchre** (`sonnet-impl/e13-r31-progress-and-skills`).

## 1. Cél

Az UI-49–UI-50 hosszú távú, **bizonyíték-alapú** fejlődési felülete
(SDD Ch13 Kör 31).

## 2. Jelenlegi állapot — mért tények

Mérve 2026-08-27, `main @ ab6b5b8e` (a részletek §0.0.B):

- Az R27 analitika-komponensei a fán vannak: `SsChartTextSummary`,
  `SsEventList`, `SsScoreRing`, `SsTrendIndicator`, `SsConfidenceLegend`
  (`lib/core/design_system/components/analytics/`). Az ADR 0286 („hiányzó ≠
  nulla", diagram szöveges alternatívája) ezekben már megjelenik
  (`SsScoreRingState.unavailable`, `SsTrendDirection.unknown`).
- A mérőszámok **verziózottak**: a fejlődési oldalon a verzió-mező a
  `MasteryProgress.catalogVersion` (`int`, ≥1) — **ez** az A5 alapja (B8).
- Az elsajátítottság merge-elt modellje `lib/features/gamification/domain/mastery/`
  (`MasteryEvidence`, `MasteryProgress`, `MasteryMilestone`), a
  `gamification/public.dart` barrelen exportálva. `MasteryEvidence.sessionId`
  adja az A2 auditálható hivatkozását; `MasteryMilestone.minEvidenceSessions ≥ 2`
  („single-session proof is not mastery").
- Az R17 Profile Hub adja a belépési pontot (`AppRoutes.profileProgress`,
  ma a legacy `ProgressScreen`-re mutat). A kör **nem** drótoz routert (B4).
- `lib/features/progress_v2/` **nem létezik** — ez a kör hozza létre (B1).

## 3. Scope

**Benne van:** a fejlődési áttekintő új felhasználó / trend / offline /
migráció állapotai · a képesség részletnézete (elsajátítottság, előfeltétel,
**bizonyíték**, következő lépés) · időtáv-, cél- és export-vezérlők ·
diagram-összegzés és a képesség-gráf **lineáris** hozzáférhető alternatívája ·
a bizonyíték-hivatkozások a megfelelő session route-ra · mérőszám-verzió
migráció és elégtelen adat állapotai.

**NINCS benne (tilos):** a haladás- vagy elsajátítottság-számítás módosítása ·
XP-alapú elsajátítottság bevezetése · más képernyők · `docs/adr/**`,
`tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/progress_v2/` | a két felület — **ÚJ fa, ezt a kör hozza létre** (§0.0.B/B1; a `library_v2` merge-elt precedense szerint), ma NULLA fájlt fed |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — a fejlődés-szövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/progress_v2/*_test.dart` (4) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r31-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a `progress_v2/` KIVÉTELÉVEL ·
`lib/core/design_system/**` · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0289)

### 5.1 Az elsajátítottság NEM XP-alapú

A képesség szintje **mért teljesítményből** származik, nem az eltöltött időből
vagy a begyűjtött pontokból. Aki sokat gyakorol rosszul, nem lesz haladó.

**NEM elfogadható gyengítés:** az XP megjelenítése elsajátítottságként „mert
motiválóbb". Az összekeveri a részvételt a tudással.

### 5.2 A bizonyíték AUDITÁLHATÓ

Minden elsajátítottsági állítás mögött konkrét, megnyitható session áll. A
felhasználó ellenőrizheti, mire alapoztuk.

### 5.3 A hiányzó adat NEM nulla

Az ADR 0286 §1 alkalmazása a fejlődési mérőszámokra.

### 5.4 A trendhez MINIMÁLIS adatmennyiség kell

Két pontból nem rajzolunk trendet. Elégtelen adat esetén a felület ezt kimondja.

### 5.5 A mérőszám-verzió váltása LÁTHATÓ a történetben

Ha a számítás módja változott, a régi és az új szakasz megkülönböztethető — nem
látszik törésnek vagy hirtelen javulásnak.

### 5.6 Az ajánlás TISZTELETBEN TARTJA a képesség-függőségeket

Nem javasol olyan gyakorlatot, aminek az előfeltétele hiányzik.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az elsajátítottság nem XP-ből származik | `mastery_evidence_test.dart` |
| A2 | Minden elsajátítottsági állítás mögött megnyitható bizonyíték áll | ugyanott |
| A3 | A hiányzó adat NEM nullaként jelenik meg | `dashboard_states_test.dart` |
| A4 | Elégtelen adat esetén nincs trend, és ezt a felület kimondja | ugyanott |
| A5 | A mérőszám-verzió váltása látható a történetben | `metric_migration_test.dart` |
| A6 | Az offline fejlődés látható (helyi adat) | `dashboard_states_test.dart` |
| A7 | Az ajánlás nem sérti a képesség-előfeltételeket | `mastery_evidence_test.dart` |
| A8 | A diagramnak szöveges összegzése, a gráfnak lineáris alternatívája van | `chart_semantics_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r31_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Az XP elsajátítottságként megjelenítve | **A1** |
| A bizonyíték-hivatkozás nem nyit meg semmit | **A2** |
| `?? 0` a hiányzó mérőszámra | **A3** |
| Trend két adatpontból | **A4** |
| A verzióváltás hirtelen javulásként | **A5** |
| Előfeltétel nélküli gyakorlat ajánlása | A7 |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A trend három kötelező cellája** (a küszöb: a minimális adatpont-szám, **5**
— forrás a merge-elt [ADR 0289](../adr/0289-mastery-is-evidence-not-xp.md) §4,
a `progress_v2` fán élő saját konstansként, §0.0.B/B3):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | **3** adatpont | **nincs trend** — „még nincs elég adat" |
| rajta (a küszöbön) | pontosan **5** adatpont | trend megjelenik (a határ inkluzív) |
| a küszöb fölött | 30 adatpont | trend megjelenik |

**Miért pont 3 az „alatta" cella (falszifikációs őr, nem kerek szám):** a fán
mért `minimumSessionsForTrend = 3`
(`lib/features/audio_analysis/engine/comparison/trend_builder.dart:9`) egy MÁSIK
felület küszöbe. Aki azt a konstanst veszi át, **3 adatpontnál trendet rajzol**
— és pontosan ez a cella vált tőle pirosra. A `TrendBuilder` importálása,
hívása vagy módosítása TILOS (§3, tilos zóna).

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** származtasd az
elsajátítottságot az XP-ből → az **A1** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/progress_v2/dashboard_states_test.dart test/features/progress_v2/mastery_evidence_test.dart test/features/progress_v2/metric_migration_test.dart test/features/progress_v2/chart_semantics_test.dart test/ui/goldens/e13_r31_screens_golden_test.dart test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r31_screens_golden_test.dart
tools/golden-x86.sh check  test/ui/goldens/e13_r31_screens_golden_test.dart
```

> **§0.0.B/B6 — a `flutter test --update-goldens` TILOS ezen a boxon.** Az
> ARM-en rögzített pixel az x86-os merge-kapu nulla toleranciájú komparátorán
> MINDIG piros ([ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md)
> §2–§3, [L486](../LESSONS.md#l486), [L493](../LESSONS.md#l493)). A
> `tools/golden-x86.sh` a CI-vel azonos architektúrán vesz fel és ellenőriz —
> a mérce (nulla tolerancia, ugyanaz a komparátor és golden-készlet)
> változatlan. Kilépési kódok: `0` = egyezik, `10` = valódi golden-eltérés,
> `20` = környezeti hiba, `30` = hibás hívás.

A keletkezett PNG-ket **commitolni kell** — enélkül az A9 nem teljesült. A
márkabetűtípusok a teszt-hostban nem töltődnek be (fallback face); ez a
meglévő golden-teszt mért viselkedése, az elrendezést, méretezést és színeket
nem érinti. MIÉRT ez a kör dolga és nem az E13-R36-é: a záró vizuális
regressziós kör csak azt tudja megmondani, hogy valami MEGVÁLTOZOTT — azt,
hogy a képernyő eleve csúnya-e, a saját körében kell látni.

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. Az áttekintő új felhasználó / offline / migráció állapotai.
2. A trend három cellája — minimális adatmennyiséggel.
3. A képesség részletnézete, auditálható bizonyíték-hivatkozásokkal.
4. A mérőszám-verzió migráció láthatósága.
5. Az ajánlás előfeltétel-tisztelete.
6. Diagram-összegzés és lineáris gráf-alternatíva.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az XP mint elsajátítottság.** Motiválóbb és hamis: a részvételt tudásnak
  mutatja (A1).
- **A dísz-bizonyíték.** A hivatkozás ott van, de nem vezet sehova —
  auditálhatatlan állítás marad (A2).
- **A verzióváltás mint javulás.** A felhasználó azt hiszi, fejlődött, pedig a
  mérce változott (A5).

## 10. Implementation handoff — az implementer tölti ki

**Motor:** Claude Sonnet 5 (`sonnet-impl`), 2026-08-27.

### Mit épített

`lib/features/progress_v2/` — új fa, a `library_v2` mintáját követve, de
szűkítve arra, amit ez a kör ténylegesen használ (nincs `data/`, nincs
`providers/` — l. „Eltérés #1" lent):

- `domain/progress_trend.dart` — `ProgressTrendPoint`, `ProgressTrendThresholds`
  (`minimumDataPointsForTrend = 5`, saját, a `TrendBuilder`-től független
  konstans, §0.0.B/B3), `ProgressTrend` (inkluzív küszöb-logika).
- `domain/metric_version_segment.dart` — `MetricVersionSegment`,
  `segmentByCatalogVersion` (kontiguus szegmensekre bont; egy visszatérő
  verziószám ÚJ szegmenst nyit, sosem olvad vissza a korábbiba — A5).
- `domain/progress_overview_projection.dart` — `MilestoneOverviewEntry`
  (`hasEvidence`/`ratio`), `ProgressOverviewProjection` (`isOffline`,
  `isNewUser`).
- `domain/skill_detail_projection.dart` — `SkillEvidenceReference`,
  `dedupeEvidenceBySession` (a `MasteryEvidence.sessionId` dedup-kulcs),
  `SkillRecommendation`, `isRecommendationEligible` (A7 tiszta függvény),
  `SkillDetailProjection`.
- `screens/progress_dashboard_screen.dart` (UI-49) — új-felhasználó /
  offline / trend (3 cella) / mérce-verzió-előzmény / készség-sor állapotok.
- `screens/skill_detail_screen.dart` (UI-50) — elsajátítottság-gyűrű,
  auditálható bizonyíték-lista, előfeltétel-tisztelő ajánlás.
- `widgets/progress_theme_scope.dart` — a `vision_theme_scope.dart` mért
  mintája (DS `ThemeExtension`-ök az `AppTheme` mellé).
- `public.dart` barrel.

l10n: 31 új kulcs a `lib/l10n/base/app_{en,hu}.arb` forrásba
(`progressV2*` névtér, hogy ne ütközzön a legacy `progress*` kulcsokkal),
`dart run tool/gen_l10n_segments.dart --write` regenerálta az aggregátumot.

`test/ui/ui_inventory_test.dart`: `hasLength(92)` → `94` (a két új
`*_screen.dart`).

### Döntések

- **Route-mentesség (B4):** mindkét képernyő `StatelessWidget`, Riverpod
  nélkül — caller-fed (B7), nincs mit `Consumer`-ezni. A bizonyíték-sor
  `onOpenEvidence(String route, String sessionId)` callbacket hív, a
  `route` paramétert a hívó oldal `AppRoutes.profileLibrarySession`
  konstansból adja (a screen csak importálja a konstanst, nem drótoz
  routert) — a `route_literal_guard_test.dart` ezt önmagában is bizonyítja
  (nincs `.go(`/`.push(` hívás a fában).
- **"Diagram szöveges összegzése" + "gráf lineáris alternatívája" (A8)**
  — a §0.0.B/B5 táblázatot úgy értelmeztem, hogy mindkettő UGYANARRA a
  trend-adatra vonatkozik (a hiányzó `SsComparisonChart` két accessibility-
  helyettesítője EGYÜTT, ahogy az E13-R27 mintája is mutatja): a
  `_TrendSection` a `SsChartTextSummary`-t (irány + darabszám mondat) ÉS a
  `SsEventList`-et (minden trendpont saját sorban) EGYÜTT rendereli, amikor
  van trend. Ha `chart_semantics_test.dart` reviewja mást várt volna
  (pl. a készség-listára, nem a trendre), az egy nyitott kérdés — a
  §0.0.B szövege nem választja szét egyértelműen a kettőt.
- **A3 vizuális jelzés:** a hiányzó-adat állapotot a `SsScoreRing`
  `unavailable` állapota ÉS egy külön, látható "Not measured yet" szöveg
  is jelzi a listasorban (nem csak a gyűrű `semanticLabel`-je) — az L403
  lecke szerint a próbának a FELIRATOT kell néznie, nem csak
  widget-típust/kulcsot.
- **Mérőszám-verzió szegmensek (A5):** a dashboard csak akkor mutat
  „Measurement history" szekciót, ha 2+ szegmens van (egyetlen verzió
  esetén nincs mit megkülönböztetni) — ezt a `metric_migration_test.dart`
  külön esete fedi.

### Eltérések a brieftől

1. A brief §1 mintája (`library_v2`) `data/`+`providers/` alkönyvtárat is
   javasolt; ez a kör NEM hozott ilyet — B7 (caller-fed, nincs repository-
   olvasás) miatt nincs mit egy `data/`/`providers/` rétegnek csinálnia.
   Ez szűkítés, nem tágítás: az `allowed_paths` csak `lib/features/progress_v2/`-t
   sorol fel, alkönyvtár-bontást nem ír elő.
2. A golden-teszt fixture-jei és a `dashboard_states_test.dart`
   `_milestone` segédfüggvénye előbb snake_case `id`-ből képzett
   `titleKey`-t próbált átadni (`chord_transition_beginnerTitle`), amit a
   merge-elt `MasteryMilestone` konstruktor lowerCamelCase-t követel —
   `_camel()` helper hozzáadva mindkét fájlhoz. Ez a mért fán derült ki
   (gate futtatás közben), nem volt előre jelezve a brief-ben.

### Valódi-sértés próba (§7/§6.1, KÖTELEZŐ)

`lib/features/progress_v2/screens/skill_detail_screen.dart`-ban a
`statusText` számítást ideiglenesen egy fix `xpDerivedRatio = 0.42`
értékre cseréltem (szimulálva egy XP-sávból származó kijelzést
`projection.ratio` — vagyis `MasteryProgress.progressValue` — helyett),
majd lefuttattam:

```
flutter test test/features/progress_v2/mastery_evidence_test.dart
```

**Eredmény: PONTOSAN az A1 két cellája vált PIROSSÁ** —
„3 of 5 evidence sessions renders 60%…" és „a fully-achieved milestone (5
of 5) renders 100%…" — `Found 0 widgets with text "60%"` / `"100%"`, mert
minden bemenetre a fix 42%-ot renderelte. Az A2 és A7 cellák változatlanul
zöldek maradtak (a hiba nem érintette az evidence-listát vagy az
ajánlás-logikát). Ezután a módosítást visszaállítottam
(`projection.ratio`-ra), és a teljes `mastery_evidence_test.dart` újra
zöld (9/9).

### Golden (A9)

`tools/golden-x86.sh record` majd `check` — mindkettő zöld, nulla eltérés.
Felvétel közben egy valódi elrendezési hibát mért ki: a
`_MetricHistorySection` verzió-sora (`Row`) `textScaler 2.0` mellett 137
pixellel túlcsordult — `Wrap`-ra cserélve javítva, majd a golden újra
felvéve. A 4 PNG (`e13_r31_{progress_dashboard,skill_detail}_{compact,compact_scale2}.png`)
commitolva a `test/ui/goldens/goldens/` alatt (ugyanaz a beágyazott
útvonal-minta, mint az E13-R30 goldenjeinél).

### Gate kimenete

`tools/round-gate.sh` a brief §7 szerinti 10 célteszttel + `architecture` +
`secrets` + `l10n` lépéssel — **MINDEN GATE ZÖLD** (format, analyze, mind a
10 célteszt, architecture, secrets, l10n). Külön `flutter analyze lib/`
(a `flutter-analyze-fixer` konvenció szerint, önállóan futtatva) szintén
tiszta.

## 11. Review — a Claude tölti ki
