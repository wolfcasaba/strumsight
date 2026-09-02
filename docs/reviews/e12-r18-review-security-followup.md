<!-- strumsight:allow-secret-file — a jelentés a kör SZINTETIKUS fixture-jét
     idézheti bizonyítékként; precedens: test/tooling/check_secrets_test.dart:1. -->

# E12-R18 — Biztonsági review, zárás-ellenőrzés (follow-up)

Reviewer: Claude (security-reviewer, Opus 5) · Dátum: 2026-08-29 · Kockázat: **high**
Friss klón: `/tmp/review2-e12-r18` · HEAD `32ed9cae` · javító commit `4783c9f7`
Első jelentés: `docs/reviews/e12-r18-review-security.md` (a `23fa5f22` HEAD-en mérve)
Módszer: **minden saját korábbi piros utamat újra futtattam a javított fán**, plusz
mutation-kill (a régi eszköz/dokumentum visszatétele az ÚJ cellák alá).

## Verdikt

**APPROVED.**

A hét átadott lelet mind ZÁRVA — mindegyiket a SAJÁT, korábban zöld
támadásommal mértem újra, és mind PIROS lett. Regresszió a korábban rendben
lévő hat ponton nincs. A merge-et nem blokkolom.

Két **új** leletet írok elő follow-upra (egyik sem nyitja vissza az átadott
hetet, egyik sem §5 termékhatár-sértés):

| # | Súlyosság | Tárgy |
|---|---|---|
| **S8** | MAJOR (latens) | fájl- és group-szintű elnémítás (`pytestmark = pytest.mark.skip`, Dart `@Skip(...)` library-annotáció, `group(..., skip: true)`) MOST is zöld — a MAJOR-2 hibaosztály szűkebb, de valósabb vektora |
| **S9** | MINOR | a MAJOR-4 javításának NINCS piros útja: a `T-CLIENT-01` guard visszaállítása a gyengébb célra teljesen zöld (37/37) |

Nyitott, de a koordinátor által ebből a körből KIVETT (nem regresszió):
MINOR-4 (`--format json` futás-metaadat) és MINOR-5 (advisory-tartomány).

**Miért nem CHANGES REQUESTED az S8-tól:** a scan ebben a körben szándékosan
NINCS CI-be kötve (§0.1) — ma még nem release-döntés. Az S8 zárása kötelező
a Kör 25-ös bekötés ELŐTT, mert a scan saját docstringje
(`tool/release/security_scan.py:12-15`) ma azt állítja, hogy a megnevezett
teszt „present, uncommented, and not `skip`/`xfail`-marked" — ez fájl-szintű
elnémításnál mérhetően nem igaz.

**Nyitott leletek darabszáma:** CRITICAL 0 · BLOCKER 0 · **MAJOR 1 (új, latens)** ·
MINOR 3 (1 új + 2 szándékosan halasztott) · NOTE 0.

---

## Leletenkénti zárás

### MAJOR-1 — kivétel-bejegyzés kikapcsolja a `secrets` ágat → **ZÁRVA**

A javítás három, egymástól független rétegben zárja: kötelező `branch` mező,
`secrets` nem szerepel az `_EXCEPTABLE_BRANCHES`-ben, és a `secrets` ág
egyáltalán nem hívja a `_apply_exceptions`-t
(`tool/release/security_scan.py:986-990`).

**[1a] a saját, eredeti payloadom (nincs `branch` mező), `--secrets-cmd /bin/false`:**

```
$ python3 tool/release/security_scan.py --exceptions f_exc_secrets_old.yaml --secrets-cmd /bin/false
security_scan: 3 finding(s).
- [critical] exceptions: exceptions[0] is missing required field(s) ['branch'] … (exceptions.missing-field)
- [critical] exceptions: exceptions[1] is missing required field(s) ['branch'] … (exceptions.missing-field)
- [critical] secrets: secrets delegate command '/bin/false' exited 1:  (secrets.delegate-failed)
EXIT=1
```

**[1b] ugyanaz `branch: secrets`-szel** → `exceptions.invalid-branch` × 2 + a
titok-lelet megmarad, **EXIT=1**.

**[1c] a titok-lelet id-je ENGEDÉLYEZETT ág alá csempészve**
(`branch: guards`, illetve `branch: dependencies`):

```
security_scan: 1 finding(s).
- [critical] secrets: secrets delegate command '/bin/false' exited 1:  (secrets.delegate-failed)
EXIT=1
```

