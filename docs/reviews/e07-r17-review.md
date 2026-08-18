# E07-R17 — Review

Brief: `docs/rounds/e07-r17-spaced-repetition.md`  
Diff: `6cb0375c..76036eb0`  
Reviewer: Codex / gpt-5.6-terra (independent orchestrator) · Dátum: 2026-08-18  
Verdikt: APPROVED

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

`ReviewItem`, a lépcsős interval-policy és a bounded queue kizárólag domain
kód; nincs Flutter-, hálózat-, óra- vagy pluginfüggőség. A queue explicit,
szigorúan a teljes nap alatt maradó budgetet kap, a hiányzó targetet typed
replacement jelzésben megőrzi, az `unknown` pedig az eredeti intervallumot és
due date-et változatlanul hagyja.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Napi budget nem léphető túl | ✅ | `review_queue_test.dart` A1 + constructor-cells; `review_queue.dart:28-53,99-120` |
| A2 | `unknown` nem rövidíti az intervallumot | ✅ | `spaced_repetition_policy_test.dart` A2; valódi-sértés próba lent |
| A3 | Siker hosszabbít, kudarc rövidít | ✅ | policy teszt A3a/A3b; `spaced_repetition_policy.dart:266-293` |
| A4 | Részleges eredmény külön kezelt | ✅ | policy teszt A4; `spaced_repetition_policy.dart:278-289` |
| A5 | Due date determinisztikus, helyi dátum | ✅ | policy teszt A5; explicit `LocalDate` input |
| A6 | Törölt tartalom helyettesítést kér | ✅ | queue teszt A6a–A6c; `review_queue.dart:99-106` |
| A7 | Azonos cél egyszer szerepel | ✅ | queue teszt A7/A7 identity; `review_queue.dart:133-145` |
| A8 | Időzóna-váltás nem tolja el a due date-et | ✅ | policy teszt A8; nincs `DateTime`/óraolvasás |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e07-r17 --brief
docs/rounds/e07-r17-spaced-repetition.md --base
6cb0375c51638cf671ca762d1eaca45125486443 --kv` → `scope_audit=ok`, 8
megváltozott, engedélyezett út. A jelen review-artefaktum a review-protokoll
szerinti generált/ignorált út, nem scope-sértés.

## Valódi-sértés próba

Az eldobható `/tmp/review-e07-r17` klónban a
`SpacedRepetitionPolicy.evaluate()` `ReviewOutcome.unknown` ágát ideiglenesen
`_shorten(previousInterval, today)`-ra cseréltem. A célzott A2 teszt `exit 1`-
gyel bukott: várt `Duration(days: 7)`, kapott `Duration(days: 1)`
(`spaced_repetition_policy_test.dart:37`). A változtatást a gate előtt
visszaállítottam; a reviewer klón munkafája tiszta.

## Megállapítások

### F1 — NOTE — Ladder-boundok jelenleg debug assert-ek

- **Fájl:** `lib/features/practice_generator/domain/policy/spaced_repetition_policy.dart:34-49`
- **Megfigyelés:** A `ReviewIntervalLadder` sorrendi invariánsai `assert`-ek;
  release módban egy jövőbeli, hibás policy-konfiguráció nem kap ugyanilyen
  diagnosztikát.
- **Hatás:** A jelen konstans default és a kör szerződése helyes; a későbbi
  konfigurálható policy-kiadásnak runtime `ArgumentError` validációt érdemes
  adnia.
- **Státusz:** NOTE — nincs jelen körös javítás, mert a default zárt és a brief
  nem kér policy-konfigurációs inputot.

## Gate-bizonyíték ellenőrzése

| Gate | Ellenőrzött eredmény |
|---|---|
| format | ✅ reviewer-klón `round-gate` |
| analyze | ✅ `No issues found` |
| célzott tesztek | ✅ 10 + 10 teszt zöld |
| architecture / secrets / l10n | ✅ reviewer-klón `round-gate` |
| CI teljes suite + property | ⏳ Full Gate dispatch `32120920644`, még fut |
| Router CI | ⏳ a review-commit után exact-HEAD dispatch szükséges |

## Merge-döntés

Nincs nyitott BLOCKER vagy MAJOR. Merge csak az exact végső SHA-n zöld Full
Gate és Router CI után lehetséges.
