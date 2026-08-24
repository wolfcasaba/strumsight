# E09-R24 — Klub domain, tagság és szerepkörök

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`) → pre-flight revideálva 2026-08-24, kód újra-olvasva `main @ 0e12cd90`
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 24
- **Kör-azonosító:** `E09-R24`
- **Branch:** `<motor>/e09-r24-club-domain-membership-and-roles`
- **Előfeltétel:** `E09-R23` merge-elve
- **Brief szerzője:** Claude (Opus 5); pre-flight revízió: Claude Sonnet 5
- **Előre kiosztott ADR:** ~~`ADR 0413`~~ **`ADR 0420`** — a `0413` MÁR foglalt. `tools/round-slots.py reserve-adr --round E09-R24` friss számot adott. Lásd [ADR 0420](../adr/0420-club-domain-membership-and-roles.md) a teljes döntéskörért.

**Kockázat = high, indoklás:** a kör egy szerveroldali permission-rendszert
(owner/moderator/member) és tagság-lifecycle-t vezet be, amelynek elsődleges
kockázata, hogy (a) egy owner nélkül maradó klub moderálhatatlanná válna
(A1), (b) egy kliensoldali "bízunk benne" jogosultság-ellenőrzés lehetővé
tenné egy member számára más tagok role-jának módosítását (A2), és (c) a
Kör 8 block-invariáns megkerülhetővé válna egy klub-specifikus párhuzamos
ellenőrzés bevezetésével (A6). Egyik `allowed_paths` fájl sem egyezik szó
szerint a router `high_risk_path_fragments` listájával, de a kockázat
ettől függetlenül valós — jogosultság-eszkaláció és safety-regresszió, nem
forma szerinti kulcsszó-egyezés.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 8 block-szűrő TÉNYLEGES aláírását — a klub-tagságnak is ugyanazt a közös szűrőt kell hívnia, nem egy klub-specifikus párhuzamos ellenőrzést. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

## 0.0c CI-only javító addendum (2026-08-24, review + CI után, Claude Sonnet 5)

A `full-gate.yml` run (PR #441, SHA `855db329`) egyetlen teszttel bukott:
`test/ui/ui_inventory_test.dart` — `expect(first.screenPaths, hasLength(76))`
PIROS, tényleges hossz `79`. A round 3 ÚJ képernyőt ad
(`club_list_screen.dart`/`club_detail_screen.dart`/
`club_member_management_screen.dart`), de a screen-számláló bővítése
kimaradt a `allowed_paths`-ból — ugyanaz a mért drift-osztály, mint az
E09-R21 brief §0.0 2. pontjában (`docs/rounds/e09-r21-challenge-and-invite-lifecycle.md`,
"screen-számláló 74→75") — ott EXPLICIT `allowed_paths`-tag volt, itt a
pre-flight (aláírásom) elmulasztotta felvenni, holott ugyanezt a mintát már
olvastam a pre-flight során. Ez az én mulasztásom, nem az implementeré — a
gate lokálisan csak a brief §7 szerinti szűk útvonalat futtatta
(`club_list_screen_test.dart`), a `ui_inventory_test.dart` csak a TELJES
CI-suite-ban fut le, ott bukott elsőként most.

**Javítás — `allowed_paths` bővítve** (ADR 0087 §2 önjavítható eset, brief-
revízió, nem tilos-zóna feloldás — a widening egy MÁR ismert, precedenses
minta, nem ad-hoc kerülőút):

- `test/ui/ui_inventory_test.dart` — a `hasLength(76)` → `hasLength(79)`
  bump, KIZÁRÓLAG a számláló-konstans, semmi más a fájlban nem változik
  (a teszt maga generatíven olvassa a screen-listát, nincs kézzel írt
  útvonal-lista a fájlban a `contains(...)` sorokon kívül, amiket ez a kör
  nem érint). Az EGYETLEN `ai-router` blokk (lentebb, a §0.0 pre-flight
  után) frissítve — a parser csak egy blokkot fogad el brief-enként.

## 0.0 Pre-flight brief-revízió (2026-08-24, Claude Sonnet 5)

A teljes mért-tény alapú indoklás [ADR 0420](../adr/0420-club-domain-membership-and-roles.md)
Kontextus/Döntés szakaszában. Összefoglalva:

1. **A Flutter klub-domain MÁR él (Kör 5, ADR 0399), TILOS zóna, csak-hívás.**
   `community_club.dart`/`club_repository.dart` már definiálja a kliens-
   kontraktust — a backend wire-formátumnak ehhez kell igazodnia, nem
   fordítva:
   - `ClubVisibility` **HÁROM** állapot: `private`, `discoverable`, `public`
     (nem csak private/public).
   - `ClubRole` **HÁROM** állapot: `owner`, `moderator`, `member`.
   - `kCommunityClubMaxMembers = 500` MÁR ki van mérve — a §6.1 küszöb-
     hármas ezt az ÉRTÉKET tükrözi (`MAX_CLUB_MEMBERS = 500` a backendben),
     nem egy önkényes új számot (ADR 0420 D3).
   - `transferOwnership` doksi-kommentje szerint a régi owner role-ja
     PONTOSAN `member`-re vált — a lenti §6 A8 sora javítva (ADR 0420 D4).
   - Minden mutáló repository-hívás `idempotencyKey`-t visz — a service a
     Kör 20/21 DB-unique + `IntegrityError`-újraolvasás mintát követi (ADR
     0420 D5), NEM új mechanizmust.
   - A metódus neve `requestJoin` — `private` klubnál függő kérés, amit
     owner/moderator fogad el; `discoverable`/`public` klubnál azonnali
     tagság (ADR 0420 D6). Az elfogadás-hívás a `club_service.py`-ban él,
     HTTP router nélkül is elfogadható ebben a körben.
   - `community_clubs` PK/public-id a MEGSZOKOTT mintát követi: belső
     `id: BigInteger` + külső `public_id: Uuid(as_uuid=True), unique=True`
     (ADR 0420 D1).
2. **Informatív, NEM ennek a körnek a feladata:** a `community_posts.club_id`
   (BigInteger, Kör 11) és a `community_challenges.club_id` (String, Kör 21)
   típus-eltérése — a feloldás a Kör 25 (klub-feed/klub-challenge FK) dolga,
   erre az ADR-re hivatkozva (ADR 0420 D2).
3. **Nincs önálló create-screen.** A §3 "create képernyő" szövege pontatlan
   — az `allowed_paths` a mérvadó: NINCS `club_create_screen.dart`, a
   létrehozás UI a `club_list_screen.dart`-ba épül (ADR 0420 D7).
4. **Újrahasznosítandó, MÉRT minták (ne találj ki újat):**
   - Block-ellenőrzés: `query_filters.py::is_blocked_pair(db, profile_id_a=,
     profile_id_b=)` és `filter_public_ids_against_viewer_blocks(...)`
     write-side ÉS read-side hívás, NEM a `query_filters.py` bővítése
     (tilos zóna, csak-hívás).
   - Idempotency: DB unique constraint + előzetes olvasás + `IntegrityError`
     → rollback + újraolvasás (mint `post_service.py::_existing_post_by_idempotency_key`,
     ADR 0415).
   - A3 duplikált-join valódi-sértés próba: ELSŐDLEGESEN a DB UNIQUE
     constraint méri (két egymást követő hívás, a második ütközik) — ez NEM
     igényel threading-et. Ha mégis konkurens race-tesztet ír az implementer,
     a `threading.Barrier`-t a PONTOS SQL-döntési pont elé kell tenni, NEM a
     szál-indítás elé (L421 — 10-ből 7 piros szinkronizáció nélkül mérve).
5. **Migráció-lánc ellenőrizve.** `ls backend/alembic/versions/ | sort |
   tail -1` → `e09_r23_0017_...` — a brief `e09_r24_0018_community_club.py`
   fájlneve és `down_revision = "e09_r23_0017"` helyes, folytonos illesztés.

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
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e09-r24-club-domain-membership-and-roles.md",
]
gate_tests = [
  "test/features/community/presentation/clubs/club_list_screen_test.dart",
  "test/ui/ui_inventory_test.dart",
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
| A8 | Ownership transfer sikeres, a régi owner role-ja PONTOSAN `member`-re vált (§0.0 pont 1, ADR 0420 D4 — a Flutter `transferOwnership` kontraktus doksi-kommentje ezt rögzíti) | `test_club_service.py` |

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

**`MAX_CLUB_MEMBERS = 500`** (§0.0 pont 1, ADR 0420 D3 — a Flutter
`kCommunityClubMaxMembers` MÁR élő értékének szerveroldali tükrözése, nem
önkényes új szám):

```bash
python3 -c "MAX=500; print('alatt', MAX-1); print('rajta', MAX); print('fölött', MAX)"
# alatt   499 → elfogad
# rajta   500 → elfogad (az 500. tag az utolsó szabad hely)
# fölött  500 + 1 újabb join → elutasít
```

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
