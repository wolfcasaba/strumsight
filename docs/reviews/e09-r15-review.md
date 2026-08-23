# E09-R15 — Review

Brief: docs/rounds/e09-r15-reactions-and-optimistic-consistency.md
Diff: `git diff 9a234d5dfaf2ee0eb80d49ce5ccbbe532ed46be2...7326680d151b` (minimax/e09-r15-reactions-and-optimistic-consistency)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-23
Verdikt: **APPROVED** (javító kör 1 után — `decb861d`)

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 1 (FIXED) · NOTE: 3

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Retry (duplicate set) nem növeli kétszer a countot | ✅ | `test_a1_duplicate_set_does_not_double_count` — saját /tmp klónban lefuttatva, zöld |
| A2 | Reaction-típus csere update-ként megy, nem új rekordként | ✅ | `test_a2_kind_change_updates_existing_row` — `created_at` invariáns asszerció is jelen van |
| A3 | Remove kétszer hívva sem hibázik és nem megy negatívba a count | ✅ | `test_a3_remove_twice_is_idempotent_noop` |
| A4 | Concurrent toggle mellett a viewer state végül konzisztens | ✅ | `test_a4_concurrent_toggle_consistent_viewer_state` (valódi `threading.Thread` + `Barrier`) + Flutter `reaction_controller_test.dart` A4 csoport (last-intent-wins, mindkét sorrend: siker-előbb és hiba-a-newer-után) |
| A5 | A count property-invariánsként sosem negatív | ✅ (lásd F1 — a teszt maga fragilis alternatív seedeknél, de a mért állítás igaz) | `test_a5_count_property_invariant_never_negative`, 200 op, seed 42 |
| A6 | Optimista update rollback hálózati hiba esetén (Flutter) | ✅ | `reaction_controller_test.dart` A6 csoport — rollback, commit, `clearError` mind lefedve |
| A7 | A reakció NEM bocsát ki learning reward-eventet | ✅ | `test_a7_no_learning_reward_event_emitted` (import-graph + side-effect ellenőrzés) + Flutter A7 teszt |

**§6.1 valódi-sértés próba** — SAJÁT kézzel újra ellenőrizve: a `test_a1_real_violation_probe`
elolvasva és a teljes backend pytest suite-tal együtt lefuttatva (lásd Gate-bizonyíték).
A próba mindkét védelmi réteget (a service-szintű `_existing_reaction` rövidzárat ÉS a DB
UNIQUE constraintet) eltávolítja egy SQLite tábla-rebuild dansszal, két azonos-kind
`set_reaction` hívást futtat, és `rows == 2`-t assertál — majd a `finally`-ban mindkét
réteget visszaállítja (GROUP BY-alapú dedup a restore SQL-ben, hogy a UNIQUE ne bukjon a
próba által hagyott duplikátumon). Ez pontosan a brief §6.1 szó szerinti előírása. A teszt
zöld volt a saját gate-futtatásomban.

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs**. Saját kézzel futtatva:

```
$ python3 tools/scope-audit.py --repo /tmp/review-e09-r15 \
    --brief docs/rounds/e09-r15-reactions-and-optimistic-consistency.md \
    --base 9a234d5dfaf2ee0eb80d49ce5ccbbe532ed46be2
Legacy scope audit OK (9a234d5dfaf2..7326680d151b, 8 changed path(s), 0 generated/ignored)
```

8 megváltozott útvonal = pontosan a §4 `allowed_paths` 7 ÚJ fájlja + a brief maga (§10
handoff kitöltve, §0.0 pre-flight). A `.codex-round-status` implementer-oldali
önjelentése (`scope_audit=ok`, `scope_audit_changed=8`) EGYEZIK a saját, izolált klónban
futtatott méréssel.

## §0.0 D2 scope-szűkítés betartása

Az implementer a §0.0 D2 pre-flight-revíziót (HTTP router és `PostOut`/`FeedPostItem`
wire-projekció ebben a körben NEM épül meg, a `reaction_service` szolgáltatás-réteg a
mérce) pontosan betartotta — a §10.1 handoff-szakasz explicit hivatkozza, és a diffben
nincs kísérlet a `backend/app/community/routers/*.py`, `schemas/post.py`,
`schemas/feed.py` vagy `backend/app/main.py` érintésére.

## Megállapítások

### F1 — MINOR — Az A5 property-teszt `count` változója csak az `op == 2` ágon íródik, seed-függő `UnboundLocalError`-kockázat

- **Fájl:** `backend/tests/community/test_reaction_service.py:657-666`
- **Probléma:** a 200-lépéses random-walk ciklusban `count` csak a `else: count = _count()`
  ágon kap értéket, de az `assert count >= 0` MINDEN iterációban lefut, feltétel nélkül.
  Seed 42 mellett az ELSŐ húzott `op` véletlenül `2` (mérve: `random.Random(42)` első
  `randint(0,2)` hívása 2-t ad), ezért a teszt ma zölden fut, és a CI-ban (`backend-ci.yml`
  `Backend test gate` lépés) sincs `PROPERTY_SEED` env-override — ellenőrizve, a workflow-ban
  nincs ilyen sor —, tehát a mai gate-en ez NEM piros.