**[1d] nem futtatható delegált + ugyanez a payload** → `secrets.delegate-unavailable`,
**EXIT=1**.

**A `branch` mező tényleg kötelező:** hiánya `exceptions.missing-field`
kritikus lelet ([1a]), ismeretlen értéke `exceptions.invalid-branch` ([1b]) —
nem csendben figyelmen kívül hagyott mező.

**Ág-szigetelés (a `guards` oldal, ahol a kivétel a D4 szerint MEGMARAD):**

```
[1e] elrontott T-DIAG-01 guard, nincs kivétel                → EXIT=1 (critical)
[1f] + kivétel `branch: dependencies` (rossz ág)             → EXIT=1 (critical)  ← nem nyeli el
[1g] + kivétel `branch: guards` (a tervezett kockázatvállalás) → EXIT=0
```

Az [1g] ág **szándékos és most már őszintén dokumentált** (docstring
`:47-53`, `exceptions.yaml:13-22`): egyetlen, owner-rel és lejárattal
ellátott, ÁG-RA és KONKRÉT guard-id-re szűkített bejegyzés — nem a korábbi,
branch-szintű konstans (`secrets.delegate-failed`), amely egyetlen sorral az
egész titok-kaput kapcsolta volna ki.

### MAJOR-2 — a guard „létezése" nyers substring → **ZÁRVA** (mindhárom eredeti forgatókönyv PIROS)

Mind a négy általam mért evázió MOST kritikus lelet
(`--only guards`, a threat model érintetlen, minden próba után
`git checkout -- <fájl>`, a fa a végén tiszta):

```
[2a] @pytest.mark.skip a test_diagnostics_session_id_cannot_escape_data_dir fölé
- [critical] guards: T-DIAG-01 (diagnostics-upload): guard.test '…' is present but
  disabled (skip/xfail marker) in backend/tests/test_diagnostics.py … (T-DIAG-01)   EXIT=1

[2b1] check_secrets_test.dart — a test( fej kikommentelve
- [critical] guards: T-RELEASE-02 (release-chain): guard.test '…' not found …        EXIT=1

[2b2] vision_model_integrity_test.dart — a törzs törölve, a név csak TODO-kommentben
- [critical] guards: T-MODEL-01 (model-package): guard.test '…' not found …          EXIT=1

[2c] pytest prefix-átnevezés (…_expired_signed_url( → …_expired_signed_url_v2()
- [critical] guards: T-MEDIA-01 (community-media-upload): guard.test '…' not found …  EXIT=1
```

A mechanizmus valódi (nem string-tuning): `_strip_python_trivia` /
`_strip_dart_comments` (`:390-448`), zárt python-tű `def <név>(`
(`:451-460`), és a Dart `test('…')` hívás paraméter-fesztávján keresett
`skip:` (`:463-513`). **Új képesség, amit külön mértem:** a szomszédos
string-literálokra tördelt teszt-nevet (`T-EGRESS-02` valós alakja) a parser
összefűzve oldja fel — ez a `check_guards` valós fán mért 0 leletében látszik.

**Új, azonos osztályú residuum → S8 (lásd lent).**

### MAJOR-3 — hiányzó §5 határ (egress + consent) → **ZÁRVA**

A modell 14 → **18** guardra nőtt; a `client-egress` komponens két
`release_gate: true` guarddal került be, plusz a kért `T-DIAG-03` token-kapu
és a `T-API-02` DoS-sor. **Minden új `path`+`test` párost egyenként
feloldottam a fán** (a scan saját parserével + `grep`):

| id | komponens | guard.path | feloldás |
|---|---|---|---|
| `T-API-02` | backend-api | `backend/tests/test_hardening.py` | :43 `def test_login_brute_force_gets_429_with_retry_after(self, client)` |
| `T-DIAG-03` | diagnostics-upload | `backend/tests/test_diagnostics.py` | :64 `def test_diagnostics_rejects_bad_token(...)` |
| `T-EGRESS-01` | client-egress | `test/privacy/consent_enforcement_test.dart` | :145 `'upload() with consent false never touches the wire adapter'` |
| `T-EGRESS-02` | client-egress | `test/privacy/consent_enforcement_test.dart` | :230-232 (két literálra tördelt név, `'a profile update sent while signed in reaches the wire; the same '` + `'call after logout does not — same container, no restart (A6)'`) |
| `T-CLIENT-01` | client-storage | `test/features/auth/token_store_test.dart` | :45 `test('round-trips a token under the documented secure key', …)` |

