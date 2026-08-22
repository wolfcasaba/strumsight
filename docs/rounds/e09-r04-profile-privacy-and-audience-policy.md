# E09-R04 — Profil privacy, audience és szerveroldali policy

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 4
- **Kör-azonosító:** `E09-R04`
- **Branch:** `<motor>/e09-r04-profile-privacy-and-audience-policy`
- **Előfeltétel:** `E09-R03` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0398` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 2 `community_privacy_settings` TÉNYLEGES oszlopait — az audience-enum ide, nem egy új táblába kerül. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/policies/access_policy.py",
  "backend/app/community/schemas/privacy.py",
  "backend/app/community/routers/privacy.py",
  "backend/app/community/models/profile.py",
  "docs/security/community-access-matrix.md",
  "lib/features/community/domain/policies/community_audience.dart",
  "backend/alembic/versions/e09_r04_0004_community_privacy_fields.py",
  "backend/tests/community/test_access_policy.py",
  "docs/rounds/e09-r04-profile-privacy-and-audience-policy.md",
  "docs/adr/0398-profile-privacy-audience-policy-and-access-control.md",
]
gate_tests = [
  "test/core/architecture_dependency_test.dart"
]
native_gate = false
```

## 0.0 Pre-flight brief-revízió (Claude, 2026-08-22, kód olvasva `main @ c13c7f72`)

**B1 — mért, kódból bizonyított allowed_paths-hiányosság (nem csendes
tágítás, hanem a §7 gate-mátrix mérése):** a `backend/tests/test_migrations.py::
test_upgrade_head_matches_current_orm_schema` (a MEGLÉVŐ, nem e körhöz tartozó
gate teszt) `assert compare_metadata(migration_context, Base.metadata) == []`-t
követel — ez az ORM `Base.metadata`-t (tehát a `CommunityPrivacySettings`
Python-osztályt, `backend/app/community/models/profile.py`) hasonlítja a
TÉNYLEGES DB-sémához az `alembic upgrade head` UTÁN. A `.github/workflows/
backend-ci.yml` `push.paths: ["backend/**", ...]`-re fut, tehát ez a kör
(ami a `backend/`-et módosítja) garantáltan kiváltja, és a teljes
`python -m pytest -q` futtatja ezt a tesztet is — NEM csak a brief §7-ben
kért `tests/community/test_access_policy.py`-t.

Az eredeti allowed_paths a `backend/app/community/models/**`-et tiltott
zónaként jelölte ("a Kör 2/3 modelljei bővítés nélkül"), miközben az A5/A1
kritérium új, PERZISZTENS `visibility`/`audience_default` oszlopot kíván a
`community_privacy_settings` táblán (§2, §5) — ha a migráció felveszi ezeket
az oszlopokat, de az ORM-osztály nem, a fenti `compare_metadata` teszt
DETERMINISZTIKUSAN elbukik minden CI-futáson. Ez a §1.1 "elérhetetlen
cél-státusz" hibaosztály tükörképe: itt nem egy elérhetetlen státusz, hanem
egy garantáltan elérhetett PIROS teszt, amit az eredeti fájllista maga
okozna.

**Revízió:** `backend/app/community/models/profile.py` felkerül az
`allowed_paths`-ra, **szigorúan a `CommunityPrivacySettings` osztály két új,
mapped oszlopával korlátozva** (`visibility`, `audience_default` — ld. ADR
0398 §1). A tilos zóna pontosítva: "`backend/app/community/models/**` a
`CommunityPrivacySettings.visibility`/`.audience_default` oszlop-hozzáadásán
kívül (a Kör 2/3 TÖBBI modellje és a `CommunityProfile` osztály bővítés
nélkül)." Új tábla, új oszlop máshol, vagy a `CommunityProfile` osztály
érintése továbbra is tilos zóna (H3).

Az ADR-fájl (`docs/adr/0398-...md`) is felkerült az `allowed_paths`-ra
technikai okból: az orchesztrátor ezt a pre-flightban, ebben a commitban
hozza létre — az implementer NEM írja, de a scope-audit a brief-commit UTÁNI
diffet nézi, és az ADR fájl már ebben a pre-flight commitban létrejön, nem
az implementer diffjében.