- **Hatás:** más seeddel (pl. 1, 2, 12345, 999999 — mind mérve, lásd lent) az ELSŐ iteráció
  `op`-ja 0 vagy 1 lehet, és ekkor `count` MÉG SOHA nem kapott értéket ebben a
  függvényhívásban → `UnboundLocalError: local variable 'count' referenced before assignment`
  az első `assert`-nél. A teszt saját docstringje (612-616. sor) kifejezetten azt írja, hogy
  "CI can monkeypatch seed if it wants a fresh draw per run" — ez az állítás ma HAMIS: egy
  eltérő seeddel a teszt ~2/3 eséllyel azonnal elhal, mielőtt bármit mérne.
- **Mérve:**
  ```
  seed=42      → első op-sorozat: [2, 0, 0, 2, 2]   (véletlenül biztonságos)
  seed=1       → első op-sorozat: [0, 0, 1, 0, 0]   (AZONNALI UnboundLocalError)
  seed=2       → első op-sorozat: [0, 1, 2, 1, 2]   (AZONNALI UnboundLocalError)
  seed=12345   → első op-sorozat: [1, 1, 0, 0, 1]   (AZONNALI UnboundLocalError)
  seed=999999  → első op-sorozat: [0, 2, 2, 1, 1]   (AZONNALI UnboundLocalError)
  ```
- **Kötelező javítás:** `count` inicializálása a ciklus ELŐTT egy `_count()` hívással, VAGY
  az `assert` mozgatása az `else` ág alá (és minden `_set`/`_remove` után is friss
  `_count()` lekérése, hogy az invariáns ténylegesen minden mutáció UTÁN mérjen, ne csak a
  véletlenül `op==2`-t húzó lépéseknél). Az utóbbi a szigorúbb, a brief §6 A5 szó szerinti
  "a count sosem negatív" állítását minden lépés után méri, nem csak a véletlenszerűen
  kiválasztott olvasásoknál.
- **Ellenőrzés:** a javítás után futtatva `PROPERTY_SEED=1 python -m pytest
  tests/community/test_reaction_service.py::test_a5_count_property_invariant_never_negative -q`
  (és néhány további seeddel) — mindnek zöldnek kell lennie, `UnboundLocalError` nélkül.
- **Státusz:** **FIXED** (`bb112754`) — a `count = _count()` mostantól MINDEN
  iterációban feltétel nélkül fut (nem csak az `op == 2` ágon). SAJÁT kézzel
  újra ellenőrizve, izolált `/tmp/review-e09-r15-fix1` klónban, négy különböző
  `PROPERTY_SEED` értékkel (1, 2, 12345, 999999) + a dev-alapértelmezett 42-vel
  — mind az öt futás zöld, `UnboundLocalError` egyikben sem jelentkezett.

### F2 — NOTE — Elárvult kommentblokk `sys` importra hivatkozik, ami nincs a fájlban

- **Fájl:** `backend/tests/community/test_reaction_service.py:818-822`
- **Probléma:** a fájl végén egy komment azt állítja, hogy "`sys` is imported at the top of
  the file" — a `ruff --fix` commit (6cca7b85) eltávolította a nem használt `sys` importot,
  de ezt a magyarázó kommentet nem törölte.
- **Hatás:** nincs futásidejű hatás, csak megtévesztő dokumentáció egy jövőbeli olvasó
  számára.
- **Kötelező javítás:** a komment törlése (vagy pontosítása, hogy már nincs `sys` import).
- **Ellenőrzés:** vizuális — a `format`/`analyze`/`test` gate nem méri.
- **Státusz:** **FIXED** (`bb112754`) — a javító kör mellékesen törölte.

### F3 — NOTE — `reaction_bar.dart` angol placeholder stringek, ARB nélkül (önjelzett, jelenleg nincs felhasználói hatás)

- **Fájl:** `lib/features/community/presentation/widgets/reaction_bar.dart:24-28,156-169`
- **Probléma:** a chip-címkék (`Support`/`Celebrate`/`Inspiring`/`Helpful`) hardcode-olt
  angol stringek, nem `AppLocalizations`-on át jönnek — ugyanaz a hibaosztály, mint az
  E09-R08 F1 és az E09-R14 F1 MAJOR leletei.
- **Hatás:** ELTÉRŐEN a fenti két precedenstől, ez a widget ebben a körben SEHOL nincs
  bedrótozva egy képernyőbe — ellenőrizve: `grep -rln "ReactionBar\b" lib/` a saját fájlján
  kívül NULLA találatot ad. Élő magyar felhasználó ma NEM látja ezeket a stringeket. Az
  implementer ezt a §0.0 D2 allowed_paths-korlát következményeként explicit dokumentálta a
  fájl doc-commentjében (24-28. sor) — nem hallgatólagos mulasztás.
