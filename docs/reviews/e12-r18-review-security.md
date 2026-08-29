# E12-R18 — Biztonsági review

Reviewer: Claude (security-reviewer, Opus 5) · Dátum: 2026-08-29 · Kockázat: **high**
Review-klón: `/tmp/review-e12-r18` · HEAD `23fa5f22` · base `9125e618`
Diff: 6 fájl (5 ÚJ + a §10 handoff), listán kívüli fájl nincs — mérve:
`git diff --name-status 9125e618..23fa5f22`.

## Verdikt

**CHANGES REQUESTED** — CRITICAL: 0 · BLOCKER: 0 · **MAJOR: 4** · MINOR: 5 · NOTE: 4.

Termékkód (`lib/**`, `backend/app/**`) nem változott, így az AGENTS.md §5
termékhatárok közvetlenül nem sérülnek — nincs új log-, hálózati vagy
perzisztencia-sink, nincs commitolt valódi titok, a szintetikus fixture
bizonyítottan illeszkedik a mérce saját szabályára (M-A1 alább). A négy MAJOR
mindegyike a **kapu megbízhatóságát** érinti: a szállított scan az ADR 0481
két kötött döntését (D5 „nincs elnyelő ág", D2 „a törölt/átnevezett védelmi
teszt release-blokkoló") **mérhetően nem tartja be**, és a program-szintű
threat model kihagyja a program legerősebb, ma már MÉRT nem tárgyalható
határát (§5.1/§5.2, egress + consent). Mind a négy javítása a kör saját,
engedélyezett fájljain belül van.

**Amit külön kiemelek pozitívumként (mérve, ne essen áldozatul a javításnak):**
a fail-closed bemenet-kezelés (exit 2) minden ágon működik, a `fatal` és az
`exceptions.expired` lelet **nem** elnyelhető, a titok-ág A1 piros útja NEM
vak (negatív kontrollal bizonyítva), a `yaml.safe_load` és a `shell=True`
hiánya rendben van, és a backend-teszt tényleg guardként köt be, nem második
igazságforrás.

---

## Mérési környezet

Minden alábbi parancs a `/tmp/review-e12-r18` klónban futott (a közös fát nem
érintettem). Python 3.12.3, PyYAML 6.0.1, Flutter/Dart elérhető.
A klón a mérések után **tiszta**: `git status --porcelain` → üres.

Alap-mérés (a kör §10.3 állításának ellenőrzése):

```
$ python3 tool/release/security_scan.py
security_scan: OK — no critical or fatal finding.
EXIT=0

$ flutter test test/tooling/security_scan_test.dart
00:02 +22: All tests passed!
```

A 14 guard mind feloldható a fán (saját, a scan parserét használó szkripttel
soronként kimérve — `T-CLIENT-01 … T-RELEASE-03`, mind `release_gate=True`,
mind létező fájl + létező teszt-név, pl. `T-DIAG-01 → backend/tests/test_diagnostics.py:258`,
`T-MODEL-02 → test/tooling/ml_asset_manifest_test.dart:39`). A dokumentum
tény-horgonyai is stimmelnek: `_safe_id` valóban `diagnostics.py:56`,
`uq_community_challenge_results_replay` létezik
(`backend/app/community/models/challenge_result.py:190`),
`media_upload_service.py` létezik, a hivatkozott ADR-ek (0091/0395/0448) és a
`community-threat-model.md` léteznek, és a nyolc Community-kategória **nincs
átmásolva**, csak egy hivatkozó sorban felsorolva (D1 teljesül).

---

## MAJOR-1 — Egyetlen `exceptions.yaml` sor kikapcsolja a teljes `secrets` ágat (D5 sérül)

**Hely:** `tool/release/security_scan.py:425-428` (`_apply_exceptions`),
`:730-734` (a secrets-ág leleteinek szűrése), `:710-717` (a guard-leletek
szűrése); a szerződés oldala: `docs/security/exceptions.yaml:13-14`;
a hamis állítás: `tool/release/security_scan.py:36-42` (modul-docstring).

**Failure scenario.** A `secrets` ág LELET-AZONOSÍTÓJA két fix konstans
(`secrets.delegate-failed`, `secrets.delegate-unavailable`, `:596-637`), nem a
megtalált titoké. A `_apply_exceptions` a lelet `id`-jére szűr, és a
**default (teljes) futásban** a secrets-leletekre is fut. Ezért egy owner-rel
és jövőbeli lejárattal ellátott, egysoros kivétel-bejegyzés nem egy elfogadott
kockázatot ment fel, hanem **a titok-ellenőrzést mint olyat kapcsolja ki** —
minden jövőbeli, valódi commitolt titokra is.

```
$ cat exc_secrets.yaml
exceptions:
  - finding: secrets.delegate-unavailable
    owner: attacker@example.invalid
    expires: "2099-01-01"
    reason: "temporarily accepted"
  - finding: secrets.delegate-failed
    owner: attacker@example.invalid
    expires: "2099-01-01"
    reason: "temporarily accepted"

$ python3 tool/release/security_scan.py --exceptions <fenti> --secrets-cmd /bin/false
security_scan: OK — no critical or fatal finding.
EXIT=0

$ python3 tool/release/security_scan.py --exceptions <fenti> --secrets-cmd nope-not-a-binary
security_scan: OK — no critical or fatal finding.
EXIT=0
```

Ugyanez guardra (a `T-DIAG-01` path-traversal védelem neve elrontva a threat
modell egy másolatában, plusz egy `finding: T-DIAG-01` kivétel):

```
$ python3 tool/release/security_scan.py --only guards --threat-model <elrontott>
- [critical] guards: T-DIAG-01 (diagnostics-upload): guard.test 'test_this_guard_was_deleted_long_ago' not found in backend/tests/test_diagnostics.py (T-DIAG-01)
EXIT=1

$ python3 tool/release/security_scan.py --threat-model <elrontott> --exceptions <exc_guard.yaml>
security_scan: OK — no critical or fatal finding.
EXIT=0
```

**Sértett szabály.** ADR 0481 **D5** („NEM elfogadható gyengítés: … egy
`--force`/`--no-fail` kapcsoló, amely a kritikus leletet elnyeli") — a
kivétel-nyilvántartás funkcionálisan pontosan ilyen kapcsoló, csak YAML-ban.
Továbbá a scan **saját docstringje hamis**: `:40-42` azt állítja, hogy „a
guard whose test was renamed cannot be waved away by an exceptions entry in
this round's scope", miközben a default futásban mérhetően elnyelhető. A
handoff §10.5 megfogalmazása („a `dependencies` ágra … van bekötve") szintén
alulmondja a mért hatókört.

**Javasolt irány.** (a) A `secrets` ág leletei elvi okból ne legyenek
elnyelhetők (a titok-kapu a D3 szerint fail-closed delegáció), vagy a kivétel
kösse magát a KONKRÉT találathoz (fájl+sor+szabály), ne a branch-konstanshoz.
(b) A kivétel hordozzon kötelező `branch`/`scope` mezőt, és csak az adott ág
adott leletére illeszkedjen. (c) A docstring §36-42 és a handoff §10.5
igazítása a mért viselkedéshez — vagy a viselkedés a szöveghez.

---

## MAJOR-2 — A guard „létezése" nyers substring: a kikommentelt vagy `skip`-elt védelmi teszt zöld (D2 sérül)

**Hely:** `tool/release/security_scan.py:311-313`
(`needle_python = f"def {guard_test}"`, `needle_dart = f"test('{guard_test}'"`,
`if needle_python not in guard_text and needle_dart not in guard_text`).

**Failure scenario 1 — a védelmi teszt letiltva `skip`-pel.** Beszúrtam egy
`@pytest.mark.skip(reason='flaky, TODO')` sort a path-traversal védelem fölé
(`backend/tests/test_diagnostics.py`, `test_diagnostics_session_id_cannot_escape_data_dir`),
a threat modellt nem érintve:

```
$ python3 tool/release/security_scan.py --only guards
security_scan: OK — no critical or fatal finding.
SCAN_EXIT=0
$ cd backend && python3 -m pytest tests/test_security_release.py -q
..........                                                               [100%]
```

A védelem **nem fut többé**, a release-kapu és az A9 cella is zöld.
(Visszaállítva: `git checkout -- backend/tests/test_diagnostics.py`.)

**Failure scenario 2 — a Dart védelmi teszt kikommentelve.** A
`test/tooling/check_secrets_test.dart` `flags provider token literals by their
own prefix` cellájának feje kikommentelve (a klasszikus „flaky, majd
visszatesszük" alak):

```
$ grep -n "flags provider token literals" test/tooling/check_secrets_test.dart
34:  // test('flags provider token literals by their own prefix', () {
$ python3 tool/release/security_scan.py --only guards
security_scan: OK — no critical or fatal finding.
SCAN_EXIT=0
```

Ugyanez `test/tooling/vision_model_integrity_test.dart`-tal (T-MODEL-01),
ahol a teszt-törzs helyére csak egy `// TODO(...) test('bad checksum fails the
integrity gate' …` komment maradt → **EXIT=0**. A hat Dart-guardra nincs a
backend A9-hez hasonló `--collect-only` keresztmérés, tehát ezt semmi más nem
fogja meg.

**Failure scenario 3 — pytest-teszt utótaggal átnevezve.** A python-tű nincs
lezárva (`def <név>`, `(` nélkül), ezért a prefix-átnevezés átcsúszik:

```
# test_media_upload.py-ban: def test_a2_finalize_rejects_expired_signed_url( → ..._v2(
$ python3 tool/release/security_scan.py --only guards
security_scan: OK — no critical or fatal finding.
EXIT=0
```

(A Dart-tű `test('<név>'` alakja a záró aposztróf miatt EZT az esetet elkapja —
mérve: a `— DISABLED` utótag PIROS lett. Az aszimmetria a python-oldalon van.)

**Kontroll (a piros út létezik):** a threat modellben elrontott guard-név
(`test_a2_finalize_rejects_expired_signed_url_RENAMED`, a valós
`docs/security/threat-model.md`-ben, majd `git checkout -- …`) mind a scant,
mind a backend A9-et pirosra vitte — tehát a *doc→fa* irány mér, a *fa→doc*
irány (letiltás/kikommentelés) nem.

**Sértett szabály.** ADR 0481 **D2** + a Következmények első pontja: „a
biztonsági védelmek törlése vagy átnevezése mostantól release-blokkoló, nem
csendes regresszió". A mért valóság: a védelem letiltható úgy, hogy a kapu
zöld marad. Ez a brief §6.2 „elgépelve / átnevezve, és senki nem méri" sorának
a fa-oldali fele, amire nincs cella. (L483 hibaosztálya: az őr a saját
hibaosztályát engedi vissza.)

**Javasolt irány.** A guard.test feloldását ne szöveg-illesztés döntse el:
(a) a Dart-guardokra a `--collect-only` analógja (`flutter test --plain-name
'<név>' --dry-run` vagy a Dart teszt-fájl AST/`test(` sorának kommentmentes
kinyerése), (b) a python-tű lezárása (`def <név>(`), (c) a `skip`/`xfail`
marker jelenlétének kritikus leletté minősítése a guard sorában, (d) minimum:
a komment- és string-tartalom kiszűrése a keresés előtt (a repó saját
`_withoutTrivia` mintája a `test/core/architecture_dependency_test.dart:1145`
sorban már létezik).

---

## MAJOR-3 — A program-szintű threat modelből hiányzik a §5 nem tárgyalható határ (egress + consent), noha az előfeltétel-kör MÉRT guardot szállított rá

**Hely:** `docs/security/threat-model.md:44-68` (komponens-lista) és
`:70-88` (client-storage — az egyetlen kliens-komponens).

**Failure scenario.** A modell hét komponense közül a kliens oldalt egyetlen
fenyegetés fedi (token sima prefsben). Nincs komponens/`guard` arra a két
határra, amit az AGENTS.md §5 nem tárgyalhatónak nevez:

1. nyers audio / kamera-frame nem hagyhatja el az eszközt alapértelmezetten;
2. kijelentkezett + diagnostics-off állapotban nincs rejtett hálózati kérés.

Ezekre a fán **van** ma mérő cella — épp a kör deklarált előfeltétele, az
E12-R17 szállította (`6ead9581`): `test/privacy/consent_enforcement_test.dart`
(négy egress-csatorna, „consent off → nem megy ki", „consent flip mid-session
→ azonnal leáll"), `docs/privacy/data-inventory.yaml`,
`test/tooling/diagnostics_storage_separation_test.dart`,
`test/features/settings/lab_mode_toggle_test.dart`,
`test/features/diagnostics/diagnostics_uploader_test.dart`. Egyik sem guard.
Következmény: ha egy jövőbeli kör a consent-kikényszerítést törli, a
release-scan **zöld marad** — miközben a brief §0.0 indoklása szerint épp „az
adat-leltár a threat model adat-oldali bemenete".

Két további, ma MÉRT, de nem modellezett védelem ugyanezen a komponensen:

- `POST /diagnostics` **token-kapu**: `backend/app/routers/diagnostics.py:122-129`
  (`X-Diag-Token`, `hmac.compare_digest`, üres konfigurált token esetén
  elutasít) — mérő cella: `backend/tests/test_diagnostics.py:64`
  (`test_diagnostics_rejects_bad_token`). A `diagnostics-upload` komponens csak
  traversalt (T-DIAG-01) és oversize-t (T-DIAG-02) modellez, spoofingot nem.
- backend rate-limit / auth-throttle / prod boot guardok:
  `backend/tests/test_hardening.py:20,42,86` (`TestRateLimiter`,
  `TestAuthThrottle`, `TestProdBootGuards`) — a `backend-api` komponens
  egyetlen fenyegetése a user-enumeration.

STRIDE-lefedettség mérve: a 14 blokk csak `tampering` / `information-disclosure`
/ `spoofing` / `denial-of-service` értéket használ; `repudiation` és
`elevation-of-privilege` egyetlen komponensnél sem szerepel.

**Sértett szabály.** AGENTS.md §5.1/§5.2 (a program legdrágább határa) +
ADR 0481 D2 szelleme (a védelem bizonyítékhoz kötése) — a kapu ma nem a
legfontosabb védelmeket köti.

**Javasolt irány.** Új komponens (`client-egress` / `consent`) legalább két
`release_gate: true` guarddal a `test/privacy/consent_enforcement_test.dart`
konkrét cellanevére, plusz `T-DIAG-03` a token-kapura
(`test_diagnostics_rejects_bad_token`) és egy `backend-api` DoS-sor a
`test_hardening.py` throttle-cellájára. Mind a négy ma feloldható a fán, tehát
a kör §6 A8 cellája változatlanul zöld maradna.

---

## MAJOR-4 — A `T-CLIENT-01` guard nem a leírt fenyegetést méri (működés-teszt védelmi teszt helyett)

**Hely:** `docs/security/threat-model.md:72-88`; a hivatkozott cella:
`test/core/storage/secure_store_test.dart:105` (`test('round-trips a secret')`).

**Failure scenario.** A leírt fenyegetés: „ha a session token … sima
`SharedPreferences`-ben … kerülne el, egy … támadó kiolvashatná", és a szöveg
tényként állítja, hogy „az egyetlen `lib/`-beli hely, amely a
`flutter_secure_storage` pluginot importálja, a `FlutterSecureStore`". A guard
viszont egy `_MemoryStorage` fake fölött futó funkcionális round-trip
(`write → read → delete`), amely a fenyegetésről semmit nem mond. Mérve:

```
$ grep -rn "flutter_secure_storage" lib/
lib/core/storage/secure_store.dart:2:import 'package:flutter_secure_storage/flutter_secure_storage.dart';
lib/core/storage/secure_store.dart:24:/// … the only place in `lib/` that …
```

Az állítás MA igaz, de **semmi nem őrzi**: a
`test/core/architecture_dependency_test.dart:1129,1135,1378` csak a
gamification és a community DOMAIN rétegre tiltja a
`package:flutter_secure_storage/` importot — a `features/**` egyéb részére
nem. Tehát ha egy jövőbeli kör a JWT-t `SharedPreferences`-be írja, a
`secure_store_test.dart` érintetlen marad, a scan zöld, és a threat model
továbbra is „mért ellenintézkedést" állít.

**Sértett szabály.** ADR 0481 D2 („NEM elfogadható gyengítés: … olyan
guard-lista, amelynek nincs bizonyított piros útja") és az AGENTS.md §5.5
analógiája (gyenge bizonyíték biztos állításként).

**Javasolt irány.** A guard mutasson a token tényleges tárolási útjára
(`test/features/auth/token_store_test.dart` — létezik a fán), és/vagy a kör
utáni önálló körben szülessen egy architektúra-cella, amely a
`flutter_secure_storage` importot a `lib/core/storage/secure_store.dart`-ra
korlátozza; addig a threat model szövege ne állítsa mértnek azt, ami nem az.

---

## MINOR

### MINOR-1 — A `guard.path` kiléphet a repóból (abszolút út és `..`)

`tool/release/security_scan.py:284-286` (`guard_path = root / entry.guard_path`,
`is_file()`), miközben a brief §5.1 szerint a `path` „a repó gyökeréhez
képesti" út. Mérve:

```
# T-ESCAPE-01: guard.path: /etc/hostname ; T-ESCAPE-02: guard.path: ../../../../etc/hosts
$ python3 tool/release/security_scan.py --only guards --threat-model <fenti>
security_scan: OK — no critical or fatal finding.
EXIT=0
```

Nincs sem containment-ellenőrzés, sem git-követettségi feltétel — egy guard
mutathat nem verziókövetett, lokális fájlra is. Irány: `Path.resolve()` +
`is_relative_to(root.resolve())`, és a guard-fájl `git ls-files` tagsága.

### MINOR-2 — A `release_gate` átbillentése és a guard-blokk törlése néma

`tool/release/security_scan.py:282-283` (`if not entry.release_gate: continue`).
Mérve: a szállított modell mind a 14 `release_gate: true` sorát `false`-ra
állítva a `guards` ág **EXIT=0**, és a kör A8 cellája is zöld maradna, mert az
csak `contains('component: <név>')` substringet néz
(`test/tooling/security_scan_test.dart:498-518`):

```
$ sed 's/^release_gate: true$/release_gate: false/' docs/security/threat-model.md > tm_off.md   # 14 találat
$ python3 tool/release/security_scan.py --only guards --threat-model tm_off.md
security_scan: OK — no critical or fatal finding. → EXIT=0
# és mind a 7 komponens-substring továbbra is jelen van → A8 zöld
```

Irány: a szállított modellre kötött cella („mind a 14 ismert id létezik és
`release_gate: true`"), vagy legalább komponensenként „≥1 `release_gate: true`
blokk" a doksi-substring helyett.

### MINOR-3 — Jelen lévő, de guard nélküli threat model = zöld

`load_threat_model` üres `entries` listával tér vissza, és a `guards` ág
lelet nélkül fut le. Mérve egy ```` ```text ````-re átírt blokkot tartalmazó
modellel: **EXIT=0**. Az A7 cella csak a HIÁNYZÓ fájlt fedi. Ez az L220
hibaosztály enyhébb alakja („nem találtam guardot, tehát tiszta"). Irány:
`entries` üressége (vagy `release_gate: true` blokk hiánya) legyen kritikus
lelet.

### MINOR-4 — A `secrets` ág parancssorból is semlegesíthető, és a kimenet nem árulja el, mi futott

`tool/release/security_scan.py:685` (`--secrets-cmd` default) + `:650-674`
(render). Mérve:

```
$ python3 tool/release/security_scan.py --secrets-cmd true
security_scan: OK — no critical or fatal finding. → EXIT=0
$ python3 tool/release/security_scan.py --secrets-cmd true --format json
{ "findings": [] } → EXIT=0
```

A `--format json` artefaktum (amit a D5 szerint a Kör 25 RC-összeállítója
olvas) semmilyen futás-metaadatot nem hordoz: nincs benne, mely ágak futottak,
milyen bemenetekkel, milyen `--secrets-cmd`-del, hány guardot oldott fel.
Egy `--only exceptions --secrets-cmd true` futás kimenete bájtra azonos egy
teljes futáséval. Irány: `run` blokk a JSON-ban (branches, inputs+sha,
guard-count, effective secrets command, `today`), és a Kör 25-ös bekötés
rögzítse a default parancsot.

### MINOR-5 — Az advisory-illesztés csak az alsó korlátot és egyetlen klauzulát ismeri

`tool/release/security_scan.py:499-529` (`_effective_floor`, `_matches_advisory`,
`_CONSTRAINT_CLAUSE`). Mérve (a `<` alakra helyesen működik):

```
$ printf 'pyjwt>=2.0,<3.0\n' > req1.txt → CVE-2022-29217 kritikus lelet, EXIT=1
$ printf 'pyjwt>=2.4,<3.0\n' > req2.txt → EXIT=0
```

Viszont az `affected` kifejezés egyetlen klauzula lehet, és a jelölt verzió az
**alsó** korlát: egy `>=x` vagy egy tartományos (`>=2.0,<2.4`) advisory nem
fejezhető ki, illetve a `>=`/`>` alak a pin alsó korlátjához mérve
alul-jelez (`>=1.0,<3.0` pin + `>=2.0` advisory → nincs lelet, pedig a 2.x
telepíthető). Ma egyetlen, `<` alakú advisory van, tehát nem aktív hiba —
de a lista bővítésekor csendben alul-mér. Irány: tartomány-kifejezés
támogatása és a pin teljes megengedett intervallumának metszése.

---

## NOTE

- **N1 — a delegált parancs stdout/stderr-je szó szerint bekerül a leletbe.**
  `tool/release/security_scan.py:625-637`. Kanárival mérve: egy `sk-CANARY_…`
  értéket kiíró álkapu teljes sora megjelent a `--format json` kimenetben.
  **Ma nem szivárgás:** az alapértelmezett delegált (`tool/ci/check_secrets.dart`)
  bizonyítottan csak helyet ír (mérve: `lib/leaked.dart:1: provider token
  literal`, az érték nem jelenik meg), és a kör A1 cellája explicit
  `isNot(contains(<érték>))` állítást is tartalmaz
  (`test/tooling/security_scan_test.dart:132-136`). A kockázat a jövőre szól:
  a scan maga nem redaktál, és a JSON release-artefaktum. Irány: a delegált
  kimenet hosszkorlátja + a `check_secrets` szigorú kimeneti alakjára szűrés.
- **N2 — a titok-delegálás 180 s-os timeoutja.** `:614`. `TimeoutExpired` →
  kritikus lelet (fail-closed irány, helyes), de egy hideg `dart run` fordítás
  CI-n hamis kritikust adhat. Mérve: a valós fán a default futás bőven a
  határon belül végzett.
- **N3 — a `dependencies` ág egyetlen manifestet lát.** A default
  `backend/requirements.txt` (11 nem-komment sor, mind felső korláttal —
  mérve: a `dependencies` ág EXIT=0). A
  `backend/requirements-dev.txt` és a Dart oldal (`pubspec.yaml` /
  `pubspec.lock`) nincs a kapuban; a threat model §8 szövege korrektül csak
  „backend-függőség"-et állít, tehát ez **nem** túlállítás, csak lefedettségi
  hézag. Mérve: `--requirements backend/requirements-dev.txt` → EXIT=0 (a
  három dev-sor mind korlátos).
- **N4 — a kör jelzés-fájlt, logot, hálózati hívást nem vezet be.** A
  `subprocess` hívás `shell=False` (`shlex.split` + argv, `:598-615`), YAML
  mindkét helyen `yaml.safe_load` (`:249`, `:354`), a `--today` érvénytelen
  értéke exit 2. A backend-teszt `--collect-only` alparancsa doc-eredetű
  stringet ad át **argv-elemként**, nem shellnek
  (`backend/tests/test_security_release.py:66-73`).

---

## Amit külön ellenőriztem és RENDBEN van (bizonyítékkal)

1. **A1 nem vak scanner (L220).** A fixture-literál
   (`test/tooling/security_scan_test.dart:114`,
   `const key = 'sk-abcdefghijklmnopqrstuvwxyz0123';`) ténylegesen illeszkedik
   a `tool/ci/check_secrets.dart` `providerToken` szabályára
   (`sk-[A-Za-z0-9_-]{20,}`), és nem esik a placeholder-szűrőbe.
   Újraépítettem a fixture-t egy temp git-fán, és a delegált kapuval mértem:

   ```
   # a literállal:
   - [critical] secrets: … exited 1: Secret scan failed (1 file(s) scanned, 1 finding(s)).
     - lib/leaked.dart:1: provider token literal
     EXIT=1
   # negatív kontroll (a literál kicserélve 'not-a-secret'-re):
   security_scan: OK — no critical or fatal finding. EXIT=0
   ```

   Az exit 1 tehát a BEINJEKTÁLT titoktól van, nem a harness zajától — az A1
   cella nem lenne zöld a titok-ág nélkül. Az érték sehol nem jelenik meg.
2. **A fail-closed bemenet-ágak (D6).** Hiányzó threat model / `exceptions.yaml` /
   `requirements` → **EXIT=2** mindhárom esetben; nem futtatható `--secrets-cmd`
   → `secrets.delegate-unavailable`, EXIT=1; `/bin/false` →
   `secrets.delegate-failed`, EXIT=1; érvénytelen `--today` → EXIT=2. Más
   kilépési kódot nem sikerült előállítanom; `--force`/`--no-fail`-szerű
   kapcsoló nincs az argparse-ban (`:679-687`), `skipped` besorolás sehol.
3. **A lejárat INKLUZÍV határa (D4).** A cellahármas mérve (`--only exceptions`,
   `--today 2026-08-29`): `expires: 2026-08-28` → EXIT=1
   (`exceptions.expired`), `2026-08-29` → EXIT=0, `2026-08-30` → EXIT=0.
   Wildcard/regex illesztés NINCS: a `live` szótár kulcsa pontos string
   (`:421`, `:428`), tehát `finding: "*"` semmit nem ment fel.
4. **A `fatal` és az `exceptions.expired` lelet NEM elnyelhető.** Élő
   `finding: guards.input-error` bejegyzés mellett a hiányzó threat model
   továbbra is EXIT=2; élő `finding: exceptions.expired` mellett egy 2020-as
   lejáratú bejegyzés továbbra is EXIT=1. (Ez a MAJOR-1 pozitív ellenpárja: a
   szerző itt tudatosan a szűrés ELÉ tette a leleteket, `:706` vs `:716`.)
5. **Nincs duplikáció (§0.0 R2).** A `backend/tests/test_security_release.py`
   a `security_scan.py`-t modulként tölti be (`:31-46`), a threat modellből
   nyeri a 8 backend node-idet, és kizárólag `pytest --collect-only`-t futtat;
   sehol nem állít újra replay-, traversal-, oversize- vagy checksum-viselkedést.
   Grep-pel ellenőrizve: a fájlban nincs sem HTTP-hívás, sem DB-fixture, sem
   `assert` ezekre a viselkedésekre.
6. **A kör nem nyúlt termékkódhoz és nem vezetett be függőséget.** A diff hat
   fájlja mind a §4 listán van; új Python/Dart csomag nincs (`yaml` a már mért
   PyYAML), új asset nincs.

---

## Amit NEM mértem

- A `tools/round-gate.sh` teljes futását és a teljes backend suite-ot (a §10.3
  állításai) — a klónban csak a kör saját Dart gate-fájlját futtattam
  (`22/22 All tests passed!`) és a `tests/test_security_release.py`-t
  (`10 passed`, illetve a mutáció alatt a várt 1 piros). A `check_secrets_test.dart`
  A10 változatlanságát nem futtattam külön; a fájl a diffben nem szerepel.
- Az `.github/workflows/security.yml` CI-bekötést (szándékosan nincs a körben,
  §0.1) — így azt sem mértem, hogy a Kör 25 milyen paraméterekkel hívná a
  scant; a MINOR-4 ajánlása erre a körre néz előre.
- A Community media presigned PUT tényleges szerver-oldali viselkedését — a
  kör csak guardként köti be, és a hivatkozott három cella
  (`test_a2/a3/a4_finalize_*`) létezését ellenőriztem, a tartalmukat nem
  auditáltam újra (E09-R18 külön review tárgya volt).

---

## Összegzés

**CRITICAL: 0 · BLOCKER: 0 · MAJOR: 4 · MINOR: 5 · NOTE: 4** — a MAJOR-1
(kivétel kikapcsolja a titok-ágat, D5) és a MAJOR-2 (kikommentelt/`skip`-elt
védelmi teszt zöld, D2) a kör saját fájljain belül javítható, és amíg nyitva
vannak, a scan zöld kimenete nem tekinthető release-bizonyítéknak.