**Egyéb §2 tény-ellenőrzés (nincs eltérés):** a `community_privacy_settings`
tábla MA (`e09_r02_0002` migráció, `backend/app/community/models/profile.py`
93–131. sor) valóban csak `id`/`public_id`/`profile_id`/`updated_at` oszlopot
hordoz — nincs `visibility`/`audience` mező, a brief §2 első pontja pontos.
A `RelationshipContext` fogalom MA sehol nem létezik a kódban (első
bevezetés ez a kör) — a §2 harmadik pontja is pontos.

**Előre-kompatibilitás (a Kör 7/8 briefjéből mérve, nem feltételezve):**
`docs/rounds/e09-r08-block-mute-and-safety-relationships.md` §2 explicit
`RelationshipContext.blocked` mezőnevet vár el ettől a körtől — az ADR 0398
ezt a mezőnevet PONTOSAN `blocked: bool`-ként rögzíti (ld. ADR §2), nem
szabad más néven (pl. `is_blocked`) elnevezni.

**§4.9 visszakeresés (ADR 0312, `node tools/knowledge-rag.mjs`):** a
szűkített (`--corpus lessons,halts,adr`) és a teljes korpuszos keresés sem
talált közvetlen, erre a körre alkalmazandó korábbi leckét vagy haltot a
block-elsőbbségi policy-sorrendről vagy az optimistic-concurrency
resource-verzióról; a legközelebbi releváns előzmény a
[`docs/sdd/10-epic-09-community-platform.md` §9.4](../sdd/10-epic-09-community-platform.md)
(a szerveroldali enforcement lista, amivel ez a brief §1/§5.1 egyezik) és
[ADR 0291](../adr/0291-community-is-optional-and-private-by-default.md)
(alap: a közösség nem nyilvános alapból — ezzel egyezik az A5/§5.3). Nincs
kimondottan releváns korábbi HALT vagy LESSON erre a témára (S8 teljesítve).

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

Hozd létre a profil- és audience-hozzáférési döntések KÖZPONTI, tesztelt policy rétegét — minden későbbi read (feed, post, keresés) ezen keresztül megy.

## 2. Jelenlegi állapot — mért tények

- `community_privacy_settings` (Kör 2) MA csak a tábla-vázat hordozza, `visibility`/audience mező nélkül — ez a kör adja hozzá
- nincs még post- vagy feed-olvasó útvonal (Kör 11/13), ezért ez a kör a policy-t ÖNMAGÁBAN, egységtesztekkel bizonyítja, nem élő route-on
- a follow/block kapcsolat még nem létezik (Kör 7/8) — a policy-mátrix ezekre a JÖVŐBELI relationship-státuszokra paraméterezve készül

## 3. Scope

**Benne van:** `ProfileVisibility` és `CommunityAudience` backend + Flutter enum stabil wire értékkel · `CommunityAccessPolicy` szolgáltatás minden profile/post readhez · privacy settings endpoint resource-version mezővel · policy matrix dokumentum (viewer/owner/follower/blocked/club member kombinációk).

**NINCS benne (tilos):**

