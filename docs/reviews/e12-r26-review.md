# E12-R26 — Review (rollback és disaster recovery drill)

- **Kör:** `E12-R26` · **Branch:** `sonnet-impl/e12-r26-rollback-and-disaster-recovery-drill`
- **PR:** [#522](https://github.com/wolfcasaba/strumsight/pull/522) · **Head SHA:** `9865de60`
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude (Opus 5), read-only, izolált `/tmp/e12r26-review` klónban
- **Kockázat:** `high` → `security-reviewer` futtatása KÖTELEZŐ (§4)
- **Dátum:** 2026-09-02

## 1. Scope-audit

Gépi audit a wrapperből: `scope_audit=ok`, `scope_audit_base=e6e9e0c1`,
`scope_audit_changed=5`. Saját, független ellenőrzés:

```
$ git diff --stat e6e9e0c1..HEAD
 backend/tests/test_rollback_drill.py               | 325 +++++
 docs/operations/disaster-recovery-drill.md         | 140 +++
 docs/rounds/e12-r26-...-drill.md                   |  92 +++
 test/tooling/rollback_policy_test.dart             | 223 +++
 tool/release/verify_rollback.py                    | 524 +++++
 5 files changed, 1304 insertions(+)
```

Mind az öt a brief `allowed_paths` listáján. A tiltott zóna érintetlenségét
függetlenül újramértem:

```
$ git diff --stat origin/main -- backend/scripts docs/operations/backend-deploy.md \
    docs/operations/database-recovery.md docs/adr docs/release lib .github tools test/core
(üres)
```

**Nincs scope-sértés.** A `dirty_files=1` jelzés-mezőt kivizsgáltam (L21): a fa a
`done` után tiszta (`git status --porcelain` üres), a jelzés pillanatában a
`.codex-round-status` írása volt folyamatban. Nincs elveszett munka.

## 2. Pre-flight-revízió helytállósága (§0.0.1)

A kör két acceptance-premisszáját a pre-flight mérve hamisnak találta. A
review a MÉRÉST is újrafuttatta, nem csak a következtetést fogadta el:

| Állítás | Újramérve |
|---|---|
| flag-cache nem létezik | `grep -rn "cache" lib/core/feature_flags/` → EGYETLEN találat, a `feature_flag_source.dart:72` doc-comment („None of these steps caches…"); ADR 0446:96 a cache-elt utolsó ismert értéket kifejezetten TILTJA |
| nincs API-verziózás | `grep -rn "api_version\|API_VERSION\|min_client\|X-Client" backend/app/*.py` → csak `tutor_openai_base_url`; a routerek (`auth`, `settings`, `diagnostics`) verziózatlanok |

A revízió helyes, és **nem lazítás**: mindkét cella szigorúbb lett annál, mint
amit az eredeti (mérhetetlen) szöveg kért — az A4 a `T = 0` elavulási ablakot
követeli, ami erősebb állítás bármely véges `T`-nél.

## 3. Valódi-sértés próbák (független, izolált `/tmp` klón)

Nem elégedtem meg az implementer saját (A1) próbájával — három FÜGGETLEN
mutációt futtattam a klónon, majd visszaállítottam. Baseline: `6/6 zöld`.

| # | Mutáció | Mért eredmény |
|---|---|---|
| P1 | `FeatureFlagResolver` memoizálóvá tétele (`Map<String, FeatureFlagResolution> _cache`, `resolve` cache-elt ágra) | **A3 ÉS A4 PIROS** — a küszöb-cellahármas `k` cellája és a round-trip is megfogja |
| P2 | `\| 1.559s \|` → `\| kb. 1.5 perc \|` a jegyzőkönyvben | **A5(a) ÉS A5(b) PIROS** |
| P3 | `\| 0.823s \|` → `\| nem mértük \|` a jegyzőkönyvben | **A5(b) PIROS** |
| — | mindhárom mutáció visszaállítása | `6/6 zöld` |

A P1 az e kör legfontosabb mérése: bizonyítja, hogy az A4 cella nem
„véletlenül zöld", hanem **pontosan azt a hibás implementációt fogja meg**,
amit a §6.1 mérce-mátrix előír (memoizáló resolver → a kikapcsolás nem hat).

Az implementer A1-próbáját is elfogadom: a mutált `check_migration_head`
mellett `1 failed, 5 passed`, pontosan a
`test_verify_rollback_fails_on_migration_head_mismatch` cellával, és a
visszaállítás után `6 passed` (jegyzőkönyv §5, §10.3).

## 4. Leletek

### MAJOR-1 — a `verify_rollback.py` 29 táblából 2-t hasonlít, és „PASS"-t ad egy 27 táblát vesztő visszaállításra

`tool/release/verify_rollback.py:69`, `:255–257`, `:265–267`, `:290–292`

A `security-reviewer` mérte, én **függetlenül reprodukáltam**:

```
$ cd backend && python3 -c "from app import models; from app.database import Base; print(len(Base.metadata.tables), sorted(Base.metadata.tables))"
2 ['user_settings', 'users']

$ STRUMSIGHT_DATABASE_URL=sqlite:////tmp/e12r26-verify/src.db PYTHONPATH=. python3 -m alembic upgrade head
$ sqlite3 → select name from sqlite_master where type='table'
29 ['alembic_version', 'community_blocks', 'community_bookmarks', … 'community_reports', 'user_settings', 'users']
```

A `verify_rollback.py:69` csak az `app.models`-t importálja, ezért a
`Base.metadata` **2 táblát** ismer, miközben az élő séma **29-et** tartalmaz. A
`:255–257` `continue`-ja a dumpban nem szereplő táblát csendben kihagyja, a
`:290–292` PASS-szövege pedig a DUMP tábláinak számát (`len(tables)`) írja ki,
nem az ténylegesen összehasonlítottakét — így a „2 table(s) match" a
TELJESSÉG látszatát kelti.

**Reprodukált failure scenario:** forrás DB `users=1, community_profiles=1` →
backup → restore friss célra → `verify_rollback.py` → `[PASS] record_counts: 2
table(s) match`, `OVERALL: PASS`, `EXIT=0`, miközben a célban
`community_profiles=0` — **az adat elveszett**. Két további reprodukált változat:
(a) tábla nélküli cél helyes `alembic_version`-nel → PASS (`:265–267` a hiányzó
táblát 0 sornak veszi); (b) csupa ismeretlen tábla-nevű dump → NULLA
összehasonlítás, mégis PASS.

**Ez a kör KÖZPONTI állítását üresíti ki** (§0.0.1 P3 / ADR 0487 D1: a
bizonyíték SZÁMSZERŰ), és pontosan a [L566](../LESSONS.md#l566) fail-OPEN
hibaosztály — ugyanaz a mintázat, mint az E12-R25 MAJOR F1-e (a nem-rekurzív
bejárás miatt átengedett többletfájl).

**Fontos elhatárolás:** a GYÖKÉROK a `backend/scripts/backup.py` szűk
`Base.metadata` importja — az **tiltott zóna**, tehát nem javítható itt, hanem
a jegyzőkönyv **A6 runbook-leletévé** kell tenni (ez lényegesen súlyosabb
lelet, mint a §7-ben ma szereplő `-m`-hívás). Ami a kör hatáskörében VAN: a
`verify_rollback.py` nem adhat teljességet sugalló PASS-t egy 2/29-es
összehasonlításra — az élő tábla-halmaz és a dump tábla-halmaza közti minden
eltérés FAIL, és a PASS-szöveg a ténylegesen összehasonlított darabszámot írja.

### MAJOR-2 — a commitolt jegyzőkönyv mérhetően hamis tényállítást tartalmaz

`docs/operations/disaster-recovery-drill.md:62` (7. lépés): „ZÖLD —
`revision=e09_r27_0020, users=1, user_settings=1` **(+ minden Community tábla
`0` sorral)**".

**Mérve:** a `backup.py` kimenetében Community tábla **nem szerepel**, és a dump
JSON kulcsai kizárólag `['user_settings','users']`. A zárójeles állítás nem a
futás kimenetéből származik — a jegyzőkönyv (az A1/A6 bizonyíték-artefaktuma) a
teljes lefedettség látszatát kelti. Ez a MAJOR-1 párja a dokumentum oldalán.

### MAJOR-3 — az üres `{}` flag-profil PASS-t ad, opt-out nélkül

`tool/release/verify_rollback.py:404–422`; a szerződést állító cella:
`backend/tests/test_rollback_drill.py:267–277`.

**Reprodukálva:** `--expected-flag-profile exp.json --observed-flag-profile
obs.json`, mindkettő `{}` → `all_keys` üres → a ciklus nem fut →
`[PASS] flag_profile: 0 flag(s) match`, `OVERALL: PASS`. A dimenzió így **PASS**-ként
esik ki, nem `SKIPPED`-ként — tehát a jegyzőkönyvben sem látszik, ami **rosszabb**,
mint a `--no-flag-profile` út. A P4 „kizárólag explicit kapcsolóval hagyható ki"
szabálya megkerülhető, és a cella saját kommentje („the ONLY way to leave it
out is the explicit opt-out") mérhetően nem teljesül.

### MAJOR-4 — korlátlan `{value!r}` visszhang: PII + bcrypt hash kerülhet a riportba

`tool/release/verify_rollback.py:158–163` (kisebb hatással `:346`, `:352`).

**Reprodukálva:** ha az operátor a `--expected-flag-profile`-ra tévedésből a
backup dumpot adja meg (mindkettő „egy JSON fájl útvonala"), a `load_flag_profile`
az első nem-bool értéknél az EGÉSZ értéket kiírja:

```
flag profile <path> key 'tables' must be a boolean, got {'users': {'count': 1, 'rows':
[{'id': 1, 'email': 'victim@example.com', 'hashed_password': '$2b$12$…
```

A string a stdoutra, a `--json` riportba és a jegyzőkönyvbe másolható kimenetbe
kerül. **Pozitív ellenpont, mérve:** a `load_backup` (`:140–141`)
`JSONDecodeError`-szövege csak pozíciót tartalmaz, nem tartalmat — a backup dump
a normál úton NEM szivárog.

### MINOR-1 — a modell-manifest `path` mezője ellenőrizetlenül fűződik a `project_root`-hoz

`tool/release/verify_rollback.py:354–358`. Mérve: `"path": "/etc/passwd"` →
`Path(root) / "/etc/passwd"` = `/etc/passwd`, a fájl beolvasva és hashelve, a
`detail` kiírja a sha256-ot; `../../../root/.ssh/id_rsa` → létezés-orákulum.
Csak olvasás, a tartalom nem jelenik meg. Ma a manifest követett, megbízható
bemenet — de a MODELL-ROLLBACK használati eset épp az, hogy a manifest egy
VISSZAÁLLÍTOTT csomagból jön, ahol a bizalmi szint alacsonyabb.

### MINOR-2 — nem-SQLAlchemy hiba kiszökik: nincs riport, a többi dimenzió le sem fut

`tool/release/verify_rollback.py:196–209`, `:249–284` — csak `SQLAlchemyError`
van elkapva. Mérve egy Postgres-URL-lel (amire a jegyzőkönyv §4 explicit
hivatkozik): `ModuleNotFoundError: No module named 'psycopg2'`, traceback,
`EXIT=1`, **de riport nélkül** — a `model_manifest`/`flag_profile` dimenzió le
sem fut, tehát nem „FAIL dimenzió", ahogy a P4 előírja. (Pozitív: a DSN/jelszó
nem szivárog a traceback-be.)

### MINOR-3 — a „csak olvasó" ellenőrző fájlt hoz létre

`tool/release/verify_rollback.py:119–123` + `:198`: elgépelt
`--database-url sqlite:///…/typo.db` után egy üres, 0 bájtos `typo.db` marad a
lemezen (a riport helyesen FAIL). Nem destruktív — a grep
`write|open(|mkdir|remove|unlink|rmtree|subprocess|shell|eval(|exec(|os.system`
a fájlon **0 találat**.

### MINOR-4 — az A5 időtartam-mintája a sor BÁRHOL részére illeszkedik

`test/tooling/rollback_policy_test.dart:171`, `:191–212`. Egy üres
időtartam-cellájú lépéssor, amelynek PARANCS-szövegében szerepel pl.
`--max-time 30s`, zölden átmenne. Az A6-cella (`:214–221`) pusztán a szakaszcím
létezését nézi, tartalmat nem. A mérce iránya helyes, de gyengébb, mint az
állítása.

### MINOR-5 — a jegyzőkönyv túlállít az A3 cella erejéről

`docs/operations/disaster-recovery-drill.md:40–45`:

> „a resolver-szintű mérés (1. sor) **explicit bizonyítja**, hogy a kikapcsolás
> nem érinti az idegen adattárat (a teszt egy független `userData` listát
> figyel a kikapcsolás/visszakapcsolás körül, byte-for-byte egyezéssel)"

**Mérve:** a `userData` egy teszt-lokális Dart lista
(`test/tooling/rollback_policy_test.dart:77`), amelyhez a vizsgált kód
(`FeatureFlagResolver.resolve`) nem fér hozzá — nincs paraméterként átadva,
nincs globális állapotban. A két `expect(userData, originalSnapshot)` állítás
ezért **szerkezetileg képtelen elbukni**: semmilyen resolver-implementáció (még
egy szándékosan „takarító" sem) nem tudná pirosra váltani. A P1 próba ezt
alátámasztja: az A3 a memoizálástól lett piros, nem az adat-ágtól.

**Ami az A3-ban VALÓBAN mér** (és a P1 bizonyítja): a **feloldás-round-trip** —
`emergencyOff` → a forrás visszabillentése → `local` ugyanazon a
resolver-példányon. Egy „latch-elő" (a vész-kikapcsolást beragasztó)
implementáció ezen elbukik. Ez valódi és értékes mérce.

**Következmény:** a §6.1 mátrix „A kill switch takarít (adatot töröl) → A3
piros" sora ezen a rétegen **nem teljesíthető** — a resolvernek nincs
adathozzáférése, tehát nem is takaríthat. Az adat-megmaradás valódi mércéje a
backend-oldali A1 lánc (rekordszám-egyezés restore után). A jegyzőkönyv
mondatát ehhez kell igazítani.

**Miért csak MINOR:** a hibás állítás egy COMMITOLT dokumentumban van, tehát a
jövőbeli olvasó erősebbnek hiszi a fedezetet, mint amilyen — de sem a kód, sem
a mérce nem hibás, és a mondat javítása a kör saját, engedélyezett fájljában
történik.

### NOTE-1 — `check_record_counts` csak a metszetet hasonlítja (ma nem elérhető rés)

`tool/release/verify_rollback.py:255–257` a `Base.metadata.sorted_tables`-ön
iterál, és `continue`-zik minden táblára, ami nincs a dumpban; a PASS-üzenet
viszont `len(tables)`-t (a DUMP tábláinak számát) írja ki.

**Megmértem, hogy elérhető-e a fail-open:** nem. A `backend/scripts/backup.py:63`
UGYANAZON a `Base.metadata.sorted_tables`-ön iterál, és a hiányzó táblákat is
felveszi (`{"count": 0, "rows": []}`), tehát valódi dumpnál a két halmaz
egybeesik — nincs átugrott tábla, és a kiírt darabszám sem inflált. Kézzel
szerkesztett dumpnál (nem ez a kör fenyegetettségi modellje) egy ismeretlen
tábla csendben kimaradna. **Nem merge-blokkoló**, de érdemes tudni: a
`verify_rollback` fedezete a `backup.py` tábla-listájához KÖTÖTT, nem az élő
adatbázis tényleges tábláihoz.

### NOTE-2 — a `SKIPPED` dimenzió ideje nem mérés

`verify_rollback.py:426` — `skipped_flag_profile` fixen `0.0` `elapsed_seconds`-öt
ad. A mező dokumentációja szerint „measured". Ez őszinte (nem futott semmi), de
ez az egyetlen pont, ahol az érték nem mérésből származik.

### NOTE-3 — az A5(a) minta a `~` karaktert a FÁJL EGÉSZÉBEN tiltja

`test/tooling/rollback_policy_test.dart:172` — a becslés-minta soronként
illeszkedik az egész fájlra, nem csak a lépés-sorokra. Egy jövőbeli, teljesen
legitim `~` (pl. útvonalban) pirosra váltja a kört. Ez a brief §5.1
szigorának szándékos következménye; azért rögzítem, hogy egy következő kör ne
kódhibának nézze.

### A6 — a runbook-lelet valódiságát külön ellenőriztem

A jegyzőkönyv §7 állítása (`python scripts/backup.py` → `ModuleNotFoundError:
No module named 'app'`, mert CPython a szkript saját könyvtárát teszi a
`sys.path[0]`-ra) **helyes**, és a `docs/operations/database-recovery.md`
tényleg így dokumentálja a parancsot. A kör helyesen **nem javította** —
tiltott zóna, és az A6 pont épp ezt a fegyelmet méri. A javítás egy jövőbeli
kör dolga.

## 5. Zöld kapu — exact-SHA evidencia a `9865de60` head SHA-n

A CI-tervet a tervező adta (`tools/round-ci-plan.py`): `full-gate.yml`,
`native_gate = false`, `router_ci_expected = true` (`docs/rounds/**` érintve).

| Workflow | Run | Eredmény |
|---|---|---|
| Full Gate (no APK) | [33590667440](https://github.com/wolfcasaba/strumsight/actions/runs/33590667440) | `success` |
| Router CI | [33590664779](https://github.com/wolfcasaba/strumsight/actions/runs/33590664779) | `success` |
| Backend CI | [33590664716](https://github.com/wolfcasaba/strumsight/actions/runs/33590664716) | `success` |

Mindhárom `headSha = 9865de60d5d420a155696507cee9f0c5621f4924`, azonos a lokális
HEAD-del. A Backend CI zöldje egyben azt is bizonyítja, hogy a
`tool/release/verify_rollback.py` a CI környezetében is importálható (a
`sys.path` beszúrás és az `app.*` import működik), nem csak ezen a boxon.

## 6. Biztonsági review (`risk = high`, KÖTELEZŐ)

`security-reviewer` ügynök, read-only, a teljes köri diffen. Vizsgált felület:
adatvesztés (a restore célja mindig ideiglenes-e), titok-szivárgás (a dump
PII-t és bcrypt hasheket hordoz — szivároghat-e a COMMITOLT jegyzőkönyvbe),
fail-open utak, path traversal / parancs-injekció, prompt-injection.

**Eredmény: nincs BLOCKER.** KÉT független `security-reviewer` futás készült (az
első 40 percig futott, ezért közben egy másodikat is indítottam) — **mindkettő
egymástól függetlenül a MAJOR-1-et és a MAJOR-2-t találta meg elsőként**, ami a
két lelet valódiságát erősen alátámasztja. Összesítve: nincs BLOCKER, 4 MAJOR,
7 MINOR, 4 NOTE.

A második futás két további leletet adott, amelyek szintén a javító körbe
mennek: **MINOR-6** — a `DimensionResult.ok` (`verify_rollback.py:86–88`)
denylist-alapú (`!= FAIL`), tehát egy ismeretlen/elgépelt státusz automatikusan
`ok=True`; **MINOR-7** — a jegyzőkönyv két „ZÖLD" cellája nem mér semmit: a 9.
lépés a flag-profil MINDKÉT oldalára UGYANAZT a fájlt adja (tautológia), a §7
`--force` + `--confirm-target` állítása pedig nem ebből a gyakorlatból
következik (nulla `--force` előfordulás; minden restore üres célra ment, ahol a
D4 kapu tervezetten nem aktiválódik). A negatív leletek (amit végignézett, és nem talált) bizonyítékkal:

| Kérdés | Bizonyíték |
|---|---|
| Írás a repo-fába / `backend/strumsight.db`-re | a 6 backend cella lefutása után `git status --porcelain` tiszta; `*.db` nem keletkezett; minden teszt-DB-URL `tmp_path`-ból épül (`test_rollback_drill.py:70,90,135,171,210,244,291`) |
| ADR 0449 D4 kettős megerősítés megkerülése | a kör ÚJ kódjában sehol nincs `--force`/`--confirm-target`; minden `restore_script.main` hívás ÜRES célra megy, ahol a D4 kapu nem is aktiválódik; `backend/scripts/**` nincs a diffben |
| Titok/PII a commitolt jegyzőkönyvben | `git diff … -- docs/` grep `/home/`, e-mail-minta, 40+ hex, `$2[aby]$`, `Bearer`, `token`, `BEGIN … PRIVATE` → **0 találat**; az útvonalak `/tmp/e12-r26-drill/*` |
| Parancs-injekció / RCE | `subprocess\|shell\|eval(\|exec(\|os.system\|__import__\|input(` a `verify_rollback.py`-n → **0 találat**; minden bemenet `json.loads`-szal, adatként |
| Prompt injection | nincs LLM/provider/tool-calling ebben a körben; beolvasott tartalom sehol nem vezérel kontrollfolyamot |
| Ellátási lánc | nincs új pip-csomag, nincs `pubspec` változás — csak stdlib + a backend meglévő SQLAlchemy/Alembic |

## 7. Verdikt — **CHANGES REQUESTED** (javító kör), majd a lezárás

A gate és a TELJES CI zöld volt, a scope tiszta, a pre-flight-revízió helyes, a
gyakorlat valóban lefutott — **a lényeget mégis a review találta meg**, ugyanúgy,
mint az E12-R25-ben: egy teljesen zöld mérce mögött egy fail-OPEN rés, ami a kör
saját központi állítását (A1 „nincs adatvesztés", SZÁMSZERŰEN) 29 táblából 2-re
vakítja, miközben „PASS"-t ír ki.

**Nyitva a javító körhöz:** MAJOR-1, MAJOR-2, MAJOR-3, MAJOR-4, MINOR-1,
MINOR-2, MINOR-4, MINOR-5, MINOR-6, MINOR-7. (MINOR-3 és a NOTE-ok nem
igényelnek változtatást — rögzítve maradnak.)

A javító kör ugyanazzal a motorral (`sonnet-impl`), ugyanazon a branchen megy, a
fenti leletlistával; minden javításhoz ÚJ mérő cella tartozik, és a §5 exact-SHA
CI-kapu az új HEAD-en ÚJRA lefut.
