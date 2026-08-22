# E09-R16 — Kommentek, reply és mention

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 16
- **Kör-azonosító:** `E09-R16`
- **Branch:** `<motor>/e09-r16-comments-reply-and-mention`
- **Előfeltétel:** `E09-R15` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0405` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 8 közös block-szűrő és a Kör 3 handle-lookup TÉNYLEGES aláírását — a mention-validáció mindkettőt hívja, nem önálló ellenőrzést épít. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/models/comment.py",
  "backend/app/community/services/comment_service.py",
  "backend/app/community/policies/comment_policy.py",
  "backend/alembic/versions/e09_r16_0010_community_comment.py",
  "lib/features/community/presentation/screens/comments_screen.dart",
  "lib/features/community/application/controllers/comment_controller.dart",
  "backend/tests/community/test_comment_service.py",
  "test/features/community/presentation/comments_screen_test.dart",
  "docs/rounds/e09-r16-comments-reply-and-mention.md",
]
gate_tests = [
  "test/features/community/presentation/comments_screen_test.dart"
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

Moderálható, korlátozott mélységű kommentrendszer biztonságos mentionnel — a mention nem kerülheti meg a block/privacy szabályt.

## 2. Jelenlegi állapot — mért tények

- A Kör 11 post-tábla MA létezik, komment nélkül — ez a kör adja hozzá a komment-réteget
- A Kör 3 handle-lookup és a Kör 8 block-szűrő MA készen áll a mention-ellenőrzéshez

## 3. Scope

**Benne van:** comment tábla, maximum reply-depth policy, resource version · list/create/edit/delete endpoint cursor paginationnel · body-hossz, Unicode, tiltott HTML, link- és mention-limit validáció · mention csak létező, látható és NEM blocked profilhoz · comment owner / post owner / moderator jogosultság külön policyben · Flutter comment sheet/detail draft-megőrzéssel · optimista create temp ID-vel, szerver-válasz utáni atomikus csere.

**NINCS benne (tilos):**

- Bookmark — Kör 17.
- Moderation-QUEUE (csak a report/hide gomb helye, a workflow Kör 26/27).
- `docs/adr/**` — az ADR 0405-öt a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/models/comment.py` | ÚJ |
| `backend/app/community/services/comment_service.py` | ÚJ |
| `backend/app/community/policies/comment_policy.py` | ÚJ — owner/moderator jogosultság |
| `backend/alembic/versions/e09_r16_0010_community_comment.py` | ÚJ |
| `lib/features/community/presentation/screens/comments_screen.dart` | ÚJ |
| `lib/features/community/application/controllers/comment_controller.dart` | ÚJ |
| `backend/tests/community/test_comment_service.py` | ÚJ — a §6 cellái |
| `test/features/community/presentation/comments_screen_test.dart` | ÚJ |

**Tilos zóna:** `backend/app/community/policies/query_filters.py` (csak HÍVÁS) · `lib/features/community/domain/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0405)

### 5.1 A mention NEM kerülheti meg a block/privacy szabályt

Egy mention csak akkor kerül feldolgozásra (linkelt/kereshető), ha a megjelölt profil látható a szerző számára ÉS nem blockolja a szerzőt — a mention-validáció a Kör 3/8 meglévő policy-kat hívja.

**NEM elfogadható gyengítés:** egy "egyszerűbb" mention-parser, ami a handle-t regex-szel keresi és linkeli anélkül, hogy ellenőrizné a láthatóságot vagy a blokkot — ez megkerülné a teljes privacy-réteget.

### 5.2 A komment-mélység KORLÁTOZOTT — végtelen thread tiltott

A `parent_id` maximum egy dokumentált mélységig engedett; egy ennél mélyebb reply-kísérlet a szerveren elutasításra kerül.

### 5.3 Az optimista create ATOMIKUSAN cserélődik a valódi ID-re

A kliens temp ID-t rendel a helyben megjelenő komenthez; a szerver-válasz megérkeztével a temp ID egyetlen atomikus állapotváltással cserélődik a valódira, nem duplikált elemként.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Nincs végtelen threadmélység | `test_comment_service.py` |
| A2 | Mention nem kerülheti meg a block/privacy szabályt | `test_comment_service.py` |
| A3 | Private posztra írt komment jogosultsághoz kötött | `test_comment_service.py` |
| A4 | Edit conflict (elavult resource version) elutasítva | `test_comment_service.py` |
| A5 | Delete jogosultság: szerző, post-owner, moderator — más nem | `test_comment_service.py` |
| A6 | Temp ID atomikusan cserélődik, nincs duplikált elem a UI-ban | `comments_screen_test.dart` |
| A7 | Komment-pagination stabil, nincs duplikált oldal | `test_comment_service.py` |
| A8 | XSS stringek (HTML/script) elutasítva a body-ban | `test_comment_service.py` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A mention-parser nem ellenőrzi a block-relációt | A2 |
| Egy 5. szintű reply is elfogadásra kerül | A1 |
| A private posztra írt komment jogosultság-ellenőrzés nélkül átmegy | A3 |
| A delete-et egy tetszőleges bejelentkezett user is elvégezheti | A5 |
| A temp ID és a valódi ID egyszerre látszik a listában | A6 |
| Egy `<script>` tag változatlanul mentődik a body-ba | A8 |

**A küszöb három kötelező cellája** (a reply-mélység (a szülő-lánc hossza, maximum 1 — egyetlen szintű reply engedett)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | top-level komment (mélység 0) | elfogadva |
| **rajta** (a küszöbön) | egyetlen szintű reply (mélység 1, a maximum megengedett) | elfogadva — ez a határ, a §14.2 dokumentált maximuma |
| a küszöb **fölött** | reply egy replyra (mélység 2) | elutasítva — `ValidationError`, a szerver nem hoz létre mélyebb szálat |

A hármas tömören: **alatt** → elfogad · **rajta** → elfogad (a dokumentált maximum) · **fölött** → elutasít.

A határ a mélység-1 (egyetlen reply-szint) az elfogadó oldalhoz tartozik, a mélység-2 már nem.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a mélység-ellenőrzést a `comment_service.py`-ból, futtasd a backend pytest-et egy 2. szintű reply-jal → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/presentation/comments_screen_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_comment_service.py -q
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

1. Migráció: `community_comments` (parent_id, mélység-oszlop vagy számított ág, resource_version).
2. `comment_policy.py` — owner/post-owner/moderator jogosultsági mátrix.
3. `comment_service.py` — create/edit/delete, mention-validáció (Kör 3+8 hívása), mélység-korlát.
4. `comments_screen.dart` — optimista create temp ID-vel, draft-megőrzés.
5. A cursor pagination + a mélység-hármas teszt.
6. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **A mention privacy-megkerülése.** Egy naiv regex-alapú parser linkelne/kereshetővé tenne egy blockolt vagy nem-látható profilt (A2) — ez a kör legsúlyosabb kockázata.
- **A végtelen thread.** UI-teljesítmény és moderálhatóság szempontjából is kritikus korlát (A1).
- **A temp-ID/valódi-ID duplikáció.** Egy rosszul szinkronizált csere két látszólagos kommentet hagyna a listában (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