- **Kötelező javítás:** NINCS ebben a körben (az ARB fájlok nincsenek az `allowed_paths`-on,
  bővítés itt scope-tágítás lenne). A KÖVETKEZŐ kör, amelyik ezt a widgetet egy képernyőbe
  drótozza, KÖTELEZŐEN vigye be az `AppLocalizations` hívásokat is ugyanabban a
  commit-sorozatban — ez pontosan az E09-R14 F1 fix mintája.
- **Ellenőrzés:** a jövőbeli bekötő kör briefjébe kerüljön be explicit acceptance-cellaként.
- **Státusz:** NOTE — nem blokkol, nem kötelező ebben a körben javítani.

### F4 — NOTE — Pre-existing flaky teszt a teljes backend suite-ban, NEM E09-R15 diffje okozza

- **Fájl:** `backend/tests/community/test_follow_service.py::test_swap_unique_constraint_breaks_a2`
  (Kör 7 / E09-R07, `threading`-alapú valódi-sértés próba a follow-service A2
  cellájára — a mi `test_a4_concurrent_toggle_consistent_viewer_state`
  mintánkkal rokon szerkezet, saját race-ablakkal).
- **Probléma:** a javító kör 1 UTÁNI re-verifikáció során (izolált
  `/tmp/review-e09-r15-fix1` klón, `python -m pytest -q` a `backend/`
  gyökérből) EGY futtatás ezt a tesztet PIROSRA hozta. Izoláltan futtatva
  (`pytest test_follow_service.py::test_swap_unique_constraint_breaks_a2`)
  és két KÖVETKEZŐ teljes-suite futtatásnál is zöld volt — a fájl NINCS az
  E09-R15 `allowed_paths`-án, a diffünk egyetlen sorát sem érinti, és a
  jelenség egy 4-ből 1 arányú, nem-determinisztikus race a MEGLÉVŐ,
  körön kívüli tesztben.
- **Hatás:** ha a merge előtti exact-SHA CI-dispatch pont ERRE a
  konkrét race-re fut rá, a `full-gate.yml`/`build-apk.yml` futás pirosra
  válthat egy olyan okból, ami NEM az E09-R15 diffjének hibája — ez H5/H7
  szempontból megkülönböztetendő egy VALÓDI reakció-hibától. Ha ez
  bekövetkezik, az orchesztrátor a piros run logját ELLENŐRZI (melyik teszt
  bukott), és ha kizárólag ez a Kör 7 teszt az, újra-dispatch indokolt
  (nem H5 — a szabály szándéka a KÖR SAJÁT hibájára vonatkozik, nem egy
  bizonyítottan körön kívüli, pre-existing flake-re).
- **Kötelező javítás:** NINCS ebben a körben — a fájl tilos zóna (nincs az
  `allowed_paths`-on), és a jelenség E09-R15-től FÜGGETLEN.
  `docs/LESSONS.md`-be egy külön, E09-R15-től független lecke kerüljön
  (a záró rituálékban), hogy egy jövőbeli Kör 7-hez nyúló forduló mérje meg
  és stabilizálja a race-t.
- **Ellenőrzés:** a jövőbeli follow-service körnek szükséges saját mérése.
- **Státusz:** NOTE — dokumentálva, nem blokkol.

## Gate-bizonyíték ellenőrzése

Mind a kilenc gate-lépés SAJÁT kézzel, izolált `/tmp/review-e09-r15` klónban (nem az
implementer munkapéldányában) újrafuttatva:

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ |
| analyze | zöld | ✅ |
| test `test/features/community/application/reaction_controller_test.dart` | zöld (8/8) | ✅ |
| architecture | zöld (12 allowlistelt deviáció, változatlan) | ✅ |
| secrets | zöld (3430 fájl, 0 lelet) | ✅ |
| l10n | zöld (parity OK) | ✅ |
| backend ruff format | zöld (85 fájl) | ✅ |
| backend ruff check | zöld | ✅ |
| backend pytest (TELJES suite, nem csak a reaction tesztek) | zöld | ✅ |

CI (teljes suite + property + APK): ezt a review NEM futtatja — az orchestrátor a
merge-előkészítés lépéseként dispatch-eli a `tools/round-ci-plan.py` által meghatározott
workflow-t, exact-SHA-n, a javító kör UTÁN.

## Javító kör 1 — zárás

`bb112754` + `decb861d` (a §10.9 handoff-kiegészítés) a `minimax/e09-r15-…` branchen.
F1 és F2 zárva, SAJÁT kézzel újraellenőrizve (lásd fent). A javító kör UTÁNI teljes
gate SAJÁT kézzel, izolált `/tmp/review-e09-r15-fix1` klónban újrafuttatva — mind a
kilenc lépés zöld (a backend pytest a TELJES suite-ot jelenti, a fenti F4 note szerinti
pre-existing flake kivételével, amit két KÖVETKEZŐ újrafuttatás megcáfolt).

## Merge-döntés

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge megengedett.
0 BLOCKER/MAJOR, a nyitott F1 MINOR ZÁRVA. A kör **APPROVED**, mehet a CI-dispatch +
exact-SHA merge útra.
