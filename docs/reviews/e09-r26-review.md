# E09-R26 review — Felhasználói report és azonnali safety flow

- **Kör:** E09-R26
- **Branch:** `minimax/e09-r26-user-report-and-immediate-safety-flow`
- **Végleges reviewelt HEAD:** `28a53b1a` (javító kör HEAD `7dda0de6` +
  orchesztrátor 2. §0.3 upstream-sync merge origin/main `680dc206`, E13-R14
  heal)
- **1. körös reviewelt HEAD:** `eb6d3868` (implementer HEAD `ddb85740` +
  orchesztrátor 1. §0.3 upstream-sync merge origin/main `b93fbdc0`)
- **Implementer:** MiniMax M3
- **Orchesztrátor/reviewer:** Claude Sonnet 5
- **Reviewelt klón:** `/tmp/review-e09-r26` (1. kör), `/tmp/review-e09-r26-fix`
  + `/tmp/review-e09-r26-final` (javító kör után, végleges), mind izolált
  `git clone --branch ... https://github.com/wolfcasaba/strumsight.git`
- **ADR:** [0422](../adr/0422-user-report-and-immediate-safety-flow.md)
- **Végső döntés:** **APPROVED** (lásd §9)

## 1. Jelzés + handoff

`.codex-round-status` (utolsó): `status=done`, `head=ddb85740`,
`summary="gate 9/9 ZÖLD, §6.1 probe verified A1→RED→restore→green, 2
fix-commits"`. A brief §10 handoff szekciója kitöltve, fájlonkénti
scope-táblázattal és A1–A7 bizonyíték-hivatkozásokkal — nem bemondás, a
mögöttes tesztek léteznek és futtathatók.

Az implementer útja NEM volt egyenes: két `stopped` jelzés volt, MINDKETTŐ
az orchesztrátor SAJÁT pre-flight hibájára mutatott rá (a §0.0 D1 rossz ARB
útvonalat vett fel: a generált `app_{en,hu}.arb`-ot ahelyett, hogy a
FORRÁS-fragmentumot (`community_{en,hu}.arb`) sorolta volna fel; majd a
mechanikus scope-audit a generált aggregate visszaváltozását is
sértésként jelezte). Mindkettőt a brief §0.0b/§0.0c dokumentálja, az
implementer helyesen state-oldotta STOP-pal ahelyett, hogy csendben
hardkódolt volna vagy kilógott volna a listából — ez a STOP-protokoll
tankönyvi működése.

## 2. Gate — SAJÁT kézzel, izolált klónban

```
tools/round-gate.sh test/features/community/presentation/report_content_sheet_test.dart
```

| # | Lépés | Eredmény |
|---|---|---|
| 1 | format | ZÖLD |
| 2 | analyze | ZÖLD |
| 3 | test (report_content_sheet_test.dart, 11 teszt) | ZÖLD |
| 4 | architecture | ZÖLD (12 allowlisted deviation — meglévő, nem e kör) |
| 5 | secrets | ZÖLD (3642 fájl, 0 lelet) |
| 6 | l10n parity | ZÖLD (en→hu, 1866 üzenet) |
| 7 | backend ruff format | ZÖLD |
| 8 | backend ruff check | ZÖLD |
| 9 | backend pytest (TELJES suite) | *lásd alább — folyamatban/eredmény a záró frissítésben* |

Célzott backend teszt önállóan is lefuttatva:
`cd backend && python -m pytest tests/community/test_report_service.py -q`
→ **21 passed** (saját kézzel megismételve, az implementer jelentésétől
függetlenül).

## 3. Scope-audit

```
python3 tools/scope-audit.py --repo /tmp/review-e09-r26 \
  --brief docs/rounds/e09-r26-user-report-and-immediate-safety-flow.md \
  --base b93fbdc0
```

