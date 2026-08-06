# ADR 0176 — Cross-feature import audit recognises nested `public.dart` barrels

**Státusz:** elfogadva (ADR 0112 önjavító kör, E04-R21 halt H3, 2026-08-06).

## Kontextus

Az `tool/check_architecture.dart` kemény szabálya (`crossFeatureImportsMustUsePublicApi`,
§214–223) szerint egy feature csak akkor importálhat egy másik feature-ből, ha a
cél **pontosan** a feature-gyökér `lib/features/<f>/public.dart`. Ez a szabály
ellentmond a projekt saját, már merge-elt kontraktjának:

- **ADR 0089** kimondja, hogy a `lib/features/song_trainer/domain/public.dart`
  „**the only entry point the rest of the app is allowed to import from**" — azaz
  a song_trainer szándékolt cross-feature domain-boundaryja egy **nested**
  `public.dart` barrel, nem a feature-gyökér (a gyökér csak prezentációs
  képernyőket exportál).
- A `domain/public.dart` fejléce maga rögzíti, hogy „the architecture guard …
  does not yet cover `song_trainer/domain`" — ismert, dokumentált rés.
- Az E04-R21 első önjavító körének mért regressziós őre
  (`tools/tests/test_r21_brief_public_boundary.py`) is **mindkét** barrelt
  (`public.dart` és `domain/public.dart`) legitim publikus felületként kezeli.

Az E04-R21 volt az **első** cross-feature fogyasztója a
`song_trainer/domain/public.dart`-nak (mérve: `grep -rn
"song_trainer/domain/public.dart" lib/ | grep -v lib/features/song_trainer/` →
0 találat a körön kívül), ezért csak most bukott ki a checker és a kontrakt
közti ellentmondás: a kör kódja **helyes** volt ADR 0089 szerint, de a checker
false-positive-ot adott (`full-gate.yml` 31064059711 = failure, architecture
exit 1) → a kör H3-mal állt meg.

## Döntés

A cross-feature import audit **bármely** olyan `public.dart` barrelt elfogad
cél-boundaryként, amely a cél-feature alatt él
(`lib/features/<targetFeature>/**/public.dart`) — a feature-gyökeret **és** a
szándékosan megírt nested barreleket (pl. `domain/public.dart`) is. Egy
`public.dart` fájl a projekt konvenciója szerint reviewelt publikus felület;
ugyanaz a bizalmi modell, mint a feature-gyökér barrelé.

**Nem gyengítés, hanem scope-pontosítás:** minden nem-`public.dart` fájl elérése
egy másik feature-ből **továbbra is sértés** — a checker ugyanúgy megfogja a
`song_trainer/domain/models/song_document.dart` közvetlen importját. Ezt gépi
regressziós teszt zárolja
(`test/core/architecture_dependency_test.dart` → „allows nested public.dart
barrels but blocks feature internals"): a fix ELŐTT piros, UTÁNA zöld, és
kizárólag az új teszt bukik a régi checkeren.

## Következmények

- Az E04-R21 re-scoped szelete (struktúra-debrief + capability-gate +
  redaction) a **már-publikus** `song_trainer/domain/public.dart`-ból,
  source-belső import nélkül, ADR 0089 szerint épül — brief-változás nélkül.
- A `main`-en nem regresszál: minden meglévő cross-feature import a
  feature-gyökér `public.dart`-ot célozza (mérve), amit az új szabály is elfogad.
- A song_trainer domain framework-függetlenségét továbbra sem ez a szabály őrzi
  (az a `_isSharedDomain` / a domain-teszt hatóköre), azt e döntés nem érinti.

## Kapcsolódó

- ADR 0089 (SongDocument V2 domain modell + a domain/public.dart boundary).
- ADR 0112 (önjavító kör protokoll).
- `docs/LESSONS.md` — a mért gyökérok és a második halt tanulsága.
