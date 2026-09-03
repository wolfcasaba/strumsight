# ADR 0500 — A Progress V2 projekciója MÉRT forrásból épül, a hiányzó forrás a kör része, és a route-váltás a legacy mélylinket megőrzi

- **Státusz:** elfogadva (2026-09-03)
- **Kontextus:** ADR 0353 („hívó-adta" prezentáció: a képernyő paramétert kap,
  nem providert olvas), ADR 0496 (az E16-R01 kompozíciós rétege — a nem
  számítható adat EXPLICIT hiány, nem hamis nulla), ADR 0471 (a képernyő
  elérhetősége MÉRT, nem feltételezett), ADR 0307 §4 (a `lib/l10n/app_*.arb`
  generált aggregátum), ADR 0123 + `docs/LESSONS.md` L90 (route-regisztrációhoz
  a kör-scope-nak a katalógust IS birtokolnia kell), kör `E16-R02`
- **Döntéshozó:** Claude (Opus 5) orchestrátor, az E16-R02 pre-flight mérése alapján
- **Megjegyzés a számozásról:** az előre megírt brief `0491`-et jelölt; az MÉRVE
  foglalt és merge-elt (`0491-practice-generator-entry-point-and-rollout.md`).
  A `tools/round-slots.py reserve-adr --round E16-R02` foglalója a `0500`-at
  adta ki erre a körre (`.pipeline/inflight/adr/0500` → `round=E16-R02`), és a
  `docs/execution/pipeline-queue.tsv` E16-R02 sora is ezt hordozza. Az ADR ezen
  a számon él (ADR 0087 §1.0.1: a foglaló a hiteles forrás, nem a brief-fejléc).

## Kontextus — a mért hiba

Az E16-R02 pre-flightja a `main @ e367048f` fán a következőket **mérte**:

| Mért parancs | Eredmény |
|---|---|
| `sed -n '543,546p' lib/app/routing/app_router.dart` | `path: AppRoutes.profileProgress` → `builder: (_, _) => const ProgressScreen()` — a legacy képernyő |
| `grep -rn "ProgressOverviewProjection\|SkillDetailProjection" --include=*.dart lib \| grep -v progress_v2/` | **0 találat** |
| `find lib/features/progress_v2 -type f` | 8 fájl: 2 képernyő, 4 domain-projekció, 1 téma-burkoló, 1 barrel — **0 provider, 0 `application/`, 0 `data/`** |
| `grep -rn "List<MasteryMilestone>\|milestoneCatalog\|masteryCatalog" --include=*.dart lib` | **0 találat** — produkciós mastery-katalógus nincs |
| `grep -rln "MasteryEvidence" --include=*.dart lib` | 4 fájl — **egyetlen `data/` előállító sem** |
| `grep -o '"[a-zA-Z0-9]*"' lib/l10n/app_en.arb \| grep -ic "mastery\|milestone"` | 3 kulcs, mind chrome — **0 milestone-cím/leírás** |

A `progress_v2` felület tehát **elkészült, de halott kód**: a képernyők
szerződése „hívó-adta" (`required this.projection`), a projekciót viszont senki
nem állítja elő, és a `/profile/progress` a legacy `ProgressScreen`-t építi.

**A döntő mérés** az volt, hogy a route puszta átkötése ROSSZABB lett volna, mint
a semmittevés. Üres `milestones` listával
`ProgressOverviewProjection.isNewUser` **igaz** (`[].every(...)` → `true`,
`progress_overview_projection.dart:65`), tehát a `ProgressDashboardScreen`
kizárólag a `_NewUserState`-et rendereli (`progress_dashboard_screen.dart:38`):
a MA valós adatot mutató legacy képernyőt egy ÖRÖKRE üres „get started"
képernyőre cseréltük volna, miközben minden acceptance-cella zöld marad, mert
közvetlenül eteti a projekciót (L397/L449 hibaosztály).

## Döntés

### D1 — A hiányzó FORRÁS a kör része; nem a cellákat gyengítjük, és nem halasztunk

