# E12-R29 review — Open Beta és canary cohort

- **Reviewer:** Claude (Opus 5), orchestrátor-szék, ADR 0055 read-only review
- **Implementer:** `sonnet-impl` (Claude Sonnet 5)
- **Branch:** `sonnet-impl/e12-r29-open-beta-and-canary-cohort`
- **Review-HEAD:** `f5631072`
- **Review-klón:** `/tmp/rev-e12-r29` (izolált, eldobható; a fő fán semmi nem módosult)
- **Dátum:** 2026-09-02

## 1. Scope-audit

```
python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e12-r29 \
  --brief docs/rounds/e12-r29-open-beta-and-canary-cohort.md --base 73881871
Legacy scope audit OK (73881871b9a9..f5631072ed30, 5 changed path(s), 0 generated/ignored)
```

Pontosan az engedélyezett öt útvonal változott. A tilos zóna érintetlen —
`git diff origin/main...HEAD -- docs/beta/cohort-profiles.yaml backend/app lib .github docs/adr`
üres.

## 2. Futtatott mércék (a review SAJÁT mérése, nem az implementer bemondása)

| Mérés | Kimenet |
|---|---|
| `pytest tests/test_capacity_guards.py -q` (izolált klón) | `7 passed` |
| `flutter test test/tooling/canary_cohort_test.dart test/tooling/ga_scope_test.dart` | `+37 All tests passed!` |
| Full Gate CI (`full-gate.yml`) | a `f5631072` head SHA-n dispatch-elve, [33620069161](https://github.com/wolfcasaba/strumsight/actions/runs/33620069161) |

### 2.1 Valódi-sértés próbák — a cellák LÖKÉST BÍRNAK

Mind a hét próba az izolált klónban futott, a mutáció után azonnal
visszaállítva:

| Próba (mit rontottam el) | Elvárt | Mért |
|---|---|---|
| `ratelimit.py` `len(q) >= max_attempts` → `False` (throttle kikapcs) | A2 piros | `FAILED …test_a2…[1-429]` ✅ |
| `media_upload_service.py` `size > MAX_UPLOAD_BYTES` → `* 10` | A3 piros | `FAILED …test_a3…[1-True]` ✅ |
| `case_service.py` `report_count *` → `0 *` | A4 piros | `FAILED …test_a4…` ✅ |
| `cohort-profiles.yaml` `closed_beta.migratedLearnEnabled` false→true (szimulált szivárgás, **a VALÓDI fán**, nem temp-fixture-ön) | A5 piros | `+11 -2 Some tests failed` ✅ |
| `open-beta-launch.md` `maxTesters: 25` → `26` | A1 piros | `+11 -2 Some tests failed` ✅ |
| `open-beta-launch.md` `<!-- human-gate:begin -->` törölve | A6/P6 piros | `+12 -1 Some tests failed` ✅ |
| `open-beta-launch.md` `adaptiveShellEnabled` → `adaptiveShellEnabledXX` | P7 piros | `+12 -2 Some tests failed` ✅ |

Az implementer §10-ben dokumentált A5 próbáját reprodukáltam; a mérés egyezik.
A fail-OPEN hibaosztály (L571/L575) ellen a P6 csoport öt cellája ténylegesen
véd: hiányzó marker/fence/szekció **dob**, nem ugrik át.

## 3. Leletek

### MAJOR-1 — a plafon bázis-inputját HAMIS empirikus állítás támasztja alá (`docs/operations/capacity-review.md:128-131`)

```
- `closed_beta.maxTesters = 50` — `docs/beta/cohort-profiles.yaml`, az
  egyetlen cohort-méret ezen a fán, ami ténylegesen ki lett osztva és
  incidens nélkül futott (`docs/beta/closed-beta-launch.md`,
  `docs/HANDOFF.md` E12-R27/R28 kézfogás).
```

**A fán MÉRT valóság ennek az ellenkezője.** `docs/beta/closed-beta-launch.md:3`
→ „**Status: NOT launched**"; `:5` → „The Closed Beta **has NOT launched**"; a
§5 Human launch field üres. A `HANDOFF.md:12-13` (az E12-R28 bejegyzése)
ugyanezt mondja ki. **Egyetlen cohort sem lett kiosztva ezen a fán**, tehát az
50 nem „futott incidens nélkül" — nem futott sehogy.

Ez pontosan az a hibaosztály, ami ellen az előző kör (E12-R28, **ADR 0489 D3**)
gépi őrt épített: *kitalált béta-adat bizonyítékként*. A jelen körben ez a
mondat a kör FŐSZÁMÁNAK (25) bázis-inputját legitimálja — vagyis nem díszítés,
hanem a számítás alátámasztása.

Ráadásul a hivatkozás **útvonala sem oldható fel**: `docs/HANDOFF.md` nem
létezik a fán (`HANDOFF.md` a repó gyökerében van) — `ls docs/HANDOFF.md` →
`No such file or directory`.

**Javítás (a `capacity-review.md` §6 „Bemenetek" blokkjában):** az 50-et
**konfigurációs** tényként kell hivatkozni (a Kör 27 által a
`cohort-profiles.yaml`-ban RÖGZÍTETT, emberi kapura váró cohort-méret), és
kimondani, hogy **üzemi tapasztalat nincs mögötte, mert a Closed Beta MÉRTEN
nem indult el** (`docs/beta/closed-beta-launch.md:3`). A `docs/HANDOFF.md`
hivatkozás helyére a valóban létező `HANDOFF.md` kerüljön.

### MINOR-1 — a plafon-képlet egy BIZTONSÁGI konstanst köt fejszám-politikához

`canary_max = 50 × (register_limiter.max_attempts / login_limiter.max_attempts)`.
A dokumentum §3-ban maga méri ki, hogy a per-key rate limitek **nem** adnak
globális fejszám-plafont, §6-ban és §7-ben pedig kimondottan „óvatossági
operatív plafonnak", nem kapacitás-mérésnek nevezi a 25-öt — ez a
becsületesség tartja a leletet MINOR szinten, nem MAJOR-on.

A megmaradó kockázat gépi: egy jövőbeli kör, amely a `register_limiter`
brute-force küszöbét **biztonsági** okból 4-re szigorítja, ezzel a képlettel a
tesztelői plafont is 20-ra viszi (és pirosra váltja a kaput) — két, egymástól
független döntés mechanikusan összekötve. A kapu fail-closed (a drift mindig
piros), ezért ez nem merge-blokkoló, de a `capacity-review.md` §6-ban
**mondja ki**, hogy a képlet egy jövőbeli, VALÓDI globális kapacitás-mérésig
(kapcsolat-pool, settings-sync átvitel, moderátor-óra) érvényes helyettesítő.

### NOTE-1 — `test/tooling/canary_cohort_test.dart:313` bedrótozott `25`

A „sanity" cella `expect((closedBetaMax * registerMax) ~/ loginMax, 25)`
alakja hardkódolt, miközben az elsődleges cella a konstansokból származtat. Ez
fail-closed (konstans-mozgás → piros), szándékos kipinnelés — csak jegyezve.

### NOTE-2 — a két baseline-térkép (32 flag-érték) kézzel átírt másolat

`_internalBaseline` / `_closedBetaBaseline` a Kör 27 értékeit tükrözi. Egy
jövőbeli, JOGOS cohort-módosítás pirosra váltja az A5 valódi-fa celláját, és a
baseline-t vele együtt kell átírni. Fail-closed, tervezett viselkedés.

## 4. Amit MÉRTEN rendben találtam

- **A4 a MÉRT úton mér** (§0.0 P1): a teszt bizonyítja, hogy `submit_report`
  **nem** nyit ügyet (`list_open_cases` üres a `get_or_create_case` előtt), és
  a `priority_score == 2 × PRIORITY_WEIGHT_REPORT_COUNT` állítás a
  `case_service.py:458-490` képletével egyezik (a triage és a history
  bizonyíthatóan 0 friss ügyre).
- **A2 nem hardkódol**: a cellahármas a `login_limiter.max_attempts`-ból
  számol, a „elfogadva" pedig helyesen `401` (nem 200) — a §0.0 P5 pontosan
  ezt a csapdát célozta.
- **A3 határ-inkluzivitás**: `MAX-1` és `MAX` átmegy, `MAX+1` dob — egyezik a
  `media_upload_service.py:443` mért szemantikájával.
- **P7**: a canary 16 flag-kulcsa mind a mért 40-elemű katalógusban van; a
  kitalált kulcs próbája piros.
- **A6 + emberi kapu**: a dokumentum a betát NEM írja elindítottnak, a Human
  launch field kipipálatlan, és a tiltott múlt idejű fordulatok listája is
  cellával mért.
- **A `cohort-profiles.yaml` érintetlen** — a `ga_scope_test` 16-kulcsos
  cellája ezért zöld maradt (§0.0 P7 indoka igazolva).

## 5. Verdikt

**CHANGES REQUESTED** — 1 MAJOR (MAJOR-1), 1 MINOR (MINOR-1), 2 NOTE.

A javító kör kizárólag a `docs/operations/capacity-review.md` §6 „Bemenetek"
blokkját (és a hozzá tartozó, ha van, ismétlődő megfogalmazást) érinti; a
gépi mércék változatlanok maradnak, mert a leletek egyike sem a cellákat érte.

---

## 6. Javító kör utáni újra-ellenőrzés — 2026-09-02

*(a javító kör után kitöltve)*
