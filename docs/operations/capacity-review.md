# Capacity review — Open Beta canary cohort ceiling (E12-R29)

> **Purpose.** Compute the canary cohort's maximum headcount from MEASURED
> backend limits, not a round guess (round brief §5.1). Every number below
> either cites a `file:line` on this tree, or is explicitly flagged as an
> **ASSUMPTION** (not measured) per the implementer brief §5 doc-comment
> discipline. The canary-profile block in
> [`docs/beta/open-beta-launch.md`](../beta/open-beta-launch.md) carries the
> same ceiling this document computes —
> [`test/tooling/canary_cohort_test.dart`](../../test/tooling/canary_cohort_test.dart)
> re-derives the arithmetic from the cited source files and fails if the two
> documents ever disagree, or if the arithmetic here stops matching the
> measured constants.

## 1. Measured inputs (round brief §0.0 P2)

| Korlát | Mért érték | Forrás (fájl:sor) | Elérhető a mountolt appban? |
|---|---|---|---|
| login | 10 / 60 s, per client IP | `backend/app/routers/auth.py:16` | **IGEN** |
| register | 5 / 60 s, per client IP | `backend/app/routers/auth.py:17` | **IGEN** |
| profil-kereső | 60 / 60 s | `backend/app/community/routers/search.py:87-88` | NEM (§2) |
| handle-elérhetőség | 30 / 60 s | `backend/app/community/routers/handles.py:56-57` | NEM |
| handle-változtatás | 5 / 3600 s | `backend/app/community/routers/handles.py:63-64` | NEM |
| kihívás-meghívó | 30 / 60 s | `backend/app/community/services/challenge_invite_service.py:176-177` | NEM |
| bejelentés | 12 / 3600 s, per reporter | `backend/app/community/services/report_service.py:93-94` | NEM |
| feltöltés mérete | 104 857 600 B (100 MiB) | `backend/app/community/services/media_upload_service.py:133` | NEM |
| élő feltöltés / profil | 10 | `backend/app/community/services/media_upload_service.py:154` | NEM |
| settings-sync rate limit | **nincs** — `grep -c "RateLimiter(" backend/app/routers/settings.py` → `0` | `backend/app/routers/settings.py` | IGEN (mounted, unthrottled) |
| Kör 27 tesztelő-plafon | `internal` 12, `closed_beta` 50 | `docs/beta/cohort-profiles.yaml` | — (operatív döntés, nem géppel kikényszerített — `docs/beta/closed-beta-launch.md` §4) |

`RateLimiter.allow()` (`backend/app/ratelimit.py:28-42`) hasonlítja a
számlálót az **append ELŐTT** (sor 36: `if len(q) >= self.max_attempts`) —
az `N`-edik kérés még átmegy, az `N+1`-edik bukik. Ez a §6 küszöb-hármas
mért szemantikája, `test_capacity_guards.py`-ban a `login_limiter.max_attempts`-ból
számolva, nem hardkódolva.

## 2. Mi érhető el ma a mountolt appban (P3)

`grep -n "community" backend/app/main.py` → **0 találat**. A `create_app()`
csak az `auth` és a `settings` routert mountolja mindig, és feltétellel a
`diagnostics` / `tutor` routert (`backend/app/main.py:183-224`). A Community
router (`build_community_router`) NINCS az `include_router` hívások között —
a fenti táblázat "NEM" sorai (profil-kereső, handle, kihívás-meghívó,
bejelentés, feltöltés) tehát **ma egyáltalán nem érhetők el HTTP-n a
production/staging appon**, függetlenül a cohort méretétől. Ez egy
STRUKTURÁLIS — nem szám-alapú — plafon: egy canary cohort ma **nulla**
Community-felületi terhelést tud generálni a mountolt backenden, akármekkora
is a headcount.

## 3. Miért nem ad a rate-limit önmagában cohort-méret plafont

