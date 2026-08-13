# ADR 0231 — Target alignment engine határa

- **Státusz:** Elfogadva (E06-R13 pre-flight, 2026-08-12)
- **Kör:** E06-R13 — Target alignment engine
- **Kapcsolódó szerződések:** SDD Ch7 §9.4 (AnalysisTarget), §14.5 (Known
  target előnye), §15.1 (Target alignment), §15.2 (Timing error), §15.4
  (Toleranciaablak), §27.1 (Practice Engine adapter); [ADR
  0226](0226-clip-analyzer-stage-boundary-and-fallback-provenance.md), [ADR
  0228](0228-event-evidence-model-and-timeline-builder-contract.md), [ADR
  0230](0230-beat-grid-tempo-curve-boundary.md)

## Kontextus

Az előre elkészített R13 brief egy `AnalysisTarget`/`ExpectedEvent`/
`AlignmentResult` domain modellt és egy `EventAligner`/`TolerancePolicy`
engine-párt ír elő — a megfigyelt (R10 event evidence, R12 beat grid) és az
elvárt események első, Audio-Analysis-saját illesztését.

A pre-flight kimérte a mai `main`-en (`ce4b6b24`):

- `AnalysisTarget` **nem létezik** az `audio_analysis` fán (`grep -rln "class
  AnalysisTarget" lib/features/audio_analysis/` üres); a `domain/target/` és
  `engine/alignment/` alkönyvtárak sem léteznek — az R13 teljes felülete ÚJ.
- A `ClipAnalyzer`-nek nincs target-fogalma — a mai Analyze út szabad játékot
  elemez.
