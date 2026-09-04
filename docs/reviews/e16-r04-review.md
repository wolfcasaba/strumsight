# E16-R04 — Review (ADR 0055, read-only)

- **Kör:** `E16-R04` — Élő backend end-to-end: fiók, szinkron, közösség egy eszközön
- **Branch:** `sonnet-impl/e16-r04-live-backend-end-to-end`, head `a47e7789`
- **Implementer:** `sonnet-impl` (Claude Sonnet 5)
- **Reviewer:** Claude (Opus 5, orchestrátor) + `security-reviewer` (KÖTELEZŐ, `risk = "high"`)
- **Alap:** `origin/main` @ `17df4ed7`; az implementer indulási HEAD-je `740ce22c`
  (a pre-flight commit: ADR 0503 + a §0.0.1 revíziók)
- **Diff:** 7 fájl, 1339 sor hozzáadva (a pre-flight ADR-jével együtt 8 fájl)

## VÉGSŐ DÖNTÉS: **APPROVED**

**0 BLOCKER · 0 MAJOR · 1 MINOR · 3 NOTE.** A MINOR és a NOTE-ok nem
blokkolják a merge-et.

---

## 1. Scope-audit — `ok`

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e16-r04 \
    --brief docs/rounds/e16-r04-live-backend-end-to-end.md --base 740ce22c