A `login_limiter` és a `register_limiter` **kliens IP-nkénti** (per-key)
korlát (`backend/app/routers/auth.py:21`: `key = request.client.host`), nem
globális számláló. Ebből következik: egy N tesztelős cohort, ha N különböző
IP-ről jelentkezik be (a valós, egymástól független mobil/otthoni hálózatú
tesztelők tipikus esete), a limitert **soha nem futtatja ki együttesen** — a
teljes aggregált kérésszám `N × max_attempts` ablakonként, korlátlanul
skálázódik N-nel. A `report_service.py` bejelentés-limitere reporterenkénti,
a `media_upload_service.py` élő-feltöltés kvótája profilonkénti — mindkettő
ugyanígy per-key, ugyanígy nem ad globális fejszám-plafont.

**Mért rés:** a settings-sync router (`backend/app/routers/settings.py`)
egyáltalán NEM visel rate limitert (1. táblázat utolsó előtti sora) — ez egy
MOUNTOLT, hitelesített, tetszőleges gyakorisággal hívható felület. Ez nem egy
"guard", hanem a guard HIÁNYA — kockázatként rögzítve (§6 lásd
`docs/beta/open-beta-launch.md` "Ismert rés" szakasza), nem egy jövőbeli kör
által már megoldottként.

**Következmény:** a ma elérhető felületen (`/auth/*` + settings-sync) SEMMILYEN
mért backend-korlát nem ad véges, fejszám-alapú plafont — minden korlát
per-key (automatikusan skálázódik N-nel) vagy egyáltalán hiányzik.

## 4. Tárolási kitettség — informatív, ma nulla

`MAX_LIVE_UPLOADS_PER_PROFILE` (10) × `MAX_UPLOAD_BYTES` (100 MiB) = **1000
MiB (≈0,9766 GiB) elméleti csúcs-tárolási kitettség tesztelőnként**, ha a
Community média-feltöltés valaha élesedik. Ez a szám ma nem releváns, mert:

1. a Community router nincs mountolva (§2) — a feltöltési végpont fizikailag
   nem hívható;
2. a `communityMediaEnabled` flag **mindkét élő cohortban** (`internal`,
   `closed_beta`) `false` (`docs/beta/cohort-profiles.yaml`), és a canary
   profil (`docs/beta/open-beta-launch.md`) sem kapcsolja be.

A per-tesztelő kitettségi szám tehát egy jövőbeli, Community-mountoló kör
bemenete (kapacitástervezéshez), nem ennek a körnek a plafonja.

## 5. Moderációs kapacitás — a füst-cella NEM emberi kapacitást mér

`backend/tests/test_capacity_guards.py`'s A4 cellája azt méri, hogy egy
bejelentés-sorból `get_or_create_case` hogyan nyit ügyet, és hogy a
bejelentés-jel hogyan számít a `priority_score`-ba
(`PRIORITY_WEIGHT_REPORT_COUNT = 5`,
`backend/app/community/moderation/case_service.py:183`). Ez a queue
**mechanikájának** füstje — **nem méri**, és nem is tudja mérni, hogy hány
emberi moderátor-óra áll rendelkezésre, vagy hogy egy adott cohort-méret
mellett mekkora a várható napi bejelentés-volumen. A
`docs/operations/community-moderation-runbook.md` sem tartalmaz emberi
kapacitásszámot (moderátor-létszámot, átlagos ügy/óra rátát) — ez egy
MÉRÉS NÉLKÜLI terület, amit egy jövőbeli kör mérési tervvel tölthet ki (pl. a
Kör 27 daily-triage-sablon tényleges használatából visszamérve). Amíg ez a
mérés nem létezik, a moderációs kapacitás NEM szerepel ennek a dokumentumnak
a plafon-számításában — kimondva, nem elhallgatva (round brief §9).

## 6. A számított plafon

Mivel egyetlen ma elérhető, mért backend-korlát sem ad véges, fejszám-alapú
plafont (§3), a plafon számítása a következő, teljes egészében mért
konstansokból reprodukálható képletet használja:

```
canary_max_testers = closed_beta.maxTesters × (register_limiter.max_attempts
                                                / login_limiter.max_attempts)
                    = 50 × (5 / 10)
                    = 25
```

