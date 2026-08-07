# E05-R17 — Review

Brief: `docs/rounds/e05-r17-auto-guitar-detector-decision.md`
Diff: `git diff c2ed5ca..882b127` (implementer saját commitjai, branch
`minimax/e05-r17-auto-guitar-detector-decision`, munkapéldány `/home/ubuntu/ss-mm-e05-r17`);
orchestrátor utókorrekció `882b127..e5450b2` (lásd BLOCKER-1 „Státusz").
Reviewer: Claude Sonnet 5 (orchestrátor) · Dátum: 2026-08-07
Verdikt (első pass): CHANGES REQUESTED
Verdikt (javító kör 1 után, `3748821`): **APPROVED** — ld. „Javító kör 1 —
zárás" szakasz a végén.

## Összegzés

BLOCKER: 1 · MAJOR: 1 (dedikált security-review lelete) · MINOR: 0 · NOTE: 5
(1 saját + 4 security)

A gate egy friss, GitHub-ról frissen klónozott, izolált `/tmp/review-e05-r17`
munkapéldányban függetlenül újrafuttatva **6/6 zöld**
(`tools/round-gate.sh test/tooling`), a scope-audit
(`tools/scope-audit.py --base c2ed5ca`, az implementer saját `882b127`
tippjén) **OK** (5 changed path). A `--self-test` **9/9 PASS**, DE a
`--self-test` zöldsége itt **nem bizonyíték**: a `decision()` függvény
alapvető iránya INVERTÁLT egy hibametrikán (lásd BLOCKER-1) — a metrikák
SZÁMÍTÁSA (IoU, mean/p95 anchor error, failure_rate) mind helyes és jól
tesztelt, csak a rájuk épülő PROMÓCIÓS DÖNTÉS logikája fordított irányú.
Dedikált `security-reviewer` subagent (risk=high, kötelező) egy MAJOR-t adott
a `dataset_manifest.md` consent-sémájára — lásd MAJOR-1.

## Acceptance criteria (§6, a javított brief szerint)

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | ADR 0187 tartalmaz döntést + számszerű küszöböket + elutasított alternatívákat + hamis-geometria kockázatot | ✅ | Orchestrátor pre-flight, `docs/adr/0187-*.md` — a BLOCKER-1 javítása is itt (Döntés 4) |
| 2 | `dataset_manifest.md` kategóriánként forrás/jogalap/consent/számosság/tiltott lista | ⚠️ Részleges | 12 kategória, 8 mezős consent-séma (§2), 7 tételes tiltott forrás (§3) — DE a consent-séma az SDD §31.2 7 kötelező mezőjéből csak 6-ot visz át, lásd MAJOR-1 |
| 3 | Harness lefut üres bemenettel `NO_DATA`-val; metrikák unit-szinten ellenőrizhetők | ⚠️ Részleges | A metrika-SZÁMÍTÁS helyes és tesztelt; a rá épülő `decision()` promóciós logika **fordított irányú** — ld. BLOCKER-1 |
| 4 | Baseline doksi: manual kalibráció költségbecslés + PENDING jelölés | ✅ | `docs/baseline/epic-05-guitar-detector-evaluation.md` §2 (P50~17s/P95~30s/anchor unc.<0.01) + §4 (PENDING-lista) |
| 5 | `git diff --stat` nem tartalmaz lib/test/assets/pubspec/binárist | ✅ | csak `.md`/`.py`, 5 fájl (implementer) |

## Scope-audit

```
$ python3 tools/scope-audit.py --repo /tmp/review-e05-r17 \
    --brief docs/rounds/e05-r17-auto-guitar-detector-decision.md --base c2ed5ca
    (HEAD=882b127, az implementer saját tippje)
Legacy scope audit OK (c2ed5ca..882b1270ac72, 5 changed path(s), 0 generated/ignored)
```

Megjegyzés: a `c2ed5ca..HEAD` (jelenlegi branch-tipp, `e5450b2`) tartomány a
scope-audit szerint **VIOLATION**-t adna a `docs/adr/0187-*.md`-re — ez
VÁRT és NEM implementer-scope-sértés: az orchestrátor saját, dokumentált
utókorrekciója (BLOCKER-1 javítása, `e5450b2`, szerző „Ralph (autonomous)"),
a fájl szándékosan lett kivéve az `allowed_paths`-ból (§2 „engedélyezett-
fájllista szűkítése"), tehát az implementer diffje ELLEN kell mérni
(c2ed5ca..882b127), nem a teljes branch ellen. A fenti audit ezt a helyes
tartományt méri. A dedikált security-reviewer subagent függetlenül
ugyanerre a következtetésre jutott (`git log -- docs/adr/0187-*.md`
in-range egyetlen, orchestrátor-szerzőségű commitot ad).

## Megállapítások

### BLOCKER-1 — A `decision()` promóciós logika INVERTÁLT: rosszabb detektort jutalmaz, jobbat büntet

- **Fájl:** `ml/vision/evaluate_geometry_baseline.py:209-253` (`Metrics.decision()`).
- **Gyökérok:** NEM implementer-hiba. A kör-brief §6.2 küszöb-mátrixa (amit
  az orchestrátor a pre-flightban konkretizált egy generikus, batch-írt
  sablonból) és az ADR 0187 eredeti Döntés 4. pontja UGYANEZT az inverz
  irányt írta elő — az implementer szó szerint, hűen implementálta a kapott
  specifikációt, ÉS saját `§10.7` handoff-jegyzetében ki is emelte, hogy ez
  látszólag ellentmond az ADR Döntés 2 táblájának (`≤ 0.030`) — tehát
  **jelezte a kétértelműséget, nem csendben találgatott**. Ez a fajta
  transzparencia pontosan az, amit a minimax-preambulum 3. szabálya kér.
- **Probléma:** `mean_anchor_error` egy HIBA-metrika, ahol az ALACSONYABB
  érték a JOBB. A helyes promóciós szabály: „≤ 0.030 (jobb-egyenlő, mint a
  küszöb) ÉS a másik két tengely is a küszöbön belül → production-candidate;
  egyébként experimental" — ez az, amit az ADR Döntés 2 táblája **már
  helyesen** `≤ 0.030` alakban ír. A kód (és az eredeti §6.2 tábla) ehelyett
  a `mean_anchor_error > MEAN_ANCHOR_ERROR_MAX` esetben ad
  `PRODUCTION_CANDIDATE`-et — azaz egy 0.031 (ROSSZABB, a küszöb fölötti)
  mean-hibájú detektort MAGASABBRA sorol, mint egy 0.029 vagy 0.030
  (JOBB-EGYENLŐ) mean-hibájút, amely `EXPERIMENTAL`-ben ragad.
- **Bizonyíték (empirikusan lefuttatva, függetlenül, a `/tmp/review-e05-r17`
  klónban, MIELŐTT az orchestrátor bármit javított volna a kódon):**
  ```
  $ python3 ml/vision/evaluate_geometry_baseline.py --self-test
    [PASS] §6.2.mean=0.029-below-threshold-yields-experimental
            mean_anchor_error=0.0290 ... decision=EXPERIMENTAL
    [PASS] §6.2.mean=0.030-on-threshold-yields-experimental
            mean_anchor_error=0.0300 ... decision=EXPERIMENTAL
    [PASS] §6.2.mean=0.031-above-threshold-yields-production-candidate-other-axes-pass
            mean_anchor_error=0.0310 ... decision=PRODUCTION_CANDIDATE
  summary: 9/9 passed
  ```
  A „9/9 PASS" itt **álbizonyíték**: a self-test saját maga elvárásai is
  (helyesen implementálva) az inverz specifikációt tükrözik, tehát
  önkonzisztensen zöld, de a mögöttes szemantika hibás — egy jövőbeli
  aktiváló kör, ha ezzel a harness-szel mérne egy VALÓDI, rossz detektort
  (mean=0.08, messze a küszöb fölött), a `decision()` **`PRODUCTION_CANDIDATE`-
  nek minősítené**.
- **Kapcsolódó hézag:** a két kiegészítő teszt
  (`§6.2.p95-axis-failure-yields-experimental`,
  `§6.2.failure-rate-axis-failure-yields-experimental`) a jelenlegi (hibás)
  kódágon **véletlenül** ad helyes címkét (`EXPERIMENTAL`), de NEM azért,
  mert ténylegesen belép a p95/failure_rate-ellenőrző ágba — mindkét teszt
  `mean_anchor_error` értéke (0.024, illetve 0.020) a küszöb ALATT van,
  tehát a jelenlegi `if mean > MAX` feltétel HAMIS, és a függvény a záró
  `return "EXPERIMENTAL"`-ra esik ANÉLKÜL, hogy a p95/failure_rate ágat
  valaha kiértékelné. A teszt NEM azt méri, aminek a neve állítja.
- **Korlátozott kockázat (a dedikált security-review saját megfigyelése,
  megerősítve):** még ha a jelenlegi hibás irány élesben maradna is, az
  ADR 0187 §Döntés 5 („a `production-candidate` minősítés mindig a
  javaslat MINŐSÉGÉRŐL szól, sosem a megerősítés kihagyásáról") és az ADR
  0181 §Döntés 2 (a manual kalibrációs UI előtöltése mindig explicit
  felhasználói megerősítéssel történik) miatt egy tévesen `production-
  candidate`-nek minősített, rossz detektor sem tudná CSENDBEN felülírni a
  manual geometriát — a blast radius szerkezetileg korlátozott. Ez NEM
  csökkenti a lelet súlyosságát (a harness célja pontosan a helyes döntés,
  és ez most nem az), de megerősíti, hogy az ADR 5. pontjának „mindig
  megerősítéssel" záró mondata jól védett második védelmi vonal.
- **Javítás — MÁR MEGTÖRTÉNT a spec oldalán:** az orchestrátor a
  `docs/adr/0187-*.md` Döntés 4. pontját és a brief §6.2 celláit a `e5450b2`
  commitban a HELYES irányra javította (`0.029`/`0.030` →
  `production-candidate`-eligible, `0.031` → `experimental`, a határ a
  `≤` / minősítő oldalhoz kötve, az R16 `isLost => drift > lostDriftBound`
  precedenssel konzisztensen). **A KÓD oldala (ez a fájl) még nem javult**,
  és emiatt a `docs/rounds/e05-r17-*.md` §10 handoff (implementer-szekció,
  amit az orchestrátor nem módosít) jelenleg a RÉGI, hibás irányt idézi —
  a dedikált security-reviewer erre külön rámutatott: a brief §6.2 és §10
  most egymásnak ELLENTMOND, ezt a fix-kör zárja.
- **Kötelező javítás (irány, nem kész patch, a fix-kör findings-je pontosan
  ezt írja elő):**
  1. `decision()`: a `mean_anchor_error > MEAN_ANCHOR_ERROR_MAX` feltételt
     `mean_anchor_error <= MEAN_ANCHOR_ERROR_MAX`-ra kell cserélni (a belső
     ág — p95/failure_rate ellenőrzés — VÁLTOZATLAN marad, csak a KÜLSŐ
     feltétel iránya fordul).
  2. A három érintett self-test asszerció (0.029/0.030/0.031) elvárt
     értékét meg kell fordítani a javított táblának megfelelően.
  3. A p95-only és failure-rate-only kiegészítő tesztek MEGTARTJÁK a
     jelenlegi elvárt címkéjüket (`EXPERIMENTAL`), DE a javítás UTÁN
     ténylegesen a helyes ágon fognak áthaladni.
  4. A `decision()` docstringje (209-234. sor) a JELENLEGI (hibás) irányt
     írja le szövegesen — a doc-comment-fegyelem szabály szerint ezt is a
     javított iránynak megfelelően kell átírni.
  5. A `docs/rounds/e05-r17-*.md` §10 handoff (implementer-szekció) a
     TÉNYLEGESEN újra lefuttatott, javított `--self-test` kimenetre
     frissítendő.
- **Ellenőrzés:** `python3 ml/vision/evaluate_geometry_baseline.py --self-test`
  9/9 PASS, DE ezúttal `mean=0.029`/`mean=0.030` sorok `decision=PRODUCTION_CANDIDATE`-et
  adjanak, `mean=0.031` sor `decision=EXPERIMENTAL`-t. `tools/round-gate.sh
  test/tooling` változatlanul 6/6 zöld.
- **Státusz:** SPEC RÉSZBEN FIXED (`e5450b2`, orchestrátor — ADR + brief).
  KÓD RÉSZ NYITVA — fix-kör 1 dispatch-elve ugyanarra a motorra (MiniMax),
  ugyanazon a branchen, findings-listával.

### MAJOR-1 — A consent-séma az SDD §31.2 hét kötelező mezőjéből hatot visz át — az „annotator privacy guideline" hiányzik

- **Fájl:** `ml/vision/dataset_manifest.md:55-73` (a §2 „kötelező mezők"
  consent-rekord táblázata, mezők a 63-70. sorban).
- **Lelet forrása:** dedikált `security-reviewer` subagent (risk=high
  kötelező pass), sor-szintű összevetéssel.
- **Hivatkozott forrás, amit átültetne:** `docs/sdd/06-epic-05-computer-vision.md:1845-1853`
  (SDD §31.2 „Consent").
- **Probléma:** Az SDD §31.2 **7** elemet ír elő minden emberi felvételhez:
  (1) explicit consent, (2) felhasználási cél, (3) retention, (4)
  hozzáférési kontroll, (5) törlési folyamat, (6) publikálási tiltás külön
  engedély hiányában, (7) **annotátor privacy guideline**. A manifest §2
  táblája az 1-6. elemet átviszi (`contributor_id`+`signed_at`, `purpose`,
  `retention_days`, `access_scope`, `deletion_procedure`,
  `publication_opt_in`), sőt egy jó pluszt is ad
  (`model_training_opt_in`, célhoz-kötöttség) — de a **7. elem hiányzik**.
  A §2 fejléce a mezőket „SDD §31.2"-ként állítja — a hiány hűségi
  átültetési hiba, nem szándékos szűkítés.
- **Hatás:** Mivel a manifest §4 kifejezetten a JÖVŐBELI aktiváló kör
  szó szerinti öröklésére szánja ezt a struktúrát („hogy a későbbi
  aktiváló kör a struktúrát örökölhesse"), egy jövőbeli kör, ami §2 szerint
  épít consent-rekordot, majd valós annotátorokkal dolgoztat (SDD §31.3:
  kéz-landmark, pose-pontok, neck polygon annotálás), **rögzített
  annotátor-kezelési privacy-szabály NÉLKÜL** tenné ezt — a nyers,
  consentelt frame-eket az annotátorok korlátlanul nézhetnék/
  másolhatnák/tárolhatnák, holott az SDD §31.2 pont ezt írná elő.
- **Részleges, de nem elégséges enyhítés a fájlban:** a §3.5 (99-105. sor)
  egy *„preferált"* arc-/tetoválás-maszkolást ír elő — de ez (a) csak
  „preferált", nem kötelező, (b) a contributor SAJÁT azonosíthatóságára
  szűkül, (c) a TÁROLT képről szól, nem az annotátor viselkedéséről. Nem
  helyettesíti a hiányzó, kötelező annotátor-privacy-mezőt.
- **Kötelező javítás:** egy új sor a §2 táblázatba, pl.
  `annotator_privacy_guideline` (mutató a kötelező annotátor-kezelési/
  -terjesztési szabályzatra), hogy a séma mind a 7 SDD §31.2 elemet vigye.
- **Ellenőrzés:** a §2 táblázat 7+1 (6 eredeti + a pótolt 7. + a bónusz
  `model_training_opt_in`) sort tartalmazzon, mindegyik az SDD §31.2
  megfelelő pontjára hivatkozva.
- **Miért NEM ez önmagában halt-ok:** nincs éles adatfolyam, nincs valódi
  annotátor, nincs tényleges consent-rekord ma (minden kategória
  `PENDING_COLLECTION`) — a kockázat egy JÖVŐBELI aktiváló kör
  hibás-öröklése, nem egy MOST fennálló szivárgás. Mivel a fix egy sor
  hozzáadása egy már úgyis nyitott fix-körben érintett témához (ugyanaz a
  `ml/vision/` mappa), ésszerűbb most zárni, mint egy külön follow-up
  körre halasztani egy ilyen olcsó javítást.
- **Státusz:** OPEN — fix-kör 1 findings-jébe felvéve (ugyanaz a dispatch,
  mint BLOCKER-1).

### N1 — NOTE — `anchor_error()`-ban egy elérhetetlen defenzív ág

- **Fájl:** `ml/vision/evaluate_geometry_baseline.py:158-159`
  (`if not frame.has_guitar: return None`).
- **Probléma:** Az egyetlen hívási hely (`evaluate()` ciklusa, 269. sor)
  MÁR kiszűri a `has_guitar=False` frame-eket egy `continue`-val, MIELŐTT
  meghívná az `anchor_error()`-t — tehát ez az ág sosem fut le a jelenlegi
  hívási láncban. Nem hibás, csak felesleges defenzív kód.
- **Hatás:** Nulla — halott kód, nem befolyásolja egyetlen mért viselkedést
  sem.
- **Kötelező javítás:** nem kötelező.
- **Státusz:** OPEN (nem blokkoló, nem kötelező a fix-körben)

### N2 (security NOTE-4) — NOTE — A hibás-bemenet kilépési kód nem a dokumentált `EXIT_BAD_INPUT=3`

- **Fájl:** `ml/vision/evaluate_geometry_baseline.py:356` (`raise
  SystemExit(f"bad input at line …")` — string argumentum → tényleges
  kilépési kód **1**), vs. a dokumentált/deklarált `EXIT_BAD_INPUT = 3`
  (`:68`) és a README (`ml/vision/README.md:24`) állítása.
- **Lelet forrása:** dedikált `security-reviewer` subagent, NOTE-4,
  reprodukálva (`--input /etc/hostname` → „bad input at line 1: Expecting
  value" → kilépési kód 1, nem 3).
- **Hatás:** Kicsi — a kód továbbra is nem-nulla (az ADR 0187 Döntés 4
  „definiált, nem-nulla kilépési kód" elve NAGYJÁBÓL teljesül), de a
  KONKRÉT dokumentált kód eltér a ténylegestől — ha egy jövőbeli CI-lépés
  a pontos kódra branch-elne, hibásan viselkedne.
- **Kötelező javítás:** nem kötelező ebben a körben, DE mivel a fix-kör
  úgyis ugyanezt a fájlt módosítja (BLOCKER-1 miatt), olcsó egyszerre
  javítani: a `raise SystemExit(...)` helyett expliciten
  `sys.exit(EXIT_BAD_INPUT)` (üzenet előbb `stderr`-re írva) — VAGY a
  dokumentációt igazítani a tényleges viselkedéshez, amelyik egyszerűbb.
- **Ellenőrzés:** `python3 ml/vision/evaluate_geometry_baseline.py --input /nonexistent` →
  a ténylegesen dokumentált kód jöjjön ki.
- **Státusz:** OPEN — opcionálisan felvéve a fix-kör findings-jébe (nem
  kötelező, de ugyanazon fájl, olcsó).

### N3 (security NOTE-1/2/3) — NOTE — Nem kötelező védelmi-mélységi javaslatok, ellenőrizve, nem blokkolók

Dedikált `security-reviewer` subagent három további, nem kötelező
megfigyelése — egyik sem SDD-mandátum-hiány, mind opcionális jövőbeli
finomítás:

- **security NOTE-1:** nincs pozitív „adult attestation" mező a §2
  consent-sémában (a §3.6 gyermek-tiltás kategorikus, de a rekord szintjén
  nem auditálható) — az SDD §31.2 ezt NEM írja elő, védelmi-mélységi
  javaslat.
- **security NOTE-2:** a §3.5 csak a contributor SAJÁT azonosíthatóságára
  szűkül; egy véletlenül képbe kerülő, nem-contributor felnőtt személy
  nincs explicit módon szabályozva. Alacsony valószínűség (a gyűjtés a
  „saját hangszer, saját kéz" körre szűkül, §1), de érdemes egy sort
  szentelni neki egy jövőbeli manifest-revízióban.
- **security NOTE-3:** a harness `_read_jsonl` csak `ValueError`-t fog el;
  egy patologikusan mélyen ágyazott JSON input (`RecursionError`)
  elkapatlanul terjedne. Nem biztonsági kérdés ebben a körben (nincs
  bizalmatlan bemeneti forrás — a manifest tiltja a nem-consentelt adatot),
  csak akkor releváns, ha a harness valaha bizalmatlan JSONL-t dolgozna
  fel.
- **Kötelező javítás:** egyik sem kötelező ebben vagy a fix-körben.
- **Státusz:** OPEN (dokumentált, nem blokkoló, nem ebben a körben esedékes)

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (handoff §10.2) | Ellenőrizve (saját `/tmp/review-e05-r17` klón, GitHub-ról) |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld (No issues found) | ✅ zöld |
| test test/tooling | zöld (43 teszt) | ✅ zöld (43 teszt, „All tests passed!") |
| architecture | zöld (12 allowlistelt eltérés) | ✅ zöld (ugyanaz a 12) |
| secrets | (nem jelentve a handoffban) | ✅ zöld (1958 fájl, 0 lelet) |
| l10n | (nem jelentve a handoffban) | ✅ zöld (964 üzenet) |
| `--self-test` | 9/9 PASS | ✅ 9/9 PASS reprodukálva — DE ld. BLOCKER-1: a zöldség nem bizonyítja a helyes irányt |
| CI (teljes suite + property + APK/full-gate) | — | Merge előtt az orchestrátor dispatch-eli (`tools/round-ci-plan.py` → `full-gate.yml` + `router-ci.yml`, natív út nincs érintve) |

## Architektúra + termékhatárok

A diff kizárólag `docs/**` és egy önálló, tiszta-stdlib `ml/vision/*.py`
fájlt érint — nincs Flutter/Dart production kód, nincs import-lánc a
`lib/`-be, nincs hálózati hívás, storage-írás, mic/camera-plugin hívás,
secret. A harness maga nem fut a shipping appban (`test/tooling` gate köti
be, nem `lib/`). Nincs lifecycle-erőforrás a diffben.

## Biztonsági/adatvédelmi review (risk=high, kötelező)

Dedikált `security-reviewer` subagent futott (2026-08-07, saját izolált
worktree, `c2ed5ca..e5450b2` diff-tartományon). **Verdikt: nincs CRITICAL,
nincs BLOCKER. 1 MAJOR** (lásd MAJOR-1 fent) **+ 4 NOTE** (N2/N3 fent
folytatva a fő megállapítások közé).

Pozitív, ellenőrzött megfigyelések:

- **Scope-audit** — a security-reviewer FÜGGETLENÜL ugyanarra a
  következtetésre jutott, mint az orchestrátor saját scope-audit futása:
  `git diff --stat c2ed5ca..e5450b2` 6 fájl, mind az engedélyezett úton;
  a `docs/adr/0187-*.md` jelenléte kizárólag az orchestrátor saját
  `e5450b2` commitjának köszönhető (szerző „Ralph (autonomous)"), az
  implementer öt commitja (`c10bf6a`…`882b127`) nem nyúlt hozzá.
- **Secrets/PII** — tiszta. Nincs token/kulcs/jelszó a diffben; minden
  consent-rekord-példa nyilvánvalóan fiktív (`c-0007`,
  `2026-XX-XXTHH:MM:SSZ`); nincs email/telefonszám/IP/valódi elérési út.
- **Prompt-injection felület** — tiszta. A manifest/README/baseline
  KORLÁTOZÓ őrsáncok (tiltott-forrás lista, consent-követelmény,
  on-device hivatkozás), nem scope-bővítők; nincs beágyazott, utasításnak
  álcázott adat.
- **Python harness biztonsága** — tiszta. Import-lista kizárólag
  `argparse, json, math, sys, dataclasses, typing`; nincs
  `eval/exec/compile/pickle/marshal/__import__`, nincs `os/subprocess/
  socket/urllib/requests`, nincs `os.environ`, nincs író-módú `open`. A
  deszerializáció sima `json.loads` (nem biztonsági kockázat). A
  `--input` kapcsoló csak OLVAS, futtatva (self-test, üres fájl,
  `/etc/hostname`, patologikus bemenet) egyetlen fájlt sem írt.
- **On-device határ** — tiszteletben tartva. A manifest §3.7 kifejezetten
  tiltja a felhő-alapú detekciós API kimenetét (ADR 0178 §Döntés 1-re
  hivatkozva), és az eval-utat „offline, lokális modellel" írja le.
- **A logika-irány kérdés (BLOCKER-1)** — a security-reviewer, a
  promptban kapott utasítás szerint, NEM adta ezt új leletként, DE
  megerősítette a megfigyelést: a spec (§6.2/ADR Döntés 4, javítva) és a
  §10 handoff narratíva (implementer-szekció, még a régi irányt idézi)
  jelenleg egymásnak ellentmond — ezt a fix-kör zárja. A security-reviewer
  saját, kalibrált megjegyzése: a blast radius korlátozott, mert az ADR
  0181/0187 mindkét esetben KÖTELEZŐ felhasználói megerősítést ír elő a
  detektor-javaslat elfogadása előtt.

MAJOR/CRITICAL összesen: **1** (MAJOR-1, fent részletezve, felvéve a
fix-kör findings-jébe).

## Javító kör 1 — zárás (2026-08-07)

MiniMax M3 ugyanabban a munkapéldányban (`/home/ubuntu/ss-mm-e05-r17`),
ugyanazon a branchen javított, `/home/ubuntu/ss-mm-e05-r17-fix1-prompt.md`
findings-listával (BLOCKER-1 + MAJOR-1 kötelező, N2 opcionális). Eredmény:
`status=done`, négy commit (`07ae19c` consent-mező, `48c0fd8` exit-kód,
`fe99458` self-test-fordítás, `3748821` §10 handoff-frissítés).

- **BLOCKER-1 → FIXED.** `decision()` belépési feltétele `<=`-ra cserélve
  (`mean_anchor_error <= MEAN_ANCHOR_ERROR_MAX` nyitja a
  `PRODUCTION_CANDIDATE` ágat), a docstring a helyes irányra frissítve, a
  három érintett self-test asszerció (0.029/0.030/0.031) átnevezve és
  megfordítva, a p95-only/failure-rate-only kiegészítő tesztek mostantól
  ténylegesen a saját águkon haladnak át (nem véletlenül adnak helyes
  címkét). **Független újra-ellenőrzés** (friss `/tmp/review-e05-r17-fix1`
  klón, GitHub-ról, NEM az implementer munkapéldánya): `--self-test` 9/9
  PASS, MINDHÁROM érintett cella a helyes irányban
  (`mean=0.029`→`PRODUCTION_CANDIDATE`, `mean=0.030`→
  `PRODUCTION_CANDIDATE` boundary-qualifies, `mean=0.031`→`EXPERIMENTAL`).
  **Ezen felül** egy a self-testtől teljesen független, frissen generált
  szintetikus JSONL-lel (`--input`, NEM `--self-test`) is megismételve:
  egy 200 frame-es „jó" detektor (mean≈0.0098) → `PRODUCTION_CANDIDATE`,
  egy 200 frame-es „rossz" detektor (mean≈0.0799) → `EXPERIMENTAL` — a
  BLOCKER zárása MÉRVE, nem a self-test saját köréből, és nem az
  implementer önjelentéséből feltételezve.
- **MAJOR-1 → FIXED.** `ml/vision/dataset_manifest.md` §2 táblázata egy
  9. sorral bővült (`annotator_privacy_guideline`, SDD §31.2 7. elemére
  hivatkozva) — a séma mind a 7 kötelező SDD-elemet átviszi.
- **N2 (opcionális) → FIXED.** A hibás-bemenet út mostantól explicit
  `sys.exit(EXIT_BAD_INPUT)`-ot hív (3), nem az implicit
  `SystemExit(str)` (1) útvonalat. Független újra-ellenőrzés: `--input
  /etc/hostname` → kilépési kód **3**.
- **Scope:** a fix-kör diffje (`f07e779..3748821`, az orchestrátor review-
  commitja utáni tartomány) `python3 tools/scope-audit.py --base f07e779`
  szerint **OK** (3 changed path — `dataset_manifest.md`,
  `evaluate_geometry_baseline.py`, a brief §10 szekciója — mind az
  engedélyezett listán).
- **Gate — független újra-futtatás** (friss `/tmp/review-e05-r17-fix1`
  klón): `tools/round-gate.sh test/tooling` **6/6 ZÖLD**.

## Merge-döntés

**Merge ENGEDÉLYEZETT** — 0 nyitott BLOCKER/MAJOR. N1 (halott defenzív ág)
és a security-review N1–N3 dokumentált, nem blokkoló follow-up. Hátravan:
CI-dispatch (`full-gate.yml` + `router-ci.yml`, `tools/round-ci-plan.py`
szerint, natív út nincs érintve) és az exact-SHA zöld kapu a merge SHA-ján
(ADR 0052/0086 §2).
