# E09-R25 — Club feed, pinned post és club challenge

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 25
- **Kör-azonosító:** `E09-R25`
- **Branch:** `<motor>/e09-r25-club-feed-pinned-post-and-challenge`
- **Előfeltétel:** `E09-R24` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — ez a kör nem hoz új kötött architekturális döntést (tisztán UI/integráció/lezárás).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 13 `following_feed.py` és a Kör 21 `challenge_invite_service.py` TÉNYLEGES query-alakját — ez a kör ÚJRAHASZNÁLJA őket klub-audience-szűréssel, nem duplikál post- vagy challenge-rendszert. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/feed/club_feed.py",
  "backend/app/community/services/club_content_service.py",
  "lib/features/community/presentation/screens/clubs/club_detail_screen.dart",
  "backend/tests/community/test_club_content_service.py",
  "test/features/community/presentation/clubs/club_detail_screen_test.dart",
  "docs/rounds/e09-r25-club-feed-pinned-post-and-challenge.md",
]
gate_tests = [
  "test/features/community/presentation/clubs/club_detail_screen_test.dart"
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

A klubok számára ugyanazon biztonságos post- és challenge-infrastruktúra újrahasznosítása — a klub feed NEM egy külön poszt-rendszer.

## 2. Jelenlegi állapot — mért tények

- A Kör 11/13 post/feed és a Kör 21 challenge-infrastruktúra MA készen áll, klub-audience nélkül — ez a kör köti be a tagság-ellenőrzést
- A Kör 24 klub-permission mátrix MA létezik — a pin/moderation jog ebből származik

## 3. Scope

**Benne van:** club audience post-policy tagság-ellenőrzéssel · club feed cursor pagination a KÖZÖS post-projekció újrahasznosításával · pinned post reláció maximum konfigurált darabszámmal · club moderator pin/unpin és post-moderation joga a permission-mátrixból · club challenge create/activate/end compatibility-validációval · Flutter club detail tabok: Feed, Challenges, Members, About · club elhagyása után a csak-club tartalom AZONNAL eltűnik a cache-ből.

**NINCS benne (tilos):**

- Új, párhuzamos post- vagy challenge-adatmodell létrehozása.
- `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/feed/club_feed.py` | ÚJ — a Kör 13 projekció újrahasznosítása club-szűréssel |
| `backend/app/community/services/club_content_service.py` | ÚJ — pin/unpin + club-challenge lifecycle |
| `lib/features/community/presentation/screens/clubs/club_detail_screen.dart` | BŐVÍTÉS — Feed/Challenges/Members/About tabok |
| `backend/tests/community/test_club_content_service.py` | ÚJ — a §6 cellái |
| `test/features/community/presentation/clubs/club_detail_screen_test.dart` | ÚJ |

**Tilos zóna:** `backend/app/community/models/post.py`, `models/challenge.py` (csak a club_id-kapcsolat hívása, nem új tábla) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

### 5.1 A klub feed a KÖZÖS post-projekciót hasznosítja újra, klub-audience szűréssel

Nincs külön "club post" adatmodell — a Kör 11 `community_posts` tábla `club_id` mezője és a Kör 13 projekció klub-audience-szűrése adja a klub feedet.

**NEM elfogadható gyengítés:** egy külön `club_posts` tábla létrehozása "egyszerűség kedvéért" — ez duplikálná a moderation/block/audience logikát, és a két rendszer drifteljen egymástól.

### 5.2 A moderator jog NEM terjed túl a saját klubján

A pin/unpin és post-moderation jogosultság-ellenőrzés a KONKRÉT klub tagságához kötött — egy klub moderátora nem moderálhat egy másik klubban.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Nem-tag nem éri el a klub feedjét vagy tartalmát | `test_club_content_service.py` |
| A2 | Klub elhagyása után a cache-ből azonnal eltűnik a csak-club tartalom | `club_detail_screen_test.dart` |
| A3 | Pin-jogosultság csak a klub owner/moderator-jáé | `test_club_content_service.py` |
| A4 | Pin-limit érvényesül (konfigurációból) | `test_club_content_service.py` |
| A5 | Club-challenge eligibility a tagságot ellenőrzi | `test_club_content_service.py` |
| A6 | Block érvényesül klubon belül is (Kör 8/24 szűrő újrahasznosítva) | `test_club_content_service.py` |
| A7 | Klub-feed pagination stabil, nincs duplikált post | `test_club_content_service.py` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy nem-tag közvetlen ID-vel eléri a klub-posztot | A1 |
| Egy másik klub moderátora pin-elhet ebben a klubban | A3 |
| A pin-limit nincs ellenőrizve, tetszőleges számú poszt pin-elhető | A4 |
| Egy nem-tag résztvevőként regisztrálódhat a club-challenge-ben | A5 |
| A klub elhagyása után a régi cache-tartalom még megjelenik | A2 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a tagság-ellenőrzést a klub feed queryjéből, futtasd a backend pytest-et egy nem-taggal → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/presentation/clubs/club_detail_screen_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_club_content_service.py -q
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

1. `club_feed.py` — a Kör 13 projekció újrahasznosítása `club_id` + tagság-szűréssel.
2. `club_content_service.py` — pin/unpin (permission-mátrix), club-challenge lifecycle (Kör 21 hívása).
3. `club_detail_screen.dart` bővítése a négy tabbal.
4. A klub-elhagyás utáni cache-invalidáció.
5. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **A párhuzamos post-rendszer csábítása.** Egy külön `club_posts` tábla gyorsabbnak tűnne, de duplikálná és driftelné a moderation-logikát (A1/A6).
- **A moderator-jog túlterjedése.** Egy rosszul paraméterezett ellenőrzés klubok közötti jogosultság-szivárgást okozna (A3).
- **Az elmaradt cache-invalidáció.** A klub elhagyása után is látszó tartalom megsértené a §16.4 SDD-elvárást (A2).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
