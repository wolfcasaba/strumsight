# E13-R05 — Független review

Brief: `docs/rounds/e13-r05-spacing-and-surfaces.md`
Diff: `12d0a846..0ffceb95`
Reviewer: Codex Sol (`gpt-5.6-sol`) · Dátum: 2026-08-21
Verdikt: **APPROVED**

## Összegzés

Nyitott BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

A Terra javító commit (`ee12446b`) lezárta F1–F6 minden MAJOR leletét. A friss
izolált re-review gate 7/7 zöld; a hat reviewer-visszarontás mind a hozzá
tartozó production regressziós cellát vitte pirosra, restore után a klón tiszta.

## Acceptance criteria

| # | Teljesült | Bizonyíték |
|---|---|---|
| A1 | ✅ | fix `SsSpacing.space4/space6/space2` API; nyers `double` visszahelyezése piros |
| A2 | ✅ | base exact `surface`; emelt szintek `surfaceRaised`-alapú canonical fixture-rel |
| A3 | ✅ | dark shadow 0; light shadow 1/2/4, központosított resolver |
| A4 | ✅ | `safeArea: true` egy `SafeArea`-t épít nested esetben |
| A5 | ✅ | hero source-őr és architecture gate; nincs feature/provider import |
| A6 | ✅ | mindhárom téma × négy szint renderel |
| A7 | ✅ | `Radius.circular(9)` rontás a source-őrt pirosra vitte |
| A8 | ✅ | distinct `border`/`borderStrong` témán a selector-rontás piros |
| A9 | ✅ | három téma × négy szint pinelt ARGB/border-width/shadow fixture; blend-rontás piros |
| A10 | ✅ | nested surface 2.0 text scale-en exception nélkül renderel |
| A11 | ✅ | 320/600/840 szélesség 16/24/32 dp tokenre oldódik |
| A12 | ✅ | `Radius.circular`, `BorderRadius.circular`, only/all és directional inset guardian cellák zöldek |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e13-r05 --brief
docs/rounds/e13-r05-spacing-and-surfaces.md --base 12d0a846` →
`Legacy scope audit OK`, 10 módosított útvonal, 0 generated/ignored. A wrapper
jelzése is `scope_audit=ok`; a jelzéskori `dirty_files=1` után a tényleges
`git status --short` tiszta volt, ezért nem maradt elfogadatlan diff.

## Megállapítások

### F1 — MAJOR — A base szint a raised szemantikai tokent használja

- **Fájl:** `lib/core/design_system/foundations/ss_elevation.dart:48-57`
- **Probléma:** `_elevatedBackground` minden szinten `colors.surfaceRaised`
  forrásból indul. `blend == 0` mellett a `base` ezért nem
  `SsColorScheme.surface`, hanem `surfaceRaised`.
- **Bizonyíték:** eldobható reviewer-cella külön `surface = 0xFF010101` és
  `surfaceRaised = 0xFF020202` tokennel `colors.surface`-t várt a base-re;
  ténylegesen `0xFF020202` érkezett, a cella piros lett.
- **Hatás:** amint az R03 legacy-kompatibilis, ma azonos két tokenje szétválik,
  a base surface raised színt kap, vagyis a hierarchy jelentése felcserélődik.
- **Kötelező javítás:** a base exact `colors.surface` legyen; az emelt szintek
  külön, explicit `surfaceRaised`-alapú úton oldódjanak. A fenti distinct-token
  regressziós cella kerüljön a production tesztbe.
- **Státusz:** FIXED (`ee12446b`) — distinct surface/surfaceRaised cella; a
  base-rontás a re-review-ban piros.

### F2 — MAJOR — A „golden” mátrix nem fogja meg a vizuális blend-driftet

- **Fájl:** `test/core/design_system/surfaces/ss_surface_test.dart:29-46`
- **Probléma:** a teszt csak ugyanazon resolver kétszeri eredményét és a négy
  háttér különbözőségét méri. Nem pineli a canonical háttér-, border- és
  shadow-értékeket.
- **Bizonyíték:** `_raisedBlend = .04` → `.05` production mutáció után a teljes
  `ss_surface_test.dart` **15/15 zöld** maradt.
- **Hatás:** a vizuális hierarchy észrevétlenül driftelhet, miközben A9 hamisan
  zöld marad; ez nem helyettesíti a briefben vállalt deterministic golden
  contractot.
- **Kötelező javítás:** témánként és szintenként pinelt, a production
  resolverből nem visszaszámolt canonical ARGB/border/shadow fixture kell;
  legalább a `.04 → .05` rontás legyen piros.
- **Státusz:** FIXED (`ee12446b`) — resolverfüggetlen canonical fixture; a
  `.04 → .05` re-mutation több theme-mátrix cellát pirosra vitt.

### F3 — MAJOR — A High Contrast border selector őre hamisan zöld

- **Fájl:** `test/core/design_system/surfaces/ss_surface_test.dart:81-93`
- **Probléma:** a shipping High Contrast témában `border == borderStrong`, így
  az értékegyenlőség nem bizonyítja, hogy az emelt szint a `borderStrong`
  szemantikai ágat választja.
- **Bizonyíték:** a resolver `borderStrong` ágának `border` tokenre rontása
  után a név szerint ezt őrző cella és a teljes surface suite is zöld maradt.
- **Hatás:** későbbi token-szétválásnál a High Contrast emelt felület gyenge
  bordert kaphat regressziós jel nélkül.
- **Kötelező javítás:** distinct `border`/`borderStrong` extensionnel épített
  teszttéma vagy egyenértékű semantic-selector cella kell; a fenti mutációnak
  pirosnak kell lennie.
- **Státusz:** FIXED (`ee12446b`) — distinct semantic színek; a
  `borderStrong → border` re-mutation célzottan piros.

### F4 — MAJOR — A raw-radius őr nem a production konstruktoralakot figyeli

- **Fájl:** `test/core/design_system/surfaces/spacing_grid_test.dart:22-38`
- **Probléma:** a regexp csak `BorderRadius.circular(<literal>)` alakot tilt,
  miközben a production `BorderRadius.all(Radius.circular(...))`-t használ.
- **Bizonyíték:** `Radius.circular(radius.value)` → `Radius.circular(9)`
  rontás után a `spacing_grid_test.dart` **3/3 zöld** maradt.
- **Hatás:** a briefben név szerint tiltott rácson kívüli radius pontosan a
  shipping konstruktorban átcsúszhat.
- **Kötelező javítás:** a source-őr fedje a `Radius.circular`, a
  `BorderRadius.circular` és az alkalmazott directional/only constructorokat;
  a 9 dp mutáció legyen piros.
- **Státusz:** FIXED (`ee12446b`) — a guardian a production constructoralakot
  is fedi; `Radius.circular(9)` re-mutation piros.

### F5 — MAJOR — A komponens-API rácson kívüli spacinget fogad

- **Fájl:** `lib/core/design_system/components/surfaces/ss_card.dart:9-16`,
  `ss_hero_card.dart:9-16`, `ss_section.dart:7-16`
- **Probléma:** a publikus `double padding/spacing` paraméterekhez nincs
  token-típus vagy runtime validáció; `13` közvetlenül átjut.
- **Bizonyíték:** eldobható reviewer-cella az `SsCard(padding: 13)`,
  `SsHeroCard(padding: 13)` és `SsSection(spacing: 13)` konstrukcióktól
  `ArgumentError`-t várt; már az első objektum normálisan létrejött.
- **Hatás:** a primitivek éppen azt az ad hoc geometriát teszik publikus API-n
  legálissá, amelyet A1 és az ADR 0385 tilt.
- **Kötelező javítás:** fix tokenes defaultok vagy zárt token-típusú publikus
  API szükséges; nyers `double`-lal off-grid érték ne legyen átadható.
- **Státusz:** FIXED (`ee12446b`) — a három primitive fix tokenes spacinget
  használ; nyers `double padding = 13` visszahelyezése piros.

### F6 — MAJOR — Az SsCard redundáns külső Material Cardot épít

- **Fájl:** `lib/core/design_system/components/surfaces/ss_card.dart:18-31`
- **Probléma:** az `SsCard` egy átlátszó Material `Card` belsejében építi meg
  az `SsSurface` saját `Material` felületét. A külső réteg külön 12 dp default
  shape-et hordoz, miközben a belső a kötött 16 dp tokent használja.
- **Bizonyíték:** eldobható widgetcella pontosan egy `Material` descendantot
  várt az `SsCard` alatt; ténylegesen kettőt talált (külső card 12 dp, belső
  surface 16 dp).
- **Hatás:** felesleges nested surface-struktúra és két eltérő shape-contract
  marad a komponensben, szemben a Chapter 13 és ADR 0385 compositional
  követelményével.
- **Kötelező javítás:** az `SsCard` közvetlenül az egyetlen `SsSurface`-t
  kompozálja; production regressziós cella mérje az egy Material felületet.
- **Státusz:** FIXED (`ee12446b`) — az `SsCard` közvetlenül `SsSurface`-t ad;
  a külső `Card` visszahelyezése két Material miatt piros.

### N1 — NOTE — A javító wrapper egy köztes láncolt tesztparancsot jelzett

A javító `.codex-round-status` `gate_shape=VIOLATION` értékét az implementer
köztes `dart format ... && flutter test ...` parancsa okozta. Ez nem az
elfogadott gate-bizonyíték: utána két exact, csonkítatlan
`tools/round-gate.sh ...` futás zöld lett, majd a reviewer friss klónban
ugyanazt az artefaktumot 7/7 zöldre futtatta. A processzeltérést rögzítjük;
merge-evidenciaként kizárólag az exact artefaktumot használjuk.

## Gate-bizonyíték

Izolált review-klón: `/tmp/review-e13-r05`, exact commit `0ffceb95`.

- scope-audit: 10 útvonal, 0 sértés;
- format: 1775 fájl, 0 változás;
- analyze: 0 issue;
- surface suite: 15/15 zöld;
- spacing suite: 3/3 zöld;
- architecture, secrets (3182 fájl / 0 lelet), l10n (1532/1532): zöld;
- `.04 → .05` blend mutáció: hamisan 15/15 zöld (F2);
- `borderStrong → border` mutáció: hamisan zöld (F3);
- `Radius.circular(9)` mutáció: hamisan 3/3 zöld (F4);
- distinct base/raised token reviewer-cella: piros, tényleges base = raised (F1);
- off-grid publikus spacing reviewer-cella: piros, 13 dp elfogadva (F5);
- one-Material reviewer-cella: piros, 2 descendant (F6);
- minden reviewer-módosítás visszaállítva; a review-klón tiszta.

Friss re-review klón: `/tmp/review-e13-r05-fix1`, exact commit `ee12446b`:

- fix-fázis scope-audit: 7 módosított útvonal, 0 sértés;
- teljes kör scope-audit: 11 útvonal, 1 generated/ignored review-report,
  0 sértés;
- format: 1775 fájl, 0 változás; analyze: 0 issue;
- surface suite: 17/17 zöld; spacing suite: 5/5 zöld;
- architecture, secrets (3183 fájl / 0 lelet), l10n (1532/1532): zöld;
- F1/F2/F3 közös resolver re-mutation: 5 célzott failure;
- F4/F5/F6 közös geometry/API/composition re-mutation: 4 célzott failure;
- restore után `git diff --exit-code` 0, tiszta klón.

A teljes CI-suite/property workflow még nem futott; az exact-SHA CI és a
friss-main landolás továbbra is merge-feltétel.

Az `origin/main @ 3000e9fa` beépítése után a kombinált `914034db` HEAD-en az
E13-R05 production-, test-, brief-, ADR- és review-fájlkészlet byte-azonos
maradt a jóváhagyott `48ff0afa` csúccsal. Friss izolált klónban a teljes
7 lépéses round-gate újra zöld lett (format 1778/0, analyze 0, surface 17/17,
spacing 5/5, architecture, secrets 3189/0, l10n 1532/1532).

## Merge-döntés

A correctness review **APPROVED**. Merge csak az exact-SHA Full Gate/Router CI
és a friss-main landolási feltételek zöld eredménye után engedett.

---

# E13-R05 — Folytatás-review (A13 katalógus-contract)

Brief: `docs/rounds/e13-r05-spacing-and-surfaces.md` (§0.0.1 + §0.0.2)
Diff: `a212b8fb..2af6eca4` · Implementer: `sonnet-impl` (claude-sonnet-5)
Reviewer: Claude (Opus 5), orchestrátor-szék · Dátum: 2026-08-23
Verdikt: **APPROVED**

## Összegzés

Nyitott BLOCKER: 0 · MAJOR: 0 · MINOR: 1 · NOTE: 0

A folytatás egyetlen nyitott munkája a §0.0.1 által megnyitott **A13** cella
volt: a `component_catalog_test.dart` három `find.byType(Card)` elvárásának
átállítása `SsCard` + a `SsCard` alá szűkített, pontosan egy `Material`
leszármazott mérésére. A diff pontosan ennyi (2 útvonal, 60 beszúrás), a
produkciós Dart-kódhoz nem nyúlt, és a `wrapper` gépi scope-auditja
`scope_audit=ok` (base `a212b8fb`, 2 módosított útvonal).

## Acceptance criteria

| # | Teljesült | Bizonyíték |
|---|---|---|
| A13 | ✅ | `find.byType(SsCard)` + `find.descendant(of: SsCard, matching: Material)` `findsOneWidget` mindhárom cellában; reviewer-mutáció pirosra viszi (lásd P1) |
| route-kapu (ADR 0273) | ✅ | a `default-off` és a három `createRouteForTesting` null-cella érintetlen; P3 bizonyítja, hogy tényleg fog |
| dark/light smoke | ✅ | mindkét téma cellája zöld, a pumpelés változatlan |
| A1–A12 | ✅ (változatlan) | az előző review-ban lezárva; a folytatás nem nyúlt hozzájuk |

## Scope-audit

Wrapper: `scope_audit=ok`, `scope_audit_base=a212b8fb…`, `scope_audit_changed=2`.
Ténylegesen módosított útvonalak:
`test/core/design_system/component_catalog_test.dart` és
`docs/rounds/e13-r05-spacing-and-surfaces.md` (§10) — mindkettő az
`allowed_paths` listán. Listán kívüli fájl nincs. A jelzéskori `dirty_files=1`
után a tényleges `git status --short` üres volt (a jelzésfájl maga) — nem
maradt el nem fogadott diff.

## Gate-bizonyíték (független, izolált klón)

Klón: `/tmp/review-e13-r05-cont`, exact commit `2af6eca4`,
`tools/prepare-flutter-generated.sh` után. A §7 szerinti **háromútvonalas**
gate csővezeték nélkül, teljes kimenettel:

- `[1] format` 1885 fájl / 0 változás — zöld
- `[2] analyze` `No issues found!` — zöld
- `[3] ss_surface_test.dart` **17/17** — zöld
- `[4] spacing_grid_test.dart` **5/5** — zöld
- `[5] component_catalog_test.dart` **8/8** — zöld
- `[6] architecture` OK (12 allowlisted deviation) — zöld
- `[7] secrets` 3482 fájl / 0 lelet — zöld
- `[8] l10n` parity OK (en → hu, 1755 üzenet) — zöld

`MINDEN GATE ZÖLD`, **exit 0**.

## Valódi-sértés próbák (reviewer, eldobható)

| # | Rontás | Mért eredmény |
|---|---|---|
| **P1** | `SsCard.build()` `SsSurface`-e külső `Card(...)` rétegbe csomagolva (második `Material`) | mindhárom cella PIROS, `+5 -3`; `Found 2 widgets with type "Material" descending from …` / `is too many` |
| **P2** | az `SsCard` kivéve a katalógus-képernyőről | mindhárom cella PIROS, `Found 0 widgets with type "SsCard"` — a finder **nem vakcella** |
| **P3** | a route-kapu `\|\|` → `&&` lazítása | a `default-off` és két null-cella PIROS, `Expected: null / Actual: MaterialPageRoute<void>` — az ADR 0273 fejlesztői-eszköz szerződés tényleg mérve van |

Minden rontás visszaállítva; `git diff --exit-code` 0, a review-klón tiszta.

## Megállapítások

### M1 — MINOR — a §10 „Futtatott ellenőrzések" a RÉGI, kétútvonalas gate-sort őrzi

- **Fájl:** `docs/rounds/e13-r05-spacing-and-surfaces.md` §10
- **Mit mértem:** a §10 zárólistája továbbra is a javítókör
  `tools/round-gate.sh <ss_surface_test> <spacing_grid_test>` hívását rögzíti,
  a §7 által előírt **háromútvonalas** (a `component_catalog_test.dart`-ot is
  tartalmazó) futást nem vezeti át a zárólistába.
- **Miért nem MAJOR:** a háromútvonalas gate ténylegesen lefutott (az
  implementer logja tartalmazza a pontos hívást, és a wrapper `gate_shape=ok`
  jelzést adott), a §10 A13-szakasza pedig külön dokumentálja a
  `component_catalog_test.dart` 8/8-át. Ettől függetlenül a fenti,
  reviewer-oldali izolált klónban **magam is lefuttattam** a teljes
  háromútvonalas gate-et, exit 0-val — a mérce tehát nem az implementer
  jelentésén nyugszik. Dokumentációs pontatlanság, nem mérce-hiány.
- **Javasolt kezelés:** nem blokkol; a következő, e fájlt érintő kör
  frissítheti a sort.

## Merge-döntés

A correctness review **APPROVED** (0 nyitott BLOCKER/MAJOR). A merge feltétele
változatlanul az exact-SHA `full-gate.yml` **és** `router-ci.yml` zöldje a
merge SHA-ján (ADR 0086 §2, ADR 0171 §3), valamint a friss-main landolás.