A két mért opció közül (a) a route-váltás halasztása az `E16-R03` előfeltételét
(„a kompozíciós rétege valós adatot ad") is érintette volna, és az A1/A2/A5
cellák törlésével JÁRT volna; (b) a hiányzó mastery-forrás (katalógus + evidencia-
adapter + l10n) felvétele a scope-ba egyetlen cellát sem vesz el. A kör a (b)
utat választja: a katalógus, az adapter és a milestone-l10n a kör `allowed_paths`
listájának része, a küszöböket az `A8`–`A12` cella pinneli, és az `A10` pontosan
a fenti „örökre üres dashboard" hibamódot viszi pirosra.

### D2 — A projekció-builder DETERMINISZTIKUS és tiszta

Azonos bemenet → azonos kimenet. `DateTime.now()` és `Random` a builderben
TILOS: az aktuális időt a hívó adja paraméterként. Ez az ADR 0353 „hívó-adta"
szerződésének kiterjesztése a projekciós rétegre, és statikus cella (`A6`) méri
a forrásszövegen, nem csak viselkedésből.

**Nem elfogadható gyengítés:** „az aktuális dátum kell hozzá" — az paraméter,
nem mellékhatás.

### D3 — Hiányzó mérés = EXPLICIT üres állapot, SOHA nem nulla

Ha egy készség-tengelyhez nincs mérés, a projekció ezt jelöli, és a képernyő
üres állapotot mutat. A `0`-val kitöltött trend visszaesésnek látszik, tehát a
felhasználó a saját fejlődéséről kapna téves képet — ez ugyanaz a döntés, amit
az ADR 0496 a gamification-oldalon már kimondott, itt a progress-oldalra
kiterjesztve.

Az adapter szintjén ez konkrétan: `PracticeMetricDimension` nem
`...Available` → **NINCS bizonyíték** (nem `0`); ismeretlen `definitionId` →
**NINCS bizonyíték** (nem „beginner"-nek vett alapértelmezés).

### D4 — A legacy `/progress` mélylink átirányít, nem tűnik el

A `/progress` a redirect-lánc végén a `/profile/progress` képernyőjét adja. A
mélylink csendes megszüntetése mentett hivatkozásokat törne (`A5`).

### D5 — A v1 mastery-katalógus annyi, amennyire MÉRT forrás van

Három milestone (`chordTransition`, `rhythmAccuracy`, `strumConsistency`),
`minimumThreshold = 0.8`, `minEvidenceSessions = 3`, `catalogVersion = 1`.

- Az id-k **lower snake_case**-ek, mert a domain `_requireStableId`-je a
  `^[a-z][a-z0-9_]*$` regexet követeli (`mastery_milestone.dart:161`) —
  pontozott id futásidőben `ArgumentError`-t dob.
- A katalógus **`final` + `List.unmodifiable`**, NEM `const`: a
  `MasteryMilestone` és a `MasteryTempoRange` publikus felülete factory
  (`:86`, `:39`), a `const` konstruktoruk privát (`:136`, `:44`) — publikus
  `const` példányosítás mérhetően lehetetlen.
- A `difficulty` **`MasteryDifficulty.beginner`**, mert az evaluator az eltérő
  nehézségű bizonyítékot ELDOBJA
  (`application/mastery_evaluator.dart:108`), a builtin katalógus 10
  definíciójából pedig 8 `beginner` és 2 `intermediate`. Az `intermediate`
  definícióból származó session a v1-ben SZÁNDÉKOSAN nem ad bizonyítékot — ezt
  a cella kimondja, nem elhallgatja.
- `MasterySkill.tempoStability` a v1-ben **NEM kap milestone-t**: a fán nincs
  mért `tempoAdherence` forrás (a `highestStableTempoBpm` a Speed Builder
  csúcs-tempója, nem adherence-metrika). DOKUMENTÁLT hiány — kitölteni TILOS.

**Nem elfogadható gyengítés:** a küszöb csökkentése azért, hogy „legyen mit
mutatni"; a nehézség-szűrő megkerülése azzal, hogy az adapter minden sessiont
`beginner`-nek jelöl.

### D6 — Két projekciós mező MÉRT ÁLLANDÓ, nem kitöltés

- `ProgressOverviewProjection.isOffline = false`: a fejlődés-adat 100%-ban
  helyi (a `practiceHistoryRepositoryProvider` lokális tár, a progress semmit
  nem szinkronizál a fiókkal), tehát „még nem szinkronizált helyi állapot" nem
  létezhet.
- `SkillDetailProjection.recommendation = null`: ajánlás-katalógus a fán nincs,
  a mező opcionális — az EXPLICIT hiány a helyes érték. Kitalált ajánlás TILOS.

### D7 — A lokalizált cím EXPLICIT leképezéssel jön, és az aggregátum generált

A 3 cím + 3 leírás kulcs a `lib/l10n/features/gamification_{en,hu}.arb`
szegmensbe kerül (MINDKÉT locale), majd `dart run tool/gen_l10n_segments.dart
--write` regenerálja a `lib/l10n/app_{en,hu}.arb` **aggregátumot**, amit kézzel
közvetlenül szerkeszteni tilos (ADR 0307 §4). A `titleKey`/`descriptionKey` →
lokalizált szöveg feloldás a kompozíciós rétegben EXPLICIT `switch`-csel
történik; dinamikus kulcs-feloldás TILOS.

### D8 — A skill-detail útvonal alakja KÖTÖTT

`AppRoutes.profileProgressSkill = '/profile/progress/skills/:skillId'` — az SDD
UI-50 kanonikus route-ja, amit a `SkillDetailScreen` doc-commentje is néven
nevez. **Paraméteres útvonal-szegmens, NEM `extra`-alapú.** A `:skillId` a
`MasterySkill.code`; ismeretlen vagy hiányzó `skillId` → átirányítás az
`AppRoutes.profileProgress`-ra (a `profileLibrarySession` merge-elt mintája) —
404 vagy dobás TILOS. A konstans az `app_route.dart` katalógusban él, mert a
`test/tooling/route_literal_guard_test.dart` tiltja a navigációs
útvonal-literálokat (L97/L246 hibaosztály: a wiring engedve, a katalógus nem).

## Következmények

- A `progress_v2` felület élővé válik: a `/profile/progress` valós, mért adatból
  számított projekciót renderel, és a skill-detail képernyő először lesz
  elérhető a fán.
- A gamification-oldal kap egy produkciós mastery-katalógust és egy
  gyakorlás-történet → bizonyíték adaptert; az `MasteryEvaluator` VÁLTOZATLAN
  marad (a dedup és a monotonitás továbbra is az ő dolga).
- **Ismert, dokumentált hiány:** a gyakorlás-történet nem őrzi a ténylegesen
  játszott tempót (a `highestStableTempoBpm` egyedül a Speed Builder futásából
  származik), ezért a v1 milestone-ok tempó-hatóköre szándékosan a teljes
  tartomány — a tempó egyetlen bizonyítékot sem zár ki és egyetlen felhasználói
  számot sem befolyásol. A hiány egy későbbi history-séma körre marad.
- `MasterySkill.tempoStability` milestone nélkül marad, amíg mért
  `tempoAdherence` forrás nem születik.