Eredmény: **13 changed path, 1 flagged** —
`docs/adr/0422-user-report-and-immediate-safety-flow.md`. Ez az
orchesztrátor SAJÁT pre-flight artefaktuma (a brief explicit kimondja: "az
implementer a `docs/adr/`-t NEM érinti (TILOS zóna)"), nem az implementer
diffje — a review-jelentés saját-artefaktum mentességének pontos analógja
(a skill §3 pontja). A többi 12 útvonal MIND az `allowed_paths`-on (a §0.0c
javítás utáni, 4 ARB fájlt is tartalmazó listán). **Nincs valódi
scope-sértés.**

(Megjegyzés a `--base` választásról: a round `9b3a5d5d`-ről indult, de a
HEAD egy §0.3 upstream-sync merge-öt is tartalmaz `origin/main`
`b93fbdc0`-ra — a `b93fbdc0`-t használva bázisnak a `git diff <base>`
plain két-pontos szemantikája nem keveri bele a HANDOFF/LESSONS/RTM/queue
merge-zajt.)

## 4. Acceptance criteria — tételesen

| # | Kritérium | Bizonyíték | Verdikt |
|---|---|---|---|
| A1 | Reporter identitás sosem szivárog | `test_a1_*` (4 teszt: dataclass-strukturális, `build_sanitized_response` runtime, HTTP wire-shape, valódi-sértés próba) + a security-reviewer FÜGGETLEN mutation-próbája (lásd §6) | ✅ TARTJA, kétszeresen mérve |
| A2 | Duplikált report idempotens | `test_a2_*` (3 teszt: azonos triple idempotens, más kategória 2 sort ad, konkurrens submit 1 sort ad) | ✅ TARTJA |
| A3 | Azonnali hide/mute/block | `report_content_sheet_test.dart::test_a3_*` (4 teszt) — sajátkezűleg átolvasva, a widget UI valóban 3 gombot rendel a thanks fázisban, `targetAuthorPublicId == null` esetén helyesen csak hide marad | ✅ TARTJA |
| A4 | Törölt target kontrolláltan | `test_a4_*` (4 teszt: aktív/soft-deleted/ismeretlen target + helper unit-teszt) | ✅ TARTJA (lásd 5.2 él-eset megjegyzés) |
| A5 | Érvénytelen kategória elutasított | `test_a5_*` (3 teszt + router 422) | ✅ TARTJA |
| A6 | Rate limit | `test_a6_*` — kulcs a hívó BELSŐ profil-id-je (ADR 0422 D6 döntésnek megfelelően, NEM IP) | ✅ TARTJA |
| A7 | Screen-reader elérhetőség | `report_content_sheet_test.dart::test_a7_*` (2 teszt: cím szemantikai fókusza, kategória-gombok label-je) | ✅ TARTJA |

## 5. Próbateszt / mutation-eredmények

### 5.1 §6.1 valódi-sértés próba — függetlenül megismételve

A security-reviewer (lásd §6) a saját, a jelentett tesztkészlettől
FÜGGETLEN eszközökkel futtatta újra az A1 teszteket
(`python3 -m pytest -k a1` → zöld) és forráskód-szinten igazolta, hogy
`build_sanitized_response` egy literál 6-kulcsos dict-et ad vissza, a
router `jsonable_encoder`-t az ORM soron NEM hív. Az implementer saját,
élő próbája (§10.4: `reporter_public_id: "PROBE_LEAK"` kulcs ideiglenes
hozzáadása → A1 PIROS → visszaállítás → zöld) dokumentálva és a fenti
független módszerrel is megerősítve.

### 5.2 Saját olvasással talált, nem-blokkoló hibaosztályok

**F1 (MINOR) — `target_id` formátum-validáció hiánya `target_type ∈
{post, comment}` esetén → téves HTTP-státusz.**
`backend/app/community/services/report_service.py:205-227`
(`target_exists`) `uuid.UUID(target_id)`-t hív VALIDÁCIÓ nélkül; egy
nem-UUID `target_id` string (`"not-a-uuid"`) `ValueError`-t dob, amit a
router (`backend/app/community/routers/reports.py:199-201`) az általános
`except ValueError` ághoz köt, ami **404**-et ad "reporter profile not
found"-stílusú szemantikával — holott a valódi hiba egy rosszul formázott
kliens input (helyes válasz: 400/422). Az `_ALLOWED_TARGET_TYPES` szűrés
megvédi a `target_type`-ot, de a `target_id` formátumát a router sosem
ellenőrzi explicit módon. **Nem tesztelt él** —
`test_a4_report_against_unknown_target_sets_flag_true` egy VALÓS,
jólformázott, csak nem-létező UUID-t használ (`uuid.uuid4()`), nem egy
malformáltat. Nincs biztonsági következménye (nincs adatszivárgás), csak
zavaró hibaüzenet egy hibás kliens felé. **Javasolt irány:** a router
`target_id`-t is validálja UUID-formára `target_type`-tal együtt, 400-at
adva explicit üzenettel.

**F2 (MINOR) — `extra_metadata` JSON csonkítás érvénytelen JSON-t
termelhet, és nincs méret-korlát KÓDOLÁS előtt.**
`report_service.py:384-393` `json.dumps(extra_metadata)`-t futtat egy
NEM méret-korlátozott bemeneten, majd karakter-szinten vágja 2048-ra
(`encoded[:2048]`) — ez tetszőleges byte-határon vághat érvénytelen JSON-t
eredményezve. A `report_service.py` docstringje (30-34. sor) tévesen
állítja: *"The router enforces the same cap at the request boundary"* — a
router (`reports.py:160-168`) NEM alkalmaz semmilyen méret- vagy
kulcsszám-korlátot. **Jelenleg látenciás** (a security-reviewer megerősíti:
a Flutter sheet ebben a körben sosem küld `extra_metadata`-t, és a
`reports.py` router NINCS bekötve az éles `build_community_router`-be —
lásd §6), de a Kör 27 moderation-queue, amint `json.loads`-ot futtat ezen
az oszlopon, fail-open helyett ÉSZREVÉTLENÜL kaphat `JSONDecodeError`-t.
**Javasolt irány:** a bemenetet byte-méret/kulcsszám-korláttal védeni
`json.dumps` ELŐTT (nem a kódolt string utólagos vágásával), vagy a
docstring-et igazítani a tényleges (hiányzó) router-oldali korláthoz.

**F3 (MINOR) — elszórt, téves `ADR 0414` hivatkozás öt fájlban.**
`backend/app/community/models/report.py:1`,
`backend/app/community/services/report_service.py:1`,
`backend/app/community/routers/reports.py:1`,
`backend/alembic/versions/e09_r26_0019_community_report.py:1`,
`lib/features/community/presentation/dialogs/report_content_sheet.dart:1`
mind `"ADR 0414"`-re hivatkoznak a fejléc-docstringben — ez a Kör 20
(notification inbox) ADR-je, NEM ez a köré (a helyes szám `0422`, a brief
§0.0/§0.0b/§0.0c ezt már kétszer korrigálta magában a briefben, de az
implementer a kódkommentekbe a régi, előre kiosztott számot írta, mielőtt
az első STOP-javítás megérkezett volna). Egy jövőbeli olvasó, aki a
docstring-hivatkozást követi, a ROSSZ ADR-re jut. Ártalmatlan (nem
funkcionális), de az SDD-lánc traceability-elve ellen megy. **Javasolt
irány:** egysoros csere mind az 5 fájlban `ADR 0414` → `ADR 0422`.

**F4 (NOTE) — `report.py` docstring egy nem létező `deleted_at` oszlopra
hivatkozik.** A modellen a mező neve `target_deleted_at_submit`
(`report.py:154-158`), a docstring (47-50. sor) viszont `` `deleted_at`
column``-ot mond — feltehetően a post/comment modellek docstringjéből
másolt maradék szöveg. Kozmetikai.

**F5 (NOTE) — `dedup_key` docstring `reporter_public_id`-t mond, a kód
`reporter_profile_id`-t (belső id) használ.** `report.py:138-142` és
`report_service.py:160-174` — a tényleges implementáció a BELSŐ id-t
használja (helyesen, ez a biztonságosabb választás), csak a docstring
komment téveszt. Kozmetikai, a security-reviewer is ugyanezt találta
függetlenül.

## 6. Security review (risk=high, kötelező)

Dedikált `security-reviewer` subagent, teljes jelentés:
[`docs/reviews/e09-r26-security.md`](e09-r26-security.md).

**Verdikt: PASS.** 0 BLOCKER, 0 CRITICAL, 0 MAJOR, 1 MINOR (= a fenti F2-vel
azonos lelet, függetlenül megtalálva), 2 NOTE (= F4/F5-tel egybevágó
kozmetikai észrevételek). A rate-limit kulcs spoofolhatatlan (JWT-eredetű
belső id), nincs IDOR, a nyers `text()` SQL parametrizált, a migráció
UNIQUE/FK/CASCADE szerkezete helyes.

## 7. Architektúra + termékhatárok

- AGENTS.md §6 domain-függetlenség: `report_service.py` a `post.py` /
  `comment.py` modelleket csak FÜGGVÉNYEN BELÜLI, lokális importtal éri el
  (`target_exists`) — nincs modul-szintű kereszt-import, konzisztens a
  meglévő mintával.
- `docs/adr/**` valóban érintetlen az implementer commitjaiban (csak az
  orchesztrátor saját, elkülönített commitjaiban).
- `backend/app/community/moderation/**` (Kör 27 tilos zóna) érintetlen.
- Lifecycle: a router `finally` blokkban zárja a DB-sessiont
  (`reports.py:203-207`), konzisztens a `safety.py` mintájával.

## 8. Összegzés

**Nyitott BLOCKER/MAJOR: 0.** F1–F3 MINOR, F4–F5 NOTE — egyik sem
blokkolja a merge-et az ADR 0052 zöld-kapu szabálya szerint. Mivel F1–F3
mindegyike egy-két soros, alacsony kockázatú javítás egy `risk=high` safety
körben (ahol a traceability és a hibaüzenet-pontosság önmagában is a kör
tárgya), **egy rövid javító kört kérek** a normál láncon (ADR 0087 §2 —
"a javító kör a lánc NORMÁL útja, nem megállási ok"), nem follow-up-ként
hagyva őket. A javító kör után a gate-eket + a security-reviewer PASS-t
NEM kell megismételni (F1–F3 egyike sem a security-reviewer scope-jában
talált MAJOR/BLOCKER), de a célzott tesztet és a teljes gate-et igen.

**Állapot ezen jelentés lezárásakor (1. forduló):** CHANGES REQUESTED
(MINOR-only, javító kör folyamatban).

## 9. Javító kör után — végső döntés

**Egy javító kör** (MiniMax M3, ugyanaz a motor), leletlista F1–F3 a
promptban. Eredmény: `status=done`, `head=7dda0de6`,
`summary="F1+F2+F3 fix complete: UUID validation 400,
InvalidExtraMetadata explicit rejection, 5 files ADR 0414→0422 (all 9 gate
steps ZÖLD)"`.

**Leletenkénti zárás-ellenőrzés (a diffet SAJÁT kézzel átolvasva,
`eb6d3868..7dda0de6`):**

| Lelet | Javítás | Teszt, ami PIROSRA fogta volna a réginek |
|---|---|---|
| F1 | `reports.py` router explicit `uuid.UUID(target_id)` validáció + 400, a `target_exists`-be jutás ELŐTT | `test_post_reports_router_malformed_target_id_returns_400` — ÚJ, `"not-a-uuid"`-vel POST-ol, 400-at + `"uuid"` szót vár a `detail`-ben |
| F2 | `EXTRA_METADATA_MAX_KEYS`/`EXTRA_METADATA_MAX_ENCODED_LEN` konstans, `InvalidExtraMetadata` explicit dobás CSONKÍTÁS helyett, router 400-ra képezi | 3 ÚJ teszt: oversize payload elutasítva (NEM csonkolva), túl sok kulcs elutasítva, pontosan a határon elfogadva (boundary) |
| F3 | mind az 5 fájl fejléc-docstringje `ADR 0414` → `ADR 0422`; bónuszként a `report.py` `deleted_at`/`reporter_public_id` kozmetikai docstring-hibák is javítva | nincs teszt (dokumentáció-only, ahogy vártuk) |

**Gate — SAJÁT kézzel, ÚJ izolált klónban, a végleges HEAD-en (`28a53b1a`,
a javító kör `7dda0de6` HEAD-je + a 2. §0.3 upstream-sync merge
`680dc206`-ra):**

- `python3 tools/scope-audit.py --repo ... --brief ... --base 680dc206` →
  13 changed path, 1 flagged (`docs/adr/0422-...` — az orchesztrátor saját
  artefaktuma, lásd §3) — **nincs valódi sértés**.
- `tools/round-gate.sh test/features/community/presentation/report_content_sheet_test.dart`
  → **9/9 ZÖLD** (format, analyze, test, architecture, secrets, l10n,
  backend ruff format, backend ruff check, backend pytest — TELJES suite).
- `cd backend && python -m pytest tests/community/test_report_service.py -q`
  → **25 passed** (21 + 4 új F1/F2 teszt).
- CI (a §0.3 2. sync UTÁN dispatch-elve, exact-SHA `28a53b1a`):
  - Full Gate [32755861667](https://github.com/wolfcasaba/strumsight/actions/runs/32755861667)
    → **success**.
  - Router CI [32755849070](https://github.com/wolfcasaba/strumsight/actions/runs/32755849070)
    → **success**.

A security-reviewer PASS-jét (§6) NEM kellett megismételni — az F1–F3
egyike sem volt a security-reviewer scope-jában talált MAJOR/BLOCKER,
csak a saját (Claude) olvasással talált MINOR leletek zárása.

**Nyitott lelet a merge után: 0.** Minden BLOCKER/MAJOR/MINOR zárva.

**VÉGSŐ DÖNTÉS: APPROVED.** Squash-merge mehet.
