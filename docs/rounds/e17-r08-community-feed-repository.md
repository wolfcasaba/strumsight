# E17-R08 — `CommunityFeedRepository` impl + feed-cache production override

- **Státusz:** PREPARED (előre megírva 2026-09-05, kód olvasva: `main @ b17e08ef`) — **`hold`: Az `E17-R07` HTTP-alapján áll**
- **Típus:** Chapter 17 (Teljes bekötés), Kör 8
- **Kör-azonosító:** `E17-R08`
- **Branch:** `<motor>/e17-r08-community-feed-repository`
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0527` — a szám ELŐZETES; a foglaló a kör indulásakor adja a véglegeset (mérve: nyolc egymást követő körön át a queue ADR-oszlopa elavult volt).
- **Fejezet-terv:** [`docs/plans/chapter-17-full-wiring.md`](../plans/chapter-17-full-wiring.md)

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "`communityfeedrepository` impl + feed-cache production override"` — a kör pre-flightjának KÖTELEZŐ lefuttatnia és a találatokat a §2-be beépítenie; a brief előre megírt állapotában a §2 a `main @ b17e08ef` mérésein áll.

## 0.0 MIÉRT `hold`

Az `E17-R07` HTTP-alapján áll. **Mi oldja fel:** az `E17-R07` lezárása.

```ai-router
schema_version = 1
risk = "high"
# risk = "high" indoklás: Hálózati olvasás + per-felhasználó gyorsítótár felhasználói tartalom körül — `security-reviewer` KÖTELEZŐ.
allowed_paths = [
  "lib/features/community/data/repositories/feed_repository_impl.dart",
  "lib/features/community/application/controllers/feed_controller.dart",
  "lib/features/community/providers/community_providers.dart",
  "test/features/community/data/feed_repository_impl_test.dart",
  "docs/rounds/e17-r08-community-feed-repository.md",
]
native_gate = false
gate_tests = [
  "test/features/community/",
  "test/privacy/",
]
```

## 0. Kör-jelzés és STOP-protokoll

Scope-ütközés esetén a kimenet a brief-REVÍZIÓ, nem a scope önkényes tágítása: állítsd meg a kört (`stopped`), és írd le, melyik §-t kell módosítani.

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**Kockázat = high, indoklás:** a kör diffje hálózatot, hitelesítést, adatvédelmet vagy felhasználói tartalmat érint, ezért a `security-reviewer` review-ja KÖTELEZŐ (AGENTS.md §15, `.ai/router.toml` high_risk_path_fragments).

## 1. Cél

A `FollowingFeedScreen` valós adatot kap: a `communityFeedRepositoryProvider` és a `feedCacheProvider` production override-ot kap.

## 2. Jelenlegi állapot — mért tények (`main @ b17e08ef`)

- `feed_controller.dart:213` és `:225` — a `feedCacheProvider` és a `communityFeedRepositoryProvider` `throw UnimplementedError`-ral várja a production wiringet; a doc-comment KIMONDJA, hogy a teszt override-ol, a production wiring egy későbbi kör.
- A `FeedCache` (`data/feed_cache.dart`) és a `CommunityFeedRepository` interfész LÉTEZIK; az impl nem.
- A `FollowingFeedScreen` `reachable: false`.
- A cache doc-commentje A2 néven **fiók-izolációt** ír elő: a cache a bejelentkezett felhasználó partíciója ellen nyílik.

## 3. Scope

**Benne van:** A `CommunityFeedRepository` HTTP-implementációja · a `feedCacheProvider` production override fiók-izolált partícióval · lapozás és frissítés · offline olvasás a gyorsítótárból, explicit állapotjelzéssel.

**NINCS benne (tilos):**

- A `FollowingFeedScreen` route-ja — az az R12.
- Poszt/komment írás — az az R09.
- A `FeedController` állapotgépének módosítása.

## 4. Engedélyezett fájlok

(lásd az `ai-router` blokk teljes listáját)

## 5. Kötött architekturális döntések (ADR 0527)

### 5.1 A feed-cache partíciója a bejelentkezett felhasználó id-je — kijelentkezéskor NEM olvasható tovább

A `feed_controller.dart` A2 doc-commentje ezt a fiók-izolációt írja elő. Közös partíció egy másik fiók tartalmát mutatná meg.

### 5.2 A `FeedController` állapotgépe bájtra érintetlen marad

A kör az override-seameket tölti ki. Az állapotgép módosítása a meglévő tesztjeit tenné hamissá, és a scope-ot adatrétegről prezentációra tolná.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A `communityFeedRepositoryProvider` és a `feedCacheProvider` production úton NEM dob `UnimplementedError`-t | teszt a szállított kompozíción |
| A2 | Fiókváltás után az előző fiók gyorsítótárazott feedje NEM olvasható | teszt két fiók-partícióval |
| A3 | Offline olvasáskor a gyorsítótárból jön tartalom, explicit offline állapotjelzéssel — nem néma üres lista | teszt |
| A4 | A lapozás a szerver kurzorát követi, nem eltolás-alapú újrakérést | teszt |
| A5 | A `FeedController` fájlja a diffben csak a provider-definíciókat érinti | `git diff` |

### 6.1 Falszifikációs próba

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** Nyisd a cache-t közös (nem fiók-izolált) partícióval, futtasd a gate-et → az A2 cellának PIROSNAK kell lennie → állítsd vissza.

Minden fenti acceptance-cella MÉRT állítás: a §7 gate-parancsa futtatja őket, és a falszifikációs próba bizonyítja, hogy a cellák tényleg pirosra váltanak a hibás implementáción.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/ test/privacy/
```

A gate a `format` → `analyze` → `test <minden útvonal külön>` → `architecture` lépéseket KÜLÖN processzként futtatja (a box mért OOM-csapdája miatt a `flutter analyze && flutter test` lánc tilos).

## 8. Implementációs sorrend

1. A §2 mért tényeinek ÚJRAMÉRÉSE a kör indulásakor (a brief alapja elmozdulhatott).
2. A §5 döntéseinek rögzítése az ADR-ben.
3. Az implementáció a §4 engedélyezett fájljain belül.
4. A §6 acceptance-cellák tesztjei.
5. A §6.1 valódi-sértés próba lefuttatása és a §10-be dokumentálása.
6. A §7 gate futtatása csonkítatlan kimenettel.

## 9. Kockázatok

- **A fiók-szivárgás.** Közös cache-partíció idegen fiók tartalmát mutatná (5.1, A2).
- **A néma üres feed.** Offline állapot sikeres üres válaszként (A3).
- **A scope-csúszás.** Az állapotgép átírása a kör adatréteg-jellegét oldaná fel (5.2, A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