- A follow/block/club TÉNYLEGES adatmodelljének létrehozása (Kör 7/8/24) — a policy itt egy `RelationshipContext` paraméter-objektumot fogad, nem valódi kapcsolatot olvas.
- Bármely feed vagy post endpoint bekötése — Kör 11/13.
- `docs/adr/**` — az ADR 0398-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/policies/access_policy.py` | ÚJ — `CommunityAccessPolicy` |
| `backend/app/community/schemas/privacy.py` | ÚJ — audience/visibility Pydantic sémák |
| `backend/app/community/routers/privacy.py` | ÚJ — privacy settings endpoint |
| `docs/security/community-access-matrix.md` | ÚJ — a policy mátrix dokumentum |
| `lib/features/community/domain/policies/community_audience.dart` | ÚJ — a Flutter-oldali enum (stabil wire érték) |
| `backend/alembic/versions/e09_r04_0004_community_privacy_fields.py` | ÚJ — visibility/audience oszlop |
| `backend/tests/community/test_access_policy.py` | ÚJ — a §6 cellái |

**Tilos zóna:** `lib/features/community/` a `domain/policies/community_audience.dart`-on kívül (a feature-gyökér Kör 5-től él) · `backend/app/community/models/**` (a Kör 2/3 modelljei bővítés nélkül) · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0398)

### 5.1 A privacy policy SZERVEROLDALI — a kliens UI-elrejtés nem biztonsági határ

Minden read útvonal (profil, poszt, feed, komment) a `CommunityAccessPolicy`-n megy át. A kliens elrejthet elemeket a felületen, de ez UX, nem védelem.

**NEM elfogadható gyengítés:** egy "gyors" kliensoldali szűrés bevezetése a szerveroldali policy helyett vagy mellett, azzal az indokkal, hogy "a UI úgyis elrejti" — ez direkt objektum-referenciás (IDOR) hozzáférést nyitna.

### 5.2 A block MINDEN audience-szabálynál elsőbbséget élvez

A policy-mátrix kiértékelési sorrendje: block-ellenőrzés ELŐSZÖR, utána visibility/audience. Egy blockolt fél számára a profil `private`-ként viselkedik FÜGGETLENÜL a tényleges visibility-től.

**NEM elfogadható gyengítés:** a block-ellenőrzés az audience-ellenőrzés UTÁN, mint "további szűrő" — ez egy `public` profilnál rövid ideig szivárogtathatna adatot a blokkolt fél felé egy race-ben.

### 5.3 Az alapértelmezett profil NEM automatikusan public

Új profil `private` vagy termékdöntés alapján `followers` alapértékkel jön létre, sosem `public`-kal.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A szerver minden readnél policyt alkalmaz (nincs policy-mentes útvonal) | `test_access_policy.py` — paraméterezett mátrix |
| A2 | Block mindig felülírja a follow- és club-jogosultságot | `test_access_policy.py` — block-override cella |
| A3 | Private profil olvasása jogosultság nélkül csak minimális, relationship-safe summaryt ad | `test_access_policy.py` |
| A4 | Followers-only tartalom csak elfogadott follow után látszik | `test_access_policy.py` |
| A5 | Az alapértelmezett profil nem `public` | `test_access_policy.py` |
| A6 | Stale privacy update (elavult resource version) elutasítva | `test_access_policy.py` — optimistic concurrency cella |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A block-ellenőrzés az audience-ellenőrzés UTÁN fut | A2 |
| A private profil teljes bio/avatar mezőt ad vissza jogosultság nélkül | A3 |
| A followers-only tartalom pending (nem accepted) follow mellett is látszik | A4 |
| Az új profil alapértéke `public` | A5 |
| A privacy-update endpoint nem ellenőrzi a resource verziót | A6 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** cseréld fel a kiértékelési sorrendet úgy, hogy az audience-ellenőrzés fusson a block-ellenőrzés ELŐTT, futtasd a backend pytest-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/architecture_dependency_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_access_policy.py -q
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

1. `ProfileVisibility`/`CommunityAudience` enum mindkét oldalon, stabil wire értékkel.
2. `CommunityAccessPolicy` — a kiértékelési sorrend: block → visibility → audience → relationship.
3. A policy-mátrix dokumentum (`community-access-matrix.md`) a kiértékelés forrása.
4. `privacy.py` router — settings endpoint resource-version mezővel.
5. Alembic: `visibility`/`audience_default` oszlopok a Kör 2 táblájához.
6. A block-override, stale-update és private-summary tesztcellák.
7. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A kliensoldali szűrésre hagyatkozás.** A leggyorsabb út egy IDOR-hoz — minden read szerveroldalon kell menjen (A1).
- **A block-audience kiértékelési sorrend felcserélése.** Egy blokkolt fél átmenetileg mégis látná a tartalmat (A2) — ez a legsúlyosabb ebben a körben.
- **Az "egyszerűség kedvéért public" alapérték.** Ez a §9.2 SDD-invariáns közvetlen megsértése lenne (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
