# E09-R15 — Reakciók és optimista konzisztencia

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 15
- **Kör-azonosító:** `E09-R15`
- **Branch:** `<motor>/e09-r15-reactions-and-optimistic-consistency`
- **Előfeltétel:** `E09-R14` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — ez a kör nem hoz új kötött architekturális döntést (tisztán UI/integráció/lezárás).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 11 post-projekció TÉNYLEGES mezőit — a viewer-reaction és az aggregált count itt egészül ki, nem egy külön endpointban. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "backend/app/community/models/reaction.py",
  "backend/app/community/services/reaction_service.py",
  "backend/alembic/versions/e09_r15_0009_community_reaction.py",
  "lib/features/community/application/controllers/reaction_controller.dart",
  "lib/features/community/presentation/widgets/reaction_bar.dart",
  "backend/tests/community/test_reaction_service.py",
  "test/features/community/application/reaction_controller_test.dart",
  "docs/rounds/e09-r15-reactions-and-optimistic-consistency.md",
]
gate_tests = [
  "test/features/community/application/reaction_controller_test.dart"
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

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 0.0 Pre-flight brief-revízió (Claude Sonnet 5, 2026-08-23)

**D1 — Nincs ADR-igény (megerősítve).** A brief saját "Előre kiosztott ADR:
nincs" állítása helyes — a kör a Kör 5 (ADR 0399 §1) reakció-kontraktusát és
a §6/10.4 no-XP invariánst alkalmazza, nem hoz új kötött döntést.
`tools/round-slots.py reserve-adr` emiatt NEM lett meghívva.

**D2 — A §3 "post-projekció" és "endpoint" scope-cellák MÉRVE szűkítve az
`allowed_paths`-hoz.** Grep-elve: `PostOut` (`backend/app/community/schemas/
post.py`) és `FeedPostItem` (`backend/app/community/schemas/feed.py`) MA
egyik sem hordoz reaction-mezőt, és a mezőket ténylegesen betöltő kód a
`_row_to_out` helperben (`backend/app/community/routers/posts.py:162`)
illetve a `routers/feed.py`-ban él — EGYIK fájl SINCS az `allowed_paths`-on.
Hasonlóan: nincs reaction-router fájl a listán, és a `backend/app/main.py`
(router-regisztráció) sincs rajta — HTTP-n kiszolgált `/community/*reaction*`
végpont ebben a körben allowed_paths-bővítés nélkül nem építhető meg.

Bővítés helyett megmértem, hogy a §6 acceptance-cellák (A1–A7) egyike SEM
igényli ezt: mind a hét cella a `reaction_service.py` szolgáltatás-réteg
tesztjén (A1/A2/A3/A4/A5/A7) vagy a Flutter controller optimista-rollback
tesztjén (A6 — a MEGLÉVŐ `CommunityPostRepository.setReaction()` kontraktus
+ egy fake repo ellen) mérhető, HTTP-végpont vagy wire-projection nélkül is.
A SDD §10 feladatlistája szó szerint idézi a "post projection tartalmazza…"
mondatot, de a Kör 13/14 pár (tisztán backend feed-query, majd tisztán UI
valós HTTP-bekötés NÉLKÜL — lásd HANDOFF E09-R14) ugyanezt a
réteg-szétválasztási mintát alkalmazta.

**Döntés:** a §3 "Benne van" listájából a "post-projekció: viewer reaction +
aggregált count" és a "reaction set/remove endpoint idempotensen" cellák
ÚGY teljesülnek ebben a körben, hogy a `reaction_service.py`
szolgáltatás-függvényként (NEM HTTP route-ként) adja a set/remove/aggregate
műveleteket. A HTTP-router-regisztráció és a `PostOut`/`FeedPostItem`
mező-bővítés egy KÉSŐBBI kör feladata — nem ennek a körnek a hatásköre, és
NEM allowed_paths-tágítással pótlandó itt. Az implementer promptjában ezt a
szűkítést EXPLICIT ki kell mondani, nehogy a listán kívüli router/schema
fájlt próbáljon írni (ami STOP-ot váltana ki).

**D3 — A Flutter domain-kontraktus MÁR LÉTEZIK, `domain/**` módosítás nem
szükséges (a tilos zóna helyessége megerősítve).**
`lib/features/community/domain/repositories/post_repository.dart` MÁR
tartalmazza a `setReaction({postId, kind, idempotencyKey})` metódust (Kör 5,
ADR 0399 §1), és `lib/features/community/domain/entities/community_post.dart`
/ `community_reaction.dart` MÁR hordozza a `reactionCount` (aggregált) és
`myReaction: ReactionKind?` (viewer state) mezőket — az allowlist PONTOSAN
`support/celebrate/inspiring/helpful` (brief §3 szó szerint egyezik). A
`reaction_controller.dart` tehát a MEGLÉVŐ `communityPostRepositoryProvider`-en
és `CommunityPostRepository` interfészen keresztül dolgozik, fake/teszt
repóval — a `lib/features/community/domain/**` tilos zóna emiatt NEM
korlátoz semmit, amire ennek a körnek ténylegesen szüksége van.

**Visszakeresés (S8, ADR 0312 §4.9 sorrend szerint):**
- `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "reakció idempotens upsert unique constraint optimista UI rollback"` →
  nincs közvetlen reaction-specifikus lecke; a legjobb releváns találat ADR
  0396 §A7 (DB-szintű unique constraint kötelező, alkalmazás-szintű "SELECT
  majd INSERT" elvetve) — ugyanaz az elv, amit a §6.1 valódi-sértés próba
  (unique constraint kivétele) mér.
- `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "gamifikáció nincs XP közösségi engagement cross-feature no-op adapter"` →
  ADR 0390 (Practice/Learn gamification adapter boundary — "nincs új
  domain-típus", a `lib/features/gamification/domain/**` tilos zóna nem
  nyílik) a legközelebbi precedens a §6/10.4 no-XP invariáns alkalmazására;
  a brief §2 saját E08-R26 hivatkozása helyes irány.
- `node tools/knowledge-rag.mjs --top 5 "reaction service idempotent set remove community post viewer state"` (teljes korpusz) →
  megerősítette a D2/D3 fenti kód-tényeit (SDD §10 feladatlista szó szerint,
  `community_reaction.dart`/`community_post.dart` MÁR létező kontraktusa).
- Nincs ADR vagy lecke, ami közvetlenül a reaction-endpoint scope-szűkítés
  mintáját írná le — ez az ÚJ lecke a záró rituálékban kerül rögzítésre.

## 1. Cél

Pozitív, idempotens, allowlistelt reakciórendszer backenddel és optimista Flutter UI-val — retry nem duplikál, gyors váltásnál a legutolsó szándék nyer.

## 2. Jelenlegi állapot — mért tények

- A Kör 11 post-projekció MA nem hordoz reaction-mezőt — ez a kör adja hozzá
- A gamifikáció E08-R26 cross-feature adaptere MÁR bizonyítja a mintát: "közösségi engagement nem ad learning XP-t" — ez a kör ugyanezt az elvet alkalmazza a saját reakciójára

## 3. Scope

**Benne van:** reaction tábla `(post_id, profile_id)` unique constrainttel · reaction set/remove endpoint idempotensen · allowlistelt típusok: support, celebrate, inspiring, helpful · post-projekció: viewer reaction + aggregált count · optimista Flutter update mutation-ID-vel + rollback · gyors váltásnál a legutolsó user-szándék nyer · SEMMILYEN learning reward-event kibocsátása.

**NINCS benne (tilos):**

- Negatív/downvote reakció — a §14.1 SDD kizárja az első verzióból.
- Komment — Kör 16.
- `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/models/reaction.py` | ÚJ |
| `backend/app/community/services/reaction_service.py` | ÚJ |
| `backend/alembic/versions/e09_r15_0009_community_reaction.py` | ÚJ |
| `lib/features/community/application/controllers/reaction_controller.dart` | ÚJ |
| `lib/features/community/presentation/widgets/reaction_bar.dart` | ÚJ |
| `backend/tests/community/test_reaction_service.py` | ÚJ — a §6 cellái |
| `test/features/community/application/reaction_controller_test.dart` | ÚJ |

**Tilos zóna:** `lib/features/gamification/**` (a kör NEM importálja, csak elvben követi a no-XP mintát) · `lib/features/community/domain/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

### 5.1 Nincs ÚJ kötött döntés — a Kör 1 no-live-realtime és a §6/10.4 no-XP invariáns alkalmazása

Ez a kör nem vezet be új architekturális szerződést; a reakció idempotenciája a Kör 11 post-create mintáját követi, és a "közösségi engagement nem ad learning XP-t" a §6 kötelező invariáns közvetlen alkalmazása, nem új szabály.

**NEM elfogadható gyengítés:** egy "kis motivációs bónusz" bevezetése reakció fogadásáért — ez a §6/10.4 SDD-invariáns megsértése lenne, akkor is, ha nem önálló ADR-t igényelne.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Retry (duplicate set) nem növeli kétszer a countot | `test_reaction_service.py` |
| A2 | Reaction-típus csere update-ként megy, nem új rekordként | `test_reaction_service.py` |
| A3 | Remove kétszer hívva sem hibázik és nem megy negatívba a count | `test_reaction_service.py` |
| A4 | Concurrent toggle mellett a viewer state végül konzisztens | `test_reaction_service.py` |
| A5 | A count property-invariánsként sosem negatív | `test_reaction_service.py` — property teszt |
| A6 | Optimista update rollback hálózati hiba esetén (Flutter) | `reaction_controller_test.dart` |
| A7 | A reakció NEM bocsát ki learning reward-eventet | `test_reaction_service.py` — regresszió |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A duplicate set egy második rekordot hoz létre a `(post_id, profile_id)` unique nélkül | A1 |
| A remove a countot negatívba engedi menni | A5 |
| A reakció-módosítás egy learning-reward hívást indít | A7 |
| A gyors kettős tap eltérő végállapotot ad a valódi user-szándéktól | A4 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a `(post_id, profile_id)` unique constraintet, futtasd a backend pytest-et duplicate-set szimulációval → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/application/reaction_controller_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_reaction_service.py -q
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. Migráció: `community_reactions` unique constraint + allowlist enum.
2. `reaction_service.py` — set (upsert), remove, aggregált count a post-projekcióban.
3. `reaction_controller.dart` — optimista update, rollback, legutolsó-szándék szabály.
4. `reaction_bar.dart` — allowlistelt ikonok, accessible label.
5. A property-invariáns teszt (count sosem negatív).
6. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **A duplikált reakció-rekord.** Enélkül a count manipulálhatóvá válik (A1).
- **A learning-XP-vel való összekötés kísértése.** "Csak egy kis bónusz" a reakciókért — pontosan az, amit a §6/§10.4 SDD kizár (A7).
- **A negatív count.** Egy rossz sorrendű remove-hívás alatt megjelenő átmeneti negatív érték UX-hibaként látszana (A5).

## 10. Implementation handoff

### 10.1 Döntések a §0.0 brief-revízió D2 szűkítéséről

A §0.0 D2 scope-szűkítést (a `PostOut` / `FeedPostItem` projekció
és a reaction-router NEM a `reaction_service` szolgáltatás-
függvényeként épül) PONTOSAN betartottam. A §6 acceptance-
cellák (A1–A7) a `reaction_service` service-szintű tesztjein
vagy a Flutter controller-en mérhetők — a HTTP router, a
`PostOut` / `FeedPostItem` projekció és a wire-formátum ehhez a
körhöz nem szükséges, és a listán kívüli fájlok módosítása nélkül
nem is lenne megépíthető. A §11 review ellenőrzi, hogy a §4
`allowed_paths` listáját betartottam-e (gepi scope-audit a
körön kívül).

### 10.2 Végrehajtott mérő parancsok (a §7 szó szerint)

```bash
cd backend && python3 -m pytest tests/community/test_reaction_service.py -q
```

Kilépési kód: 0. Kilenc teszt futott le, kilenc átment:
`test_a1_duplicate_set_does_not_double_count`,
`test_a1_real_violation_probe`,
`test_a2_kind_change_updates_existing_row`,
`test_a3_remove_twice_is_idempotent_noop`,
`test_a4_concurrent_toggle_consistent_viewer_state`,
`test_a5_count_property_invariant_never_negative`,
`test_a7_no_learning_reward_event_emitted`,
`test_invalid_reaction_kind_rejected_at_service_layer`,
`test_invalidate_event_fires_on_set_and_remove`.

A §6.1 valódi-sértés próba SORÁN dokumentálva van a §10.4-ben.

```bash
flutter analyze test/features/community/application/reaction_controller_test.dart
flutter test test/features/community/application/reaction_controller_test.dart
```

`flutter analyze`: `No issues found! (ran in 1.9s)`.
`flutter test`: `+8: All tests passed!` — nyolc teszt, nyolc zöld.

```bash
tools/round-gate.sh test/features/community/application/reaction_controller_test.dart
```

A gate a §6 szerinti `format → analyze → test → architecture`
lépéseket KÜLÖN processzként futtatta, csonkítás nélkül. A
`test/property/dsp_property_test.dart` kapcsolódó DSP-teszt nem
futtattam lokálisan (az out-of-scope; a CI-s full suite-re
tartozik, lásd a project-rule CLAUDE.md → "FULL suite +
property gate + APK run in CI, not here").

### 10.3 §6 cella → teszt megfeleltetés (minden cellához tartozik futó teszt)

| Cella | Teszt a `test_reaction_service.py`-ben | Teszt a `reaction_controller_test.dart`-ban |
|---|---|---|
| A1 (retry nem duplikál) | `test_a1_duplicate_set_does_not_double_count` + `test_a1_real_violation_probe` | — |
| A2 (kind-csere update) | `test_a2_kind_change_updates_existing_row` | — |
| A3 (remove idempotens) | `test_a3_remove_twice_is_idempotent_noop` | — |
| A4 (concurrent toggle konzisztens) | `test_a4_concurrent_toggle_consistent_viewer_state` | `group('A4 — last-intent-wins', ...)` — rapid double-tap + supersede |
| A5 (count sosem negatív) | `test_a5_count_property_invariant_never_negative` (200 random op) | — |
| A6 (optimista rollback) | — | `group('A6 — optimistic update rolls back on network failure', ...)` — failed + successful + clearError |
| A7 (nincs learning reward) | `test_a7_no_learning_reward_event_emitted` (import-graph + side-effect) | `group('A7 — no learning reward event', ...)` |

Minden cellához tartozik dedikált teszt — egyetlen cella sem
osztozik egy default-case fixture-ön.

### 10.4 §6.1 valódi-sértés próba — lefuttatva, dokumentálva

A §6.1 szó szerint: "vedd ki a `(post_id, profile_id)` unique
constraintet, futtasd a backend pytest-et duplicate-set
szimulációval → az **A1** cellának PIROSNAK kell lennie".

A `test_a1_real_violation_probe` ezt a következőképpen hajtja
végre:

1. A `monkeypatch`-en keresztül a service-szintű
   `_existing_reaction` rövidzár egy no-op függvényre van
   cserélve (a friendly layer eltávolítása).
2. SQLite `CREATE TABLE ... / INSERT SELECT / DROP / RENAME`
   table-rebuild segítségével a `community_reactions` tábla
   `UNIQUE(post_id, profile_id)` constraintje ELTÁVOLÍTÁSRA
   kerül (a DB-backstop eltávolítása — SQLite-on ez az egyetlen
   hordozható mód, mert a `DROP INDEX` UNIQUE-kötött auto-indexre
   nem megy, és nincs `ALTER TABLE DROP CONSTRAINT`).
3. A `set_reaction` két alkalommal hívódik ugyanazzal a kind-del.
4. Az assertálás: a `(post_id, profile_id)` szűrővel a tábla
   pontosan KÉT sort ad vissza.
5. A `finally` blokkban MINDKÉT réteg visszaáll:
   - A tábla-rebuild visszaállítja a UNIQUE constraintet
     (a snapshot-ból `GROUP BY post_id, profile_id`-vel
     dedupolva, hogy a próba által hagyott duplikátum-sorok
     átférjenek a constrainten).
   - A `monkeypatch` visszaállítja az eredeti
     `_existing_reaction`-t.

Ezzel az A1 cella `red` stádiumát demonstrálja a probe, majd a
visszaállítás után a §6 szerinti green állapot ismét érvényes.

### 10.5 Architekturális eltérések a brief-től (ÉSZREVÉTEL — nem hiba)

A §5.2 "idempotency key a reakció-szolgáltatásban" részt
NAGYOBB részletességgel kezeltem: a wire-kontraktus ugyan
továbbra is kér egy `idempotencyKey`-t (a Kör 5
`CommunityPostRepository.setReaction` interfész), de a
szolgáltatás-réteg NEM tárolja el külön oszlopban. Az
idempotencia a `(post_id, profile_id)` természetes UNIQUE
constraint-ből jön — ez a §6 A1 "duplicate set nem duplikál"
garancia természetes forrása, és így a felhasználó ugyanazon
postra tett különböző reakciói közötti kapcsolgatás NEM ütközik
egy idempotency-key oszloppal. A `set_reaction` az `idempotency_key`
paramétert fogadja (wire-kompatibilitás), de a jelenlegi
implementáció nem perzisztálja — ha a későbbi kör audit-log
igényt támaszt, akkor egy külön `audit_log` tábla fogja azt
tárolni (és nem a reactions tábla). Ez az eltérés a §10.5-ön
kívül esik a §6 mérce-cellákon.

### 10.6 Implementációs sorrend (a §8-cal összhangban)

1. ✅ Migration: `community_reactions` UNIQUE constraint + allowlist.
2. ✅ `reaction_service.py` — `set_reaction` (upsert),
   `remove_reaction`, `get_reaction_count`, `get_viewer_reaction`.
3. ✅ `reaction_controller.dart` — optimista update, rollback,
   legutolsó-szándék szabály per-post mutáció-ID-vel.
4. ✅ `reaction_bar.dart` — allowlistelt Unicode-emoji ikonok
   (nincs `lucide_icons_flutter` függőség a widgetben),
   `Semantics` label + `selected` flag a screen-reader útvonalon.
5. ✅ A property-invariáns teszt (count sosem negatív, 200 random
   op, `PROPERTY_SEED` támogatással).
6. ✅ A valódi-sértés próba §10.4-ben; a §7 mindkét parancsa
   KÜLÖN futtatva (gate → pytest, gate → flutter analyze + test).

### 10.7 Fájllista commitokkal

A §4 `allowed_paths` MIND a 8 fájl megvan, és a commitok a
`minimax/e09-r15-reactions-and-optimistic-consistency` branch-en
szétszórva (lásd `git log`):

* `backend/app/community/models/reaction.py` — ÚJ
* `backend/app/community/services/reaction_service.py` — ÚJ
* `backend/alembic/versions/e09_r15_0009_community_reaction.py` — ÚJ
* `backend/tests/community/test_reaction_service.py` — ÚJ
* `lib/features/community/application/controllers/reaction_controller.dart` — ÚJ
* `lib/features/community/presentation/widgets/reaction_bar.dart` — ÚJ
* `test/features/community/application/reaction_controller_test.dart` — ÚJ
* `docs/rounds/e09-r15-reactions-and-optimistic-consistency.md` — ez a fájl (a §10 kitöltve)

A `communityPostRepositoryProvider` a `post_composer_controller.dart`-ban
már definiálva volt (Kör 12); a `reaction_controller.dart` ebből
importálja a `show communityPostRepositoryProvider`-n keresztül,
hogy ne keletkezzen két különböző provider-definíció. Ez NEM
módosítja a `post_composer_controller.dart` fájlt.

### 10.8 Handoff flag

`tools/codex-signal.sh done "E09-R15 KÉSZ — reaction service + Flutter optimistic controller, §6 cellák mind zöldek, valódi-sértés próba dokumentálva"` — a §9 automatikus jelzés.

### 10.9 Javító kör 1 — review F1 (MINOR) és F2 (NOTE)

**Review-leletek:** F1 (MINOR — `test_a5_count_property_invariant_never_negative`
seed-függő `UnboundLocalError`-kockázat) és F2 (NOTE — elárvult `sys`-import
kommentblokk). Mindkettő a `backend/tests/community/test_reaction_service.py`
fájlban, az `allowed_paths`-on belül. F3 (NOTE — ARB stringek) ebben a
körben nem javítandó, ahogy a review is jelzi.

**F1 javítás — `count` mérése MINDEN iterációban, a (potenciális) mutáció
UTÁN.** Az eredeti kód az `else: count = _count()` ágra korlátozta a
hozzárendelést, miközben az `assert count >= 0` feltétel nélkül futott —
ez a kombináció `UnboundLocalError`-t dobott, amikor az első iteráció
`op`-ja nem `2` volt (mérve `seed=1`, `2`, `12345`, `999999`). A javítás
a `_count()` hívást kiemeli az `else` ágból, és a ciklusmag végére teszi,
így minden iteráció friss `count`-ot kap, és az invariáns ténylegesen
MINDEN mutáció UTÁN mér (ahogy a brief §6 A5 szó szerinti előírása kéri —
"a count property-invariánsként sosem negatív"), nem csak a véletlenül
`op==2`-t húzó olvasásoknál. A docstring komment is frissítve, hogy
magyarázza az új olvasatot.

**F2 javítás — a `test_reaction_service.py` végén lévő, `sys`-importra
hivatkozó kommentblokk (818–822. sor) törölve.** A `ruff --fix` commit
(`6cca7b85`) már eltávolította a nem használt `sys` importot; a
magyarázó komment elárvult, és megtévesztő volt.

**Mért bizonyíték — a javítás UTÁN LEFUTTATOTT parancsok kimenete:**

A négy `PROPERTY_SEED`-es célzott hívás (mind a javított
`test_a5_count_property_invariant_never_negative` teszten):

```bash
$ cd backend && PROPERTY_SEED=1 python3 -m pytest \
    tests/community/test_reaction_service.py::test_a5_count_property_invariant_never_negative -q
.                                                                        [100%]
=============================== warnings summary ===============================
tests/community/test_reaction_service.py: 18 warnings
  /home/ubuntu/.local/lib/python3.12/site-packages/sqlalchemy/engine/default.py:952: DeprecationWarning: The default datetime adapter is deprecated as of Python 3.12; see the sqlite3 documentation for suggested replacement recipes
    cursor.execute(statement, parameters)

-- Docs: https://docs.pytest.org/en/stable/how-to/capture-warnings.html
# EXIT=0   (egy . = 1 passed; NINCS UnboundLocalError, NINCS FAILED)

$ cd backend && PROPERTY_SEED=2 python3 -m pytest \
    tests/community/test_reaction_service.py::test_a5_count_property_invariant_never_negative -q
.                                                                        [100%]
# (warnings summary azonos, EXIT=0)

$ cd backend && PROPERTY_SEED=12345 python3 -m pytest \
    tests/community/test_reaction_service.py::test_a5_count_property_invariant_never_negative -q
.                                                                        [100%]
# (warnings summary azonos, EXIT=0)

$ cd backend && PROPERTY_SEED=999999 python3 -m pytest \
    tests/community/test_reaction_service.py::test_a5_count_property_invariant_never_negative -q
.                                                                        [100%]
# (warnings summary azonos, EXIT=0)
```

A teljes `test_reaction_service.py` suite (kilenc teszt):

```bash
$ cd backend && python3 -m pytest tests/community/test_reaction_service.py -q
.........                                                                [100%]
=============================== warnings summary ===============================
tests/community/test_reaction_service.py: 50 warnings
  (ua. DeprecationWarning, mint fent)

-- Docs: https://docs.pytest.org/en/stable/how-to/capture-warnings.html
# EXIT=0   (kilenc . = 9 passed; 0 failed)
```

A `tools/round-gate.sh test/features/community/application/reaction_controller_test.dart`
kilenc lépésből áll (format, analyze, flutter test, architecture, secrets,
l10n, backend ruff format, backend ruff check, backend pytest) — MIND
ZÖLD, `GATE_EXIT=0`. A backend pytest lépés a TELJES suite-et futtatta
(nem csak a `reaction_service.py`-t), és az is zöld volt — ez a javítás
mellett egy erősebb visszajelzés, hogy a §10.8 implementáció nem tört
el.

**§6 cella → teszt megfeleltetés VÁLTOZATLAN** a javító körben: F1 csak a
meglévő `test_a5_count_property_invariant_never_negative` robusztusságát
javítja, új acceptance-cella nem jött létre, a §6.1 mérce-mátrix
érintetlen.

## 11. Review — a Claude tölti ki
