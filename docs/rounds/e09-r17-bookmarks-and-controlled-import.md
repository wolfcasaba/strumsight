# E09-R17 — Bookmark, mentett tartalom és biztonságos import

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 17
- **Kör-azonosító:** `E09-R17`
- **Branch:** `<motor>/e09-r17-bookmarks-and-controlled-import`
- **Előfeltétel:** `E09-R16` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0406` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 10 `plan template`/`original progression` artifact TÉNYLEGES mezőit — az import-validáció ezekre a MEGLÉVŐ schema-verziókra épül. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/models/bookmark.py",
  "backend/app/community/routers/bookmarks.py",
  "backend/alembic/versions/e09_r17_0011_community_bookmark.py",
  "lib/features/community/presentation/screens/bookmarks_screen.dart",
  "lib/features/community/application/use_cases/import_share_artifact.dart",
  "backend/tests/community/test_bookmark_service.py",
  "test/features/community/application/import_share_artifact_test.dart",
  "docs/rounds/e09-r17-bookmarks-and-controlled-import.md",
]
gate_tests = [
  "test/features/community/application/import_share_artifact_test.dart"
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

Privát mentés és share-artifactból induló, kontrollált Practice/Song import — az import ÚJ lokális példányt hoz létre, sosem mutálja a community postot.

## 2. Jelenlegi állapot — mért tények

- A Kör 10 artifact-szerződés MA hordozza a `plan template` és `original progression` típusokat — ez a kör az első, ami ezekből TÉNYLEGESEN lokális tartalmat hoz létre
- A meglévő `lib/features/practice/**` és `lib/features/songs/**` importáló felülete NEM ismeri a Communityt — ez a kör csak a Community-oldali use-case-t adja, a cél-feature saját `public.dart`-ján keresztül

## 3. Scope

**Benne van:** bookmark tábla + idempotens set/remove API · Bookmarks képernyő cursor paginationnel, törölt-content tombstone kezeléssel · explicit Import action plan template/original progression artifactnál · import-validáció: schema version, dependency, licenc/meta státusz, lokális ütközés · import ÚJ lokális példányt hoz létre source attributionnel, NEM mutálja a postot · ismeretlen/deprecated artifactnál read-only fallback · a bookmark-count PRIVÁT marad.

**NINCS benne (tilos):**

- A cél-feature (`practice`, `songs`) belső importáló logikájának módosítása — csak a `public.dart`-jukon keresztüli hívás.
- Teljes védett dalanyag (tab, backing track) importja.
- `docs/adr/**` — az ADR 0406-ot a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/models/bookmark.py` | ÚJ |
| `backend/app/community/routers/bookmarks.py` | ÚJ |
| `backend/alembic/versions/e09_r17_0011_community_bookmark.py` | ÚJ |
| `lib/features/community/presentation/screens/bookmarks_screen.dart` | ÚJ |
| `lib/features/community/application/use_cases/import_share_artifact.dart` | ÚJ |
| `backend/tests/community/test_bookmark_service.py` | ÚJ — a §6 cellái |
| `test/features/community/application/import_share_artifact_test.dart` | ÚJ |

**Tilos zóna:** `lib/features/practice/**`, `lib/features/songs/**` belső (nem `public.dart`) fájljai · `lib/features/community/domain/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0406)

### 5.1 Az import ÚJ lokális példányt hoz létre — SOSEM mutálja a community postot

Az import-use-case a cél-feature `public.dart` felületén keresztül egy ÚJ, önálló lokális entitást hoz létre, forrás-attribúcióval — a közösségi poszt tartalma ettől függetlenül, változatlanul él tovább.

**NEM elfogadható gyengítés:** egy "referencia-alapú" import, ami csak egy linket ment a community posztra ahelyett, hogy valódi lokális másolatot készítene — ez a poszt törlésekor vagy szerkesztésekor csendben elromlana.

### 5.2 A bookmark-aktivitás PRIVÁT — a count nem publikus

A bookmark-számláló sosem kerül a publikus post-projekcióba; kizárólag a bookmarkoló felhasználó saját listájában látszik.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Bookmark set/remove idempotens | `test_bookmark_service.py` |
| A2 | A bookmark-count nem publikus (nem szerepel a post-projekcióban) | `test_bookmark_service.py` |
| A3 | Törölt poszt bookmarkja biztonságos tombstone-t kezel (nem crash, nem üres hivatkozás) | `test_bookmark_service.py` |
| A4 | Import-validáció elutasítja az ismeretlen/érvénytelen schema-verziót | `import_share_artifact_test.dart` |
| A5 | Import új lokális példányt hoz létre, a forrás community post változatlan marad | `import_share_artifact_test.dart` |
| A6 | Lokális névütközés kezelt (nem csendes felülírás) | `import_share_artifact_test.dart` |
| A7 | Deprecated artifactnál read-only fallback jelenik meg | `import_share_artifact_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A bookmark-count megjelenik a nyilvános post-response-ban | A2 |
| Egy törölt poszt bookmarkja null-pointer hibát dob megnyitáskor | A3 |
| Az import elfogad egy ismeretlen schema-verziójú artifactot | A4 |
| Az import mutálja a forrás community post artifact-mezőjét | A5 |
| Egy azonos című lokális tartalom csendben felülíródik | A6 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** kapcsold ki az import schema-verzió ellenőrzését, futtasd a flutter tesztet egy ismeretlen verziójú artifacttal → az **A4** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/application/import_share_artifact_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_bookmark_service.py -q
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

1. Migráció: `community_bookmarks` unique `(post_id, profile_id)`.
2. `bookmarks.py` router — idempotens set/remove, cursor pagination.
3. `import_share_artifact.dart` — schema-validáció, licenc/meta ellenőrzés, névütközés-kezelés.
4. `bookmarks_screen.dart` — tombstone állapot törölt tartalomra.
5. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **Az import mint mutáció.** Ha az import bármilyen módon visszaírna a community postba, két felhasználó ütköző módosítást okozhatna (A5).
- **A bookmark-count szivárgása.** Egy "hasznos" statisztika-mező könnyen kiszivárogtatná a privát mentési szokásokat (A2).
- **A csendes névütközés-felülírás.** A felhasználó elveszítené egy korábban létrehozott lokális tartalmát észrevétlenül (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