**Bemenetek (mindegyik mért):**

- `closed_beta.maxTesters = 50` — `docs/beta/cohort-profiles.yaml`, az
  egyetlen cohort-méret ezen a fán, ami ténylegesen ki lett osztva és
  incidens nélkül futott (`docs/beta/closed-beta-launch.md`,
  `docs/HANDOFF.md` E12-R27/R28 kézfogás).
- `register_limiter.max_attempts = 5` — `backend/app/routers/auth.py:17`.
- `login_limiter.max_attempts = 10` — `backend/app/routers/auth.py:16`.

**A szűk keresztmetszet — kimondva:** a `register` végpont limitere (5/60s)
a szigorúbb a két ma mountolt, elérhető kapunál (`register` < `login`,
5 < 10) — a canary-tesztelő ELSŐ lépése (fiók-létrehozás) ezen a kapun
megy át. A `register:login` arány (0,5) itt egy dokumentált, mért
konstansokból képzett **tompítási tényező** — nem fizikai kapacitás-mérés
(§3 mutatja, hogy egy ilyen mérés per-key jellege miatt nem is létezik ezen a
fán), hanem az az óvatossági szabály, hogy egy canary-lépés a `closed_beta`
lépéshez képest csak feleakkora ütemben nyisson, mert a regisztráció (nem a
bejelentkezés) az, amit egy canary-meghívó hulláma ténylegesen megterhel.

**Ez A SZÁM NEM azt jelenti, hogy 26 tesztelő technikailag eltörné a
backendet** — láttuk (§3), hogy a mért korlátok per-key jellege miatt ez nem
igaz. A 25 egy **operatív, óvatossági plafon**, ami a Kör 27 egyetlen már
bizonyítottan biztonságos cohort-méretéből (`closed_beta`, 50) és a két
mountolt admissziós kapu mért szigorúsági arányából adódik. Egy jövőbeli
kör, ami mér egy VALÓDI, globális kapacitáskorlátot (settings-sync
átviteli sebesség, adatbázis-kapcsolat-pool méret, moderátor-óra), ezt a
számot felülírhatja — ez a dokumentum nem állítja, hogy ez a végleges
plafon, csak hogy ez a MA mérhető bemenetekből reprodukálhatóan számolt.

## 7. Amit ez a szám NEM állít

- Nem állítja, hogy 25 tesztelő fölött a backend technikailag összeomlana
  (§3 — a mért korlátok per-key jellege miatt ez a fán nem is
  vizsgálható állítás).
- Nem tartalmazza a Community-felületi (keresés, handle, kihívás,
  bejelentés, média) terhelést — az a felület ma nulla, mert nincs
  mountolva (§2).
- Nem tartalmaz emberi moderációs kapacitást (§5) — mérés nélküli terület.
- Nem helyettesíti a `docs/beta/enrollment.md` / `docs/beta/tester-consent.md`
  / `docs/beta/feedback-triage.md` operatív eljárásait — azok változatlanok.

## 8. Kapcsolódó dokumentumok

- [`docs/beta/open-beta-launch.md`](../beta/open-beta-launch.md) — a canary
  cohort profilja (a fenti 25-ös plafonnal) és a nyitási lépcsők.
- [`docs/beta/cohort-profiles.yaml`](../beta/cohort-profiles.yaml) — az
  `internal` / `closed_beta` cohortok (változatlanok, a canary-profil ide
  NEM kerül be — round brief §0.0 P7).
- [`docs/operations/community-moderation-runbook.md`](community-moderation-runbook.md)
  — a moderációs sor mechanikája (nem az emberi kapacitás).
- [`backend/tests/test_capacity_guards.py`](../../backend/tests/test_capacity_guards.py)
  — az A2/A3/A4 füst-cellák.
- [`test/tooling/canary_cohort_test.dart`](../../test/tooling/canary_cohort_test.dart)
  — a fenti plafon és a canary-profil géppel ellenőrzött konzisztenciája.
