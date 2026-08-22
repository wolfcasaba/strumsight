# E09-R09 — Profilkeresés és biztonságos discovery

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 9
- **Kör-azonosító:** `E09-R09`
- **Branch:** `<motor>/e09-r09-profile-search-and-discovery`
- **Előfeltétel:** `E09-R08` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — ez a kör nem hoz új kötött architekturális döntést (tisztán UI/integráció/lezárás).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 8 `query_filters.py` TÉNYLEGES aláírását — a keresés ugyanazt a közös block/mute szűrőt hívja, nem egy párhuzamos szűrést vezet be. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/repositories/profile_search_repository.py",
  "backend/app/community/routers/search.py",
  "lib/features/community/presentation/screens/community_search_screen.dart",
  "lib/features/community/data/local/recent_search_store.dart",
  "backend/tests/community/test_profile_search.py",
  "test/features/community/presentation/community_search_test.dart",
  "docs/rounds/e09-r09-profile-search-and-discovery.md",
]
gate_tests = [
  "test/features/community/presentation/community_search_test.dart"
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

## 1. Cél

Handle és érdeklődés alapján kereshető, privacy-t tiszteletben tartó profilfelfedezés — e-mail/telefonszám/hely alapú keresés NÉLKÜL.

## 2. Jelenlegi állapot — mért tények

- A Kör 3 handle-policy és a Kör 8 közös block-szűrő MA készen áll — ez a kör az ELSŐ, ami a kettőt egy felhasználó-néző keresési útvonalon kombinálja

## 3. Scope

**Benne van:** exact handle lookup + prefix keresés dokumentált minimum query hosszal · PostgreSQL keresési index (nem teljes táblaszkennelés) · private/non-discoverable és blocked profilok szűrése · rate limit + abuse monitoring a keresésre · Flutter search képernyő debounce-szal, törölhető lokális recent-search listával · Explore-javaslat CSAK explicit interest tagekből, feature flag mögött.

**NINCS benne (tilos):**

- E-mail vagy telefonszám alapú keresés — a §5.2 SDD-invariáns kizárja.
- Kontakt-feltöltés vagy pontos hely szerinti discovery.
- `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/repositories/profile_search_repository.py` | ÚJ |
| `backend/app/community/routers/search.py` | ÚJ |
| `lib/features/community/presentation/screens/community_search_screen.dart` | ÚJ |
| `lib/features/community/data/local/recent_search_store.dart` | ÚJ — lokális, törölhető history |
| `backend/tests/community/test_profile_search.py` | ÚJ — a §6 cellái |
| `test/features/community/presentation/community_search_test.dart` | ÚJ |

**Tilos zóna:** `backend/app/community/policies/query_filters.py` (csak HÍVÁS, nem módosítás) · `lib/features/community/domain/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

### 5.1 A keresés SOSEM e-mail vagy telefonszám alapú

Kizárólag handle és opcionális interest-tag a keresési kulcs — ez a §5.2/§18.7 SDD-invariáns közvetlen leképezése.

**NEM elfogadható gyengítés:** egy "kényelmi" e-mail-alapú barát-kereső funkció bevezetése, akár csak belső/admin célra — ez a kontakt-alapú felfedezés tiltott osztálya.

### 5.2 A keresés a KÖZÖS block/mute-szűrőt hívja, nem párhuzamos logikát

Egy második, keresés-specifikus block-ellenőrzés bevezetése elkerülhetetlenül driftelne a Kör 8 szűrőjétől.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | E-mail vagy telefonszám alapján nincs keresés | `test_profile_search.py` |
| A2 | Blocked és non-discoverable profil nem jelenik meg a találatokban | `test_profile_search.py` |
| A3 | A keresés nem használ teljes táblaszkennelést (index-alapú terv) | `test_profile_search.py` — explain-plan/index teszt |
| A4 | Rate limit érvényesül a keresési endpointon | `test_profile_search.py` |
| A5 | A recent-search lista kizárólag helyi és felhasználó által törölhető | `community_search_test.dart` |
| A6 | Unicode query helyesen normalizálva keres | `test_profile_search.py` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy admin/debug endpoint e-mail-alapú lookupot enged | A1 |
| A keresés nem hívja a Kör 8 közös block-szűrőt | A2 |
| A keresés `LIKE '%...%'` teljes táblaszkenneléssel megy index nélkül | A3 |
| A rate limit hiányzik vagy csak kliensoldali | A4 |
| A recent-search a szerverre szinkronizálódik | A5 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a `query_filters.py` hívását a keresési repositoryból, futtasd a backend pytest-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/presentation/community_search_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_profile_search.py -q
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

1. `profile_search_repository.py` — exact + prefix lookup, index-alapú terv.
2. A közös block/mute-szűrő (Kör 8) bekötése a keresési querybe.
3. `search.py` router — rate limit + minimum query hossz.
4. `community_search_screen.dart` — debounce, recent-search (lokális).
5. Explore-javaslat interest-tag alapon, feature flag mögött.
6. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A kontakt-alapú keresés kísértése.** Egy "barátok megtalálása" funkció könnyen e-mail-alapúvá csúszna — ez explicit tiltott (A1).
- **A block-szűrő megkerülése.** Egy párhuzamos, keresés-specifikus ellenőrzés driftelne a Kör 8 közös szűrőjétől (A2).
- **A teljes táblaszkennelés.** Növekvő userbázisnál ez performance- és DoS-kockázat egyben (A3).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