Elgépelt guard-név nincs: `check_guards(entries, root)` a valós fán **üres
lista**, és a 18 blokk validációs leletlistája is üres.

**Szemantikai illeszkedés (nem csak feloldhatóság) — kimért:**
`T-EGRESS-01` a `diagnosticsConsentProvider = false` mellett NYERS
audio-mintát (`const [0.1]`, 44100) ad át és `expect(probe.requests, isEmpty)`
(consent_enforcement_test.dart:145-174) — pontosan az AGENTS.md §5.1 határ.
`T-EGRESS-02` kijelentkezés utáni wire-kérés hiányát méri ugyanabban a
konténerben (§5.2). `T-API-02` valóban a login-throttle 429/`Retry-After`
cellája. `T-DIAG-03` a `X-Diag-Token` `hmac.compare_digest` kapuját méri.

### MAJOR-4 — a `T-CLIENT-01` guard nem a fenyegetést mérte → **ZÁRVA** (mérce nélkül, lásd S9)

A guard átirányítva `test/features/auth/token_store_test.dart:45`-re, amely a
token TÉNYLEGES útját méri (`expect(secure.values[StorageKeys.secureAuthToken],
'jwt-1')` + `expect(secure.keysTouched, everyElement(StorageKeys.secureAuthToken))`)
— nem egy generikus write→read→delete kör.

A doksi többé nem állít mértnek nem mértet: az „egyetlen
`flutter_secure_storage` import" állítás átkerült egy kimondottan
**„Nem mért feltevés (jövőbeli kör tárgya, NEM guard-dal őrzött)"** blokkba
(`docs/security/threat-model.md:87-97`), a mérési helyzet (az
`architecture_dependency_test.dart` csak a gamification/community DOMAIN
rétegre tiltja) néven nevezve. Ez pontosan az a fajta lefokozás, amit kértem.

### MINOR-1 — `guard.path` kiléphet a repóból → **ZÁRVA**

```
$ python3 tool/release/security_scan.py --only guards --threat-model f_tm_escape.md
- [critical] guards: T-ESCAPE-01 (diagnostics-upload): guard.path escapes the repo root: /etc/hostname
- [critical] guards: T-ESCAPE-02 (backend-api): guard.path escapes the repo root: ../../../../etc/hosts
EXIT=1
```

(`resolve()` + `is_relative_to(resolved_root)`, `:305-318`.)

### MINOR-2 — a `release_gate` átbillentése néma → **ZÁRVA** (két rétegben)

```
$ sed 's/^release_gate: true$/release_gate: false/' docs/security/threat-model.md > f_tm_off.md   # 18 találat
$ python3 tool/release/security_scan.py --only guards --threat-model f_tm_off.md
- [critical] guards: the threat model has zero `release_gate: true` guard blocks … (guards.no-release-gate-entries)
EXIT=1
```

Emellett az új `MINOR-2` cella
(`test/tooling/security_scan_test.dart:832-874`) mind a 18 id-re megköveteli
az `id` + `release_gate: true` blokkot — tehát EGYETLEN sor átbillentése is
piros, nem csak a mind a 18-é (a régi A8 komponens-substring ezt nem fedte).

### MINOR-3 — jelen lévő, de guard nélküli threat model → **ZÁRVA**

```
$ python3 tool/release/security_scan.py --only guards --threat-model f_tm_empty.md   # ```text fence
- [critical] guards: the threat model has zero `release_gate: true` guard blocks … EXIT=1
$ …--threat-model f_tm_gatefalse.md   # csak release_gate: false blokkok
- [critical] guards: … EXIT=1
```

---

## Van-e minden javításhoz piros út? (a kör saját ADR 0481 D2 mércéje)

**Mutation-kill 1 — a RÉGI eszköz az ÚJ cellák alatt**
(`git checkout 23fa5f22 -- tool/release/security_scan.py`,
`flutter test test/tooling/security_scan_test.dart`, majd
`git checkout HEAD -- …` + `git reset`):

```
00:03 +24 -13: Some tests failed.
```

A 13 piros cella pontosan a javításokat fedi: MAJOR-1 ×4 (secrets nem
elnyelhető / `branch` kötelező / ismeretlen ág / kereszt-ág), MAJOR-2 ×5
(skip-marker, kikommentelt Dart, python utótag-átnevezés, Dart `skip:`
argumentum, tördelt név feloldása), MINOR-1 ×2, MINOR-3 ×1, és az A8
„a valós modell exit 0" cella (a szállított doksi és az új parser
összekötése). A MAJOR-1 „a `branch: guards` kivétel TOVÁBBRA is elnyeli a
guard-leletet" cellája a régi eszközön is zöld — helyesen, mert ez a
megtartott D4-viselkedés.

**Mutation-kill 2 — a RÉGI dokumentum az ÚJ cellák alatt**
(`git checkout 23fa5f22 -- docs/security/threat-model.md`):

```
$ python3 tool/release/security_scan.py --only guards      → EXIT=0   (a scan maga nem veszi észre)
$ flutter test test/tooling/security_scan_test.dart
00:03 +34 -2: MINOR-2 … each known id resolves to id + release_gate: true, in order [E]
             A8 … every component in the real threat model has at least one guard id [E]