Legacy scope audit OK (740ce22c329e..a47e77890a0f, 7 changed path(s), 0 generated/ignored)
```

A wrapper saját gépi auditja ugyanezt mérte (`scope_audit=ok`,
`scope_audit_base=740ce22c…`, `scope_audit_changed=7`).

> **Mért false positive, rögzítve a jövőnek:** ugyanez az audit
> `--base 17df4ed7` (azaz `origin/main`) mellett `FAILED`-et ad, egyetlen
> lelettel: `path outside allowed scope: docs/adr/0503-….md`. Ez **nem** az
> implementer sértése — az ADR-t az orchestrátor írta a pre-flightban, és a
> brief §3 kifejezetten ki is mondja, hogy a `docs/adr/**` az implementernek
> tilos, mert „az ADR 0503-at a Claude írta meg a pre-flightban". A helyes
> audit-alap tehát az implementer INDULÁSI HEAD-je (`740ce22c`), nem
> `origin/main`. Aki `origin/main`-ről auditál, a saját pre-flight commitját
> fogja az implementerre olvasni.

**A7 (tilos zóna érintetlen) — igazolva:**

```
$ git diff --stat 17df4ed7..HEAD -- tool/release/production_smoke.py \
    backend/tests/test_production_smoke_contract.py \
    docs/contracts/client-backend-endpoints.json lab_build.json \
    lib/ backend/app/ .github/ tools/
(üres)
```

## 2. Acceptance-kritériumok — leletenként mérve

| # | Kritérium | Verdikt | A MÉRT bizonyíték |
|---|---|---|---|
| A1 | mind a 34 szerződés-bejegyzés besorolva, fail-closed | ✅ | `test_classify_contract_covers_the_real_contract_with_no_unclassified_entries` a VALÓDI fájlt olvassa (`smoke.load_contract(_REAL_CONTRACT_PATH)`), és `by_kind == {"exercised": 10, "not_exercised": 21, "known_gap": 3}`-ot pinnel (34). A `classify_contract` a `known_gap`-et a bejegyzés SAJÁT `status` mezőjéből veszi, nem hardkódolt listából |
| A2 | első eltérésnél nem-nulla kilépés + a lánc MEGÁLL | ✅ | `test_chain_halts_at_the_first_divergence_and_later_steps_never_run` — **számláló kliens** bizonyítja, hogy a későbbi lépések nem is HÍVÓDNAK meg (`counting_client.call_count == 2`), nem csak „nincsenek jelentve" |
| A3 | séma-valid, titokmentes profil + gitignore-lefedés | ✅ | `device_profile_test.dart` az ÉLŐ fából mér: `checkSecrets(projectRoot: repository)` (nem temp-repó, a §0.0.1 R6 szerint) + `git check-ignore` a valódi szabály ellen |
| A4 | a runbook §1–§7 megőrizve, új lépések ellenőrző paranccsal | ✅ | `grep -n "^## "` → §1–§7 változatlan címekkel, `## 8.` és `## 9.` a végén; a Dart cella szerkezetileg pinneli mindkettőt |
| A5 | a gate-cellák hálózat nélkül futnak | ✅ | in-process `TestClient` (ASGI, nincs socket); az egyetlen `main()`-cella `http://127.0.0.1:1`-re mutat, de a besorolás miatt a **kliens létrehozása ELŐTT** lép ki (a `main()` sorrendje: classify/return, majd kliens) |
| A6 | `AppConfig` production fail-closed ágai változatlanok | ✅ | `lib/` érintetlen (A7); `test/app/app_config_test.dart` a célzott kapuban zöld (+21) |
| A7 | `production_smoke.py`, szerződés-JSON, `lab_build.json` változatlan | ✅ | a fenti üres `git diff --stat` |

### 2.1 A vákuum-cella hibaosztály — külön ellenőrizve

Az E12-R31 (a `production_smoke.py` köre) review-ja három MAJOR-t mért
**teljesen zöld gate mellett**, köztük egy „vákuum titok-szivárgási cellát"
(olyan cella, ami semmit nem bizonyít). Ezért a két legfontosabb cellát
nem a nevük, hanem a mechanizmusuk alapján mértem:

- **A2 nem passzolhat rossz okból:** a `main()` exit-2 cellája nem csak a
  kilépési kódot nézi, hanem a `stderr`-t is (`assert "unclassified" in
  captured.err`) — egy connection-refused eredetű 2-es kód tehát NEM
  elégítené ki.
- **A2 „megáll" állítása nem önbevallás:** a `_CountingClient` a hívások
  SZÁMÁT méri, nem a `steps` listát; a lánc nem tudja „elfelejteni
  jelenteni" a lefutott lépéseket.

## 3. A három kötelező valódi-sértés próba

Az implementer mindhármat lefuttatta és a §10.3-ban dokumentálta a MÉRT
kimenettel (a piros cella nevével és az assertion-üzenettel), majd
visszaállította a fát. A visszaállítást magam is ellenőriztem: a
munkapéldány `git status --short` üres, és a hat termékfájl diffje
megegyezik a commitolttal.

## 4. Biztonsági review (`security-reviewer`, `risk = "high"`) — 0 BLOCKER / 0 MAJOR

Hét mérési ponton futott: titok-szivárgás, `.gitignore`-lefedés,
titok a folyamat-listában/logban, séma/transport, fiók-kezelés,
hálózat-mentesség, runbook. Kiemelt megállapítások:

- **Nincs credential-argumentum.** A smoke futásonként friss, eldobható
  fiókot regisztrál, ezért a `production_smoke.py` `--password-env`
  felülete strukturálisan eltűnt — nincs mit a `ps`-be vagy a
  shell-history-ba szivárogtatni.
- **A válasz-törzs sosem printelt**, egyetlen kivétellel: a `/health/ready`
  `reason` mezője (zárt kódhalmaz, nem titok — ADR 0449 D1).
- **A redirect-követés blokkolt** (`_NoRedirectHandler.redirect_request →
  None`), ugyanúgy, mint a precedensben.
- **A `http` engedése kimondott és korlátozott döntés** (ADR 0503 D3): a
  `_scheme_error` minden más sémát fail-closed elutasít (exit 2). Nem néma
  védelemvesztés.
- **A generált jelszó CSPRNG-alapú** (`uuid.uuid4()` → `os.urandom(16)`,
  122 bit).

## 5. Leletek

### MINOR-1 — a `.gitignore` mintája a trackelt példa-fájlra is illeszkedik

`.gitignore:93` `device_build.*.json` **literálisan illeszkedik** a
trackelt `device_build.example.json`-ra is:

```
$ git check-ignore -v --no-index device_build.example.json
.gitignore:93:device_build.*.json	device_build.example.json
$ git check-ignore -v device_build.example.json ; echo "exit=$?"
exit=1                     # trackelt utat a check-ignore alapból kihagy
```

**Ma működik**, mert a fájl trackelt (a gitignore csak a nem-trackelt utakra
hat), és a valódi profil minden névvariánsa ki van zárva (mérve:
`device_build.json`, `.local.`, `.prod.`, `.lab.` → mind IGNORED). A
kockázat latens: ha a példa valaha kikerül az indexből (pl. egy
`git rm --cached` egy refaktor közben), **némán** követhetetlenné válik.

**Javaslat (nem blokkoló, külön kör vagy egy jövőbeli érintés):** egy
`!device_build.example.json` negáció a két sor után. Nem kényszerítem ki
ebben a körben: a szabály funkcionálisan helyes, a szándékot a fölötte lévő
komment kimondja, és van rá gépi őr (`device_profile_test.dart`
`git check-ignore` cellája).

### NOTE-1 — `uuid.uuid4()` a `secrets` modul helyett

`live_backend_smoke.py:809`. Kriptográfiailag megfelelő (`os.urandom`),
csak kevésbé idiomatikus, mint a `secrets.token_urlsafe`. Nincs
sebezhetőség.

### NOTE-2 — a smoke minden futása fiókot hagy a lab-szerveren

Nincs teardown-lépés. Dev/lab higiéniai kérdés, nem termékhatár-sértés; egy
jövőbeli kör megfontolhat egy záró törlést (ma nincs hozzá
kliens-szerződésben szereplő delete-végpont).

### NOTE-3 — az A1 cella szám-pinnelése szándékosan törékeny

A `by_kind == {"exercised": 10, "not_exercised": 21, "known_gap": 3}`
állítás minden szerződés-változásra pirosra vált. Ez **nem hiba**, hanem az
ADR 0503 D1 célja: egy új kliens-végpont besorolás nélkül nem csúszhat át.
Itt csak azért rögzítem, hogy egy jövőbeli kör ne „flaky tesztként" lazítsa
fel.

## 6. Az implementer-futás megszakadásáról (nem lelet)

A `sonnet-impl` futást a wrapper 3600 s-es abszolút időkorlátja ölte meg
(`status=timeout`, `head=822d156e`, `dirty_files=1`) — **a §10 handoff
kiírása közben**, miközben a teljes backend-suite-ot futtatta újra egyetlen
szám ellenőrzéséért. A kör érdemi munkája ekkor már kész és commitolt volt,
a `tools/round-gate.sh` 10/10 zölddel lefutott, a scope-audit `ok` volt. Az
orchestrátor a munkafán maradt §10-et (engedélyezett fájl, kész tartalom)
ellenőrizte és commitolta (`a47e7789`). **Nem H6:** ez az első és egyetlen
megszakadás ezen a körön, és nem `blocked` jelzés.

## 7. Merge-feltételek

- [x] scope-audit `ok` (a helyes bázison)
- [x] célzott kapu 10/10 zöld a munkapéldányon
- [x] read-only review, 0 BLOCKER / 0 MAJOR
- [x] `security-reviewer` lefutott (kötelező, `risk = "high"`), 0 BLOCKER / 0 MAJOR
- [ ] exact-SHA CI (Full Gate + Router CI) a merge SHA-n — az orchestrátor méri
