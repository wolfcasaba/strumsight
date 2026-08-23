# E09-R24 — Klub domain, tagság és szerepkörök

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 24
- **Kör-azonosító:** `E09-R24`
- **Branch:** `<motor>/e09-r24-club-domain-membership-and-roles`
- **Előfeltétel:** `E09-R23` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0413` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 8 block-szűrő TÉNYLEGES aláírását — a klub-tagságnak is ugyanazt a közös szűrőt kell hívnia, nem egy klub-specifikus párhuzamos ellenőrzést. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/models/club.py",
  "backend/app/community/policies/club_permissions.py",
  "backend/app/community/services/club_service.py",
  "backend/alembic/versions/e09_r24_0018_community_club.py",
  "lib/features/community/presentation/screens/clubs/club_list_screen.dart",
  "lib/features/community/presentation/screens/clubs/club_detail_screen.dart",
  "lib/features/community/presentation/screens/clubs/club_member_management_screen.dart",
  "backend/tests/community/test_club_service.py",
  "test/features/community/presentation/clubs/club_list_screen_test.dart",
  "docs/rounds/e09-r24-club-domain-membership-and-roles.md",
]
gate_tests = [
  "test/features/community/presentation/clubs/club_list_screen_test.dart"
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

Kisebb, témaközpontú tanulócsoportok explicit permission-rendszerrel — owner nélkül nem maradhat aktív klub.

## 2. Jelenlegi állapot — mért tények

- Ez az első kör, ami a `community_club` entitást (Kör 5 domain) TÉNYLEGES adatmodellel és lifecycle-lal tölti fel

## 3. Scope

**Benne van:** club, member, invite tábla public ID-val, visibilityvel, role-lal · create/read/update/join/leave/invite/member-remove/role-change lifecycle · explicit permission mátrix: owner, moderator, member · ownership transfer KÖTELEZŐ owner leave/delete előtt · membership + invite limit konfigurációból · block policy közös klubban is érvényesül · Flutter club list/detail/create/member-management képernyő.

**NINCS benne (tilos):**

- Klub-feed vagy klub-challenge — Kör 25.
- Privát chat bevezetése bármilyen formában — a §16.6 SDD kifejezetten kizárja.
- `docs/adr/**` — az ADR 0413-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/models/club.py` | ÚJ |
| `backend/app/community/policies/club_permissions.py` | ÚJ |
| `backend/app/community/services/club_service.py` | ÚJ |
| `backend/alembic/versions/e09_r24_0018_community_club.py` | ÚJ |
| `lib/features/community/presentation/screens/clubs/club_list_screen.dart` | ÚJ |
| `lib/features/community/presentation/screens/clubs/club_detail_screen.dart` | ÚJ |
| `lib/features/community/presentation/screens/clubs/club_member_management_screen.dart` | ÚJ |
| `backend/tests/community/test_club_service.py` | ÚJ — a §6 cellái |
| `test/features/community/presentation/clubs/club_list_screen_test.dart` | ÚJ |

**Tilos zóna:** `backend/app/community/policies/query_filters.py` (csak HÍVÁS) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0413)

### 5.1 Owner nélkül NEM maradhat aktív klub

Az owner leave/delete művelete KÖTELEZŐVÉ teszi az ownership transfert (vagy a klub archiválását/törlését, ha nincs más tag) — a szerver ezt tranzakcióban kényszeríti ki.

**NEM elfogadható gyengítés:** egy owner leave, ami egyszerűen törli az owner-t és a klubot "owner nélkül" hagyja — ez árva, moderálhatatlan klubokat termelne.

### 5.2 A role-mutáció SZERVEROLDALI jogosultságot használ, explicit mátrixszal

Owner/moderator/member permission-mátrix a `club_permissions.py`-ban él, minden role-változtatás ezen keresztül megy — nincs kliensoldali "bízunk benne" jogosultság-ellenőrzés.

### 5.3 A block policy közös klubban is érvényesül

Két blokkoló fél egy közös klubban sem lát egymástól tartalmat — a Kör 8 közös szűrő itt is hívva van.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Owner leave KÖTELEZŐ ownership transfert igényel | `test_club_service.py` |
| A2 | Permission mátrix (owner/moderator/member) tesztelt minden művelethez | `test_club_service.py` |
| A3 | Duplikált join nem hoz létre két tagságot | `test_club_service.py` |
| A4 | Private klubba csak invite/elfogadott request útján lehet bekerülni | `test_club_service.py` |
| A5 | Member removal helyes jogosultsággal (owner/moderator) | `test_club_service.py` |
| A6 | Blockolt tagok nem látják egymás tartalmát közös klubban | `test_club_service.py` |
| A7 | Membership/invite limitek konfigurációból érvényesülnek | `test_club_service.py` |
| A8 | Ownership transfer sikeres, a régi owner role-ja `member`-re vagy `moderator`-ra vált | `test_club_service.py` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Az owner leave törli az owner-t transfer nélkül, a klub owner nélkül marad | A1 |
| Egy member módosíthatja egy másik tag role-ját | A2 |
| Két konkurens join két tagsági rekordot hoz létre | A3 |
| A privát klub bárki számára csatlakozható invite nélkül | A4 |
| A block-szűrő nincs bekötve a klub-tartalom lekérdezésébe | A6 |

**A küszöb három kötelező cellája** (a klub taglétszáma a konfigurált `MAX_CLUB_MEMBERS`-hez képest):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `member_count = MAX_CLUB_MEMBERS - 1` | a join elfogadva |
| **rajta** (a küszöbön) | `member_count == MAX_CLUB_MEMBERS` | az UTOLSÓ join MÉG elfogadva — a limit inkluzív felső határ |
| a küszöb **fölött** | `member_count == MAX_CLUB_MEMBERS` és egy ÚJABB join érkezik | elutasítva, dokumentált hibakóddal |

A hármas tömören: **alatt** → elfogad · **rajta** → elfogad (az utolsó szabad hely) · **fölött** → elutasít.

A határ `MAX_CLUB_MEMBERS` a záró, még elfogadott taglétszám — az ezt meghaladó join utasítódik el.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a kötelező-transfer ellenőrzést az owner-leave endpointból, futtasd a backend pytest-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/presentation/clubs/club_list_screen_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_club_service.py -q
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

1. Migráció: `community_clubs`, `community_club_members`, `community_club_invites`.
2. `club_permissions.py` — owner/moderator/member explicit mátrix.
3. `club_service.py` — lifecycle (create/join/leave/invite/remove/role-change/ownership-transfer).
4. A block-szűrő bekötése a klub-tartalom és tagság-lekérdezésekbe.
5. `club_list_screen.dart`, `club_detail_screen.dart`, `club_member_management_screen.dart`.
6. A membership/invite-limit konfigurációs teszt.
7. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **Az owner-mentes klub.** Egy elhagyott, moderálhatatlan klub biztonsági és support-teherré válna (A1) — ez a kör legfontosabb invariánsa.
- **A kliensoldali jogosultság-ellenőrzés.** Egy member könnyen manipulálhatná a UI-t, ha a szerver nem ellenőrzi újra a role-t (A2).
- **A block megkerülése klubban.** A közös tér csábít egy "kivétel" bevezetésére, de ez pont a legérzékenyebb kontextus (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