Some tests failed.
```

Tehát a MAJOR-3 tartalmi bővítésének **van** piros útja (a 18-elemű id-lista
és a `client-egress` komponens-cella).

**Ahol NINCS piros út → S9:** a MAJOR-4 javítása. A `T-CLIENT-01` guardot
visszaállítva a pre-fix célra
(`path: test/core/storage/secure_store_test.dart`, `test: round-trips a secret`)
minden zöld:

```
$ python3 tool/release/security_scan.py --only guards          → EXIT=0
$ flutter test test/tooling/security_scan_test.dart            → 00:03 +37: All tests passed!
```

Ez természetes korlát (a guard *minőségét* gépileg nehéz mérni), de ki kell
mondani: a MAJOR-4 javítása ítélet, nem mérce — egy jövőbeli kör
visszagyengítheti anélkül, hogy bármi pirosodna.

---

## S8 (ÚJ, MAJOR-latens) — fájl- és group-szintű elnémítás továbbra is zöld

**Hely:** `tool/release/security_scan.py:378-386` (`_PY_SKIP_MARKERS`,
`_DART_SKIP_MARKERS`), `:451-460` (400 karakteres python prelude-ablak),
`:495-511` (Dart: csak a `test(` hívás fesztávja + 200 karakter fölötte).

**Failure scenario 1 — pytest modul-szintű `pytestmark` (egy sor, HÁROM guardot némít):**

```
# backend/tests/test_diagnostics.py tetejére: pytestmark = pytest.mark.skip(reason='whole file disabled')
$ python3 tool/release/security_scan.py --only guards
security_scan: OK — no critical or fatal finding.      SCAN_EXIT=0
$ cd backend && python3 -m pytest tests/test_diagnostics.py -q
sssssssssssss                                                   [100%]
$ python3 -m pytest tests/test_security_release.py -q            # az A9 keresztmérés is
............                                                    [100%]   (12 passed)
```

A `T-DIAG-01` (path traversal), `T-DIAG-02` (oversize) és `T-DIAG-03`
(token-kapu) egyszerre néma, a kapu OK-t mond. Az A9 sem fogja meg: a
`pytest --collect-only` a `skip`-elt teszteket is BEGYŰJTI.

**Failure scenario 2 — Dart library-szintű `@Skip`:**

```
# test/tooling/vision_model_integrity_test.dart tetejére: @Skip('whole file disabled')\nlibrary;
$ python3 tool/release/security_scan.py --only guards   → EXIT=0
```

**Failure scenario 3 — Dart `group(..., skip: true)` a guard-teszt körül:**

```
# check_secrets_test.dart: group('disabled', skip: true, () { test('flags provider token literals …
$ python3 tool/release/security_scan.py --only guards   → EXIT=0
```

(Mindhárom után `git checkout -- <fájl>`; a fa tiszta.)

**Sértett szabály.** ADR 0481 D2 + a scan saját docstringje
(`:12-15`: „that test is present, uncommented, and not `skip`/`xfail`-marked").
A fájl-szintű karantén (`pytestmark`, `@Skip`) a leggyakoribb „flaky, majd
visszatesszük" idióma — épp az a vektor, amit a MAJOR-2 javítása le akart
zárni.

**Javasolt irány (olcsó).** (a) `_PY_SKIP_MARKERS` + fájl-szintű ellenőrzés:
`pytestmark` sor `mark.skip`/`mark.xfail`-lel bárhol a modulban → a fájl
minden guardja `disabled`. (b) Dart: `@Skip(` a fájl fejlécében (nem csak a
teszt fölött 200 karakteren belül) és a befoglaló `group(` `skip:`
argumentuma. (c) A Dart-oldali kereszt-cella
(`security_scan_test.dart:738-782`) ugyanezt tükrözze.

## S9 (ÚJ, MINOR) — a MAJOR-4 javításának nincs mércéje

Lásd fent a mérést (guard visszagyengítve → 37/37 zöld). Javasolt irány: a
`MINOR-2` id-cella bővítése a szállított `guard.path` (és ahol számít:
`guard.test`) párra, hogy a guard-cél csendes visszagyengítése is pirosodjon —
ez ugyanaz az „ismert lista a szállított dokumentumra" minta, ami már működik.

---

## Nem lazult-e valami? (a korábban RENDBEN lévő hat pont)

| # | Ellenőrzés | Mért eredmény MOST |
|---|---|---|
| 1 | A1 nem vak scanner | temp git-fán újraépítve: a `sk-…` literállal `lib/leaked.dart:1: provider token literal`, **EXIT=1**; negatív kontroll (literál kicserélve) **EXIT=0**. Az érték most sem jelenik meg. |
| 2 | fail-closed 0/1/2 | hiányzó threat model / exceptions / requirements → **2**, hibás `--today` → **2**, `/bin/false` secrets → **1**, valós fa → **0**. `--force`/`--no-fail` kapcsoló nincs; a „skipped" szó sehol nem besorolás. |
| 3 | inkluzív lejárat-határ | `--today 2026-08-29`: `expires 2026-08-28` → EXIT=1 (`exceptions.expired`), `2026-08-29` → EXIT=0, `2026-08-30` → EXIT=0 (az új kötelező `branch: guards` mezővel). |
| 4 | `fatal` és `exceptions.expired` nem elnyelhető | élő `finding: guards.input-error` mellett hiányzó modell → **EXIT=2**; élő `finding: exceptions.expired` mellett 2020-as bejegyzés → **EXIT=1**. |
| 5 | nincs duplikáció | `backend/tests/test_security_release.py` továbbra is a scan modulját tölti be és csak `pytest --collect-only`-t futtat; az új `_resolve_node_id` a valós node-idet listázza (osztályba ágyazott `T-API-02` miatt), nem ír újra viselkedést. `12 passed`. |
| 6 | nincs termékkód-érintés | a javító commit fájljai: `tool/release/security_scan.py`, `test/tooling/security_scan_test.dart`, `backend/tests/test_security_release.py`, `docs/security/{threat-model.md,exceptions.yaml}`, `docs/rounds/…`, `docs/reviews/…` — `lib/**` és `backend/app/**` érintetlen. |

Zöld alapállapot a javított fán (saját futás): `flutter test
test/tooling/security_scan_test.dart` → **`00:03 +37: All tests passed!`**;
`python3 -m pytest tests/test_security_release.py -q` → **12 passed**;
`python3 tool/release/security_scan.py` → **`OK`, EXIT=0**.

---

## Amit NEM mértem

- A teljes `tools/round-gate.sh`-t és a teljes backend suite-ot (a handoff
  §10.3 állításai) — csak a kör két gate-fájlját futtattam.
- A `check_secrets_test.dart` A10-cellát külön (a fájl a javító diffben sem
  szerepel; a `T-RELEASE-02` guardon keresztül mérve feloldható).
- A MINOR-4 / MINOR-5 állapotát nem tekintem regressziónak: a koordinátor
  ezeket kimondottan kivette ebből a körből (`/tmp/E12-R18-review-findings.md`
  „NEM ebben a körben"). Mérve: a `--format json` kimenet a valós fán
  továbbra is `{"findings": []}` (nincs futás-metaadat), az advisory-illesztés
  továbbra is egy-klauzulás.

## Összegzés

Átadott leletek: **7/7 ZÁRVA** (MAJOR-1, MAJOR-2, MAJOR-3, MAJOR-4, MINOR-1,
MINOR-2, MINOR-3), mind a saját, korábban zöld támadásom PIROS
újrafuttatásával bizonyítva. Regresszió nincs. Új nyitott lelet: **1 MAJOR
(latens, S8 — fájl/group-szintű elnémítás)** és **1 MINOR (S9 — a MAJOR-4
javításának nincs piros útja)**; plusz a szándékosan halasztott MINOR-4/-5.
**Verdikt: APPROVED**, azzal a kötéssel, hogy az S8 a Kör 25-ös CI-bekötés
előtt záruljon.