- A Practice Engine-nek **saját, meglévő** illesztése van:
  `lib/features/practice/domain/model/compiled_practice_target.dart`
  (`CompiledPracticeTarget`/`CompiledTargetEvent`) +
  `lib/features/practice/domain/service/practice_event_matcher.dart` +
  `test/property/practice_event_matcher_property_test.dart` — ez a Practice
  pontozásának szerződése (SDD §27.1: „A Practice Engine saját pontozási
  contractja marad a termék elsődleges session score forrása. Az Audio
  Analysis részletes evidence-t ad hozzá, nem írja felül önkényesen.").
- Az R12 (ADR 0230, 3. döntés) explicit kimondta, hogy `AnalysisTarget` „csak
  a következő, E06-R13 kör saját contractja; R12-ben nem létezik" — ez a kör
  most váltja be azt az ígéretet.

**Mért, nem blokkoló dokumentációs eltérés:** a brief §9 kockázat-szakasza
„metric version emelést von maga után (ADR 0203)"-ra hivatkozik. `docs/adr/`
alatt **nincs 0203 számú ADR** — ugyanez a hivatkozás hét másik, batch-ben
előre megírt E06 brief-ben is szerepel (R02, R14, R16, R19, R20, R25), tehát
egy, az Epic 6 korai tervezéséből (az R01 kickoff előtti szakaszból)
megmaradt, még be nem váltott placeholder-szám, nem R13-specifikus hiba. R13
allowed_paths-a nem érinti a metric-katalógust, és a hivatkozás egy
kockázat-narratívában áll, nem acceptance-cellában — nem blokkoló, csak
dokumentált eltérés (AGENTS.md §2). A metric-verzió tényleges kérdését a
katalógust ténylegesen módosító jövőbeli kör oldja fel.

## Döntés

1. **Az illesztés monoton dinamikus programozás.** Ha `observed[i] ↔
   expected[j]`, akkor `observed[i+1]` csak `expected[k], k > j`-vel
   párosulhat; keresztező pár nem megengedett. Greedy legközelebbi-szomszéd
   NEM elfogadható (SDD §15.1 kivétele — „bizonyítottan egyszerű use case" —
   itt nem áll fenn).
2. **Determinisztikus tie-break.** Azonos költségű jelöltek közül a
   **korábbi** expected index nyer; a döntés nem függhet `Map`/`Set`
   iterációs sorrendtől.
3. **Bemenet-immutabilitás.** Az `EventAligner` sem az observed, sem az
   expected listát nem mutálja.
4. **Tempófüggő tolerancia, clamp-pel.** `tolerance = clamp(beatDuration ×
   ratio, minMs, maxMs)`; `ratio`/`minMs`/`maxMs` néven nevezett, verziózott
   konstansok a `tolerance_policy.dart`-ban (kezdeti érték: `ratio = 0.25`,
   `minMs = 40`, `maxMs = 150` — ideiglenes az R29 kalibrációs körig, brief
   OD-03). Fix milliszekundum minden tempón NEM elfogadható (SDD §15.4).
5. **A target immutable snapshot**, nem élő referencia (SDD §9.4): nincs
   benne provider-, controller- vagy repository-hivatkozás; a
   `targetVersion` a provenance-be kerül.
6. **Korlátos, dokumentált komplexitás.** A DP sávos (a sáv szélessége a
   toleranciából adódik), `O(n·m)` idő, `O(min(n,m))` memória.
   Dokumentálatlan `O(n³)` nem elfogadható (SDD Kör 13 elfogadási feltétel).
7. **Költségfüggvény (OD-01 alapértelmezés).** `cost(match) = |Δt| /
   tolerance` (0..1 a toleranciaablakon belül, afölött nem párosítható) `+
   0.5` irány-eltérésnél `+ 0.25` eseménytípus-eltérésnél, mindez `(2 −
   observedConfidence)` szorzóval; `cost(missed) = 1.0`; `cost(extra) = 1.0`.
   Minden együttható néven nevezett, verziózott konstans — kalibrálatlan,
   PENDING eval-mátrix sorral (kockázat, brief §9).
8. **A toleranciaablakon kívüli pár nem párosítható** (OD-02): a maximum
   match window kemény korlát; azon túl missed + extra keletkezik — ez teszi
   helyessé a sávos DP-t.
9. **Scope-határ:** a Practice Engine saját illesztője
   (`CompiledPracticeTarget`/`CompiledTargetEvent`/`practice_event_matcher.dart`)
   **nem módosul és nem kerül importálásra** — az R13 kizárólag az Audio
   Analysis saját, párhuzamos `AnalysisTarget`/`EventAligner` felületét adja.
   A Practice-oldali fordítás/adaptálás az E06-R26 dolga (SDD §27.1).

## Elutasított alternatívák

- **Greedy legközelebbi-szomszéd illesztés** — korai/késői klaszterekben
  keresztező párokat termel; a monotonitás property-t megbuktatná.
- **A Practice Engine meglévő matcherének újrafelhasználása vagy
  kiterjesztése** az Audio Analysis célra — feature-határt sértene (a
  `practice/**` nem importálható az `audio_analysis` alól) és felülírná a
  Practice saját, elsődleges pontozási szerződését (SDD §27.1).
- **Fix milliszekundum tolerancia minden tempón** — a SDD §15.4 kifejezetten
  kizárja; nem venné figyelembe a tempó hatását az emberi időzítés-észlelésre.
- **Teljes `O(n·m)` mátrix-allokáció korlátlan bővítéssel** — a brief §9
  teljesítmény-kockázata (2000×2000 megfuttatás) miatt dokumentálatlan
  memóriakölséget okozna; a sávos DP ehelyett a toleranciából származó
  korlátos sávot allokál.
- **A toleranciaablakon kívüli párosítás engedélyezése** — végtelenítené a
  kereshető jelöltek terét, és ellentmondana a SDD §15.1 „maximum match
  window" kötelező elemének.

## Következmények

**E06-R30 (2026-08-13):** a döntés változatlan; a feature flag OFF.

- Az illesztő motor teljesen **bekötetlen** száll: nincs UI-, Practice- vagy
  Song-adapter, nincs metrika-számítás — ezek R14+ (timing), R26 (Practice
  adapter) feladatai. Production viselkedés (V1 Analyze, Practice scoring)
  bitre változatlan marad.
- A költségfüggvény együtthatói **kalibrálatlanok** — bármely jövőbeli
  módosításuk metric-version emelést igényel (a metric-katalógus tényleges
  ADR-jét a katalógust módosító kör rögzíti; l. a fenti dokumentált eltérést
  az „ADR 0203" placeholder-hivatkozásról).
- A Practice Engine saját illesztése és pontozása marad az elsődleges,
  felhasználó felé megjelenő session score forrása; az `EventAligner`
  kimenete a jövőbeli Audio Analysis metrikák (R14–R16) bemenete, nem a
  Practice pontszám helyettesítője.
