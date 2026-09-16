# Production-readiness hiánylista — 2026-09-16

**Measured against:** `main` @ `bedfd1e` (a `claude/workflow-production-readiness-r1866i`
ág induló fája), a benne látható CI-futások, és a 2026-09-16-án nyitott két élő ág +
három PR. A jelentés **pillanatkép**: minden állítás mögött fájl-útvonal, workflow
run-id vagy PR-szám áll. Ahol a bizonyíték ebből a konténerből nem szerezhető meg
(pl. GitHub-secret megléte), ott ez ki van mondva — nem tippel.

**Mérési környezet korlátja.** Ez a távoli konténer **nem tud Flutter/Android
buildet futtatni**: nincs SDK, és a letöltés proxy-403-ba fut
(`storage.googleapis.com`, `dl.google.com`, `pub.dev`, `maven.google.com`, mérve
2026-09-16). A mérés forrása ezért a CI és a fában lévő artefaktumok. A felhasználó
saját boxán (PR #601) van Flutter 3.44.2 + Android SDK 36, de ott **APK-t sem lehet
lokálisan buildelni** (x86 build-tools ARM64-en), és emulátor sem indul (nincs KVM) —
azaz **az APK egyetlen forrása a CI**, az elfogadásé pedig a valódi eszköz.

---

## 1. Összegzés

- **A minőségi kapulánc érett és zöld.** A `flutter-gates` összetett lépés (format,
  analyze, architecture, secret-scan, l10n-paritás, asset-gate, teljes `flutter test`,
  randomizált property-gate) `main`-en zölden fut: `full-gate.yml` run **33998450680**
  és **34373102220**, `build-apk.yml` run **33961449605**.
- **A produkciós kiadási út viszont soha nem lett végigjárva.** A
  `.github/workflows/release-apk.yml` élete során **kétszer** futott
  (**30514352164**, **30521935406**, mindkettő 2026-07-30), és **mindkettő elbukott a
  „Production signing prerequisites" jobon** — a 4 aláíró secret hiányzott. **Aláírt
  produkciós APK még soha nem készült.**
- **A gépi munka lényegében kész, a kiadás emberi kapui mind nyitva vannak.** A
  `docs/sdd/program-completion-report.md` §5 nyolc emberi kapuja **mind `NYITOTT`**
  (`docs/sdd/program-completion-report.md:138-145`), a `docs/release/ga-record.md:33`
  `ga_status: not-yet`, és a `docs/governance/04-release-checklist.md` **mind a 30
  sora pipálatlan** (`grep -c '\[ \]'` → 30, `grep -c '\[x\]'` → 0).
- **A sor nem tud magától haladni.** `docs/execution/pipeline-queue.tsv`: **332 `done`,
  53 `hold`, 0 `pending`** — a driver csak `pending` sort enged be, tehát a lánc ma
  **nem admittál semmit**. A továbblépés emberi döntés (hold → pending), nem gépi.
- **A kockázat átterelődött a merge-integrációra.** Két élő ág (összesen ~130 fájl,
  +7800 sor) vár merge-re, plusz három nyitott PR, ebből kettő konfliktusos
  (`mergeable_state: dirty`): #593, #594. A leghosszabb késleltetést a golden-PNG és a
  `HANDOFF.md` ütközései okozzák.
- **A funkcionális hiány mérhető és behatárolt.** A `E17` „full wiring" fejezet 13
  köre `hold`-on áll (`E17-R02`…`R14`), és emiatt a közösségi képernyők üresek: a
  #594 PR leírása szerint a `clubs.py` / `notifications.py` backend-router **nem
  létezik**.
- **A végső elfogadási predikátum továbbra is emberi:** valódi gitáros, valódi
  telefonon, aláírt (vagy legalább sideloadolt) buildből. Ebből **nulla dokumentált
  munkamenet** van.

---

## 2. Workflow-leltár

| workflow | trigger | mit mér | utolsó mért futás | production-releváns hiány |
|---|---|---|---|---|
| `.github/workflows/build-apk.yml` | `workflow_dispatch` (ADR 0086) | teljes `flutter-gates` lánc + song-séma és song-fixture kapuk + `flutter build apk --release --dart-define=STRUMSIGHT_ENV=development` + coverage | **33961449605** (main, sikeres, 2026-09-05); **34982557486** (ág, sikeres, 2026-09-15) | az APK **debug-aláírású**, `development` env — sideloadolható, de **nem store-képes** |
| `.github/workflows/full-gate.yml` | push / dispatch | ugyanaz a kapulánc APK nélkül | **33998450680**, **34373102220** (main, sikeresek) | nincs — ez a napi minőségi háló |
| `.github/workflows/release-apk.yml` | `workflow_dispatch` | 4 kötelező secret előfeltétel-job → `STRUMSIGHT_REQUIRE_RELEASE_SIGNING=true`, `--dart-define=STRUMSIGHT_ENV=production`, aláírt release APK | **30514352164**, **30521935406** (2026-07-30) — **mindkettő bukott** a `Production signing prerequisites` jobon (`release-apk.yml:10`) | **P0** — a secretek megléte innen nem igazolható; aláírt produkciós artefaktum nincs |
| `.github/workflows/record-goldens.yml` | dispatch (tulajdonosi engedély, 2026-09-15, `bedfd1e`) | x86 golden-felvevő, a PNG-ket visszacommitolja | a `main` egyfájlos commitja (`bedfd1e`) | ág-ütközés forrása (lásd §4) |
| `.github/workflows/router-ci.yml` | push (path-szűrt) | router-carve-out kapuk | — | nincs |
| `.github/workflows/lab-apk.yml` | push `main`, `lab_build.json` | lab-célú APK | — | nem produkciós csatorna |
| `.github/workflows/backend-ci.yml` | push | backend tesztek | — | staging-migrációs próba **nem** része |
| `.github/workflows/chord-train.yml`, `ml-train.yml`, `dsp-probe.yml`, `tutor-eval.yml` | dispatch | modell-tréning és kiértékelés | — | valós korpusz hiányzik (lásd §5 P2) |
| `release-candidate.yml` | — | — | **nem létezik** | csak javaslat: `docs/release/workflows/release-candidate.proposal.yml` (ADR 0488 D1/D8, `K-RC-01`) |

Aláírási politika (a fában, működőképesen): `android/app/build.gradle.kts` fail-closed
release-aláírás (env vagy `android/key.properties`, debug-keystore/alias elutasítva ha
`STRUMSIGHT_REQUIRE_RELEASE_SIGNING=true`, ADR 0448). `applicationId =
"com.wolfcasaba.strumsight"` (`android/app/build.gradle.kts:116`).

---

## 3. Kapu-státusz

| kapu | állapot | bizonyíték |
|---|---|---|
| Minőségi kapulánc a `main`-en | **zöld** | `full-gate.yml` 33998450680, 34373102220 |
| Teljes teszt-suite + property-gate (`PROPERTY_SEED=run_id`) | **zöld** | `build-apk.yml` 33961449605 |
| Sideloadolható (debug-aláírt) APK | **előáll** | `build-apk.yml` 33961449605 artefaktum |
| Aláírt **produkciós** APK | **soha nem állt elő** | `release-apk.yml` 30514352164, 30521935406 — bukott |
| RC-összeállító workflow telepítve | **nincs** | csak `docs/release/workflows/release-candidate.proposal.yml` |
| Release-checklist | **0/30 pipálva** | `docs/governance/04-release-checklist.md` |
| GA-rekord | `ga_status: not-yet` | `docs/release/ga-record.md:33` |
| Szakaszos rollout naplója | minden szakasz `pending` | `docs/release/staged-rollout-log.md` |
| Verzió / build-szám | `1.0.0+1` **26 Release és 27 tag mellett változatlan** | `pubspec.yaml:5`, `docs/release/release-history-audit.md` §4 |

---

## 4. Nyitott munka a `main`-en kívül

| ág / PR | tartalom | méret | kapu | ütközés |
|---|---|---|---|---|
| `claude/sdd-plans-quality-clarity-5ydqyy` („learner-loop") | 1–5. kör: következő-gyakorlat ajánlás, valós XP-főkönyv a Practice V2 mögött, egységes haladás-modell (`practiceStatsProvider` + streak-jóváírás), Songs fül → Song Trainer V2 könyvtár; zárja a `full-app-verification` L4+L5 pontját | 28 commit előre, 63 fájl, +3419/−237 | `full-gate` **34981957665** + `build-apk` **34982557486** zöld (`f7bcb90`) | **TISZTÁN merge-elhető a `main`-re** |
| `claude/ui-design-viral-elements-u9z9ht` („motion", Ch18 R06/R07) | streak-láng, megosztás-reveal, lépcsőzetes belépő animációk | 20 commit előre / 1 hátra, 68 fájl, +4463/−419 | `full-gate` **34955802156** + `build-apk` **34955804305** zöld (`a8a287b`) | **KONFLIKTUSOS**: add/add a `.github/workflows/record-goldens.yml`-en (saját `0a4e0c8` vs `main` `bedfd1e`); a learner-loop ággal: `HANDOFF.md`, `lib/features/today/screens/today_hub_screen.dart`, `test/ui/goldens/goldens/e13_r17_today_hub_compact.png`, `…/e13_r22_practice_result_compact.png`, továbbá közös szerkesztés `live_screen.dart`, `practice_effect_listener.dart`, `practice/public.dart`, `streak_screen.dart`, l10n ARB-k |
| **PR #593** | `E17` 5 kör `hold` → `pending` | 6 fájl | — | `mergeable_state: dirty`, a bázis-sha (`9632a96`) elavult |
| **PR #594** | Community adatréteg 1. batch: duplikált `communityChallengeRepositoryProvider` javítás + `getJson` eldobott query-paraméter javítás | 150 fájl, +17245/−582 | — | `dirty`; a leírás kimondja: `clubs.py` / `notifications.py` **nem létezik** → a klub- és értesítés-képernyők üresek |
| **PR #601** | `CLAUDE.md` — a saját box toolchain-dokumentációja | kicsi | — | **tiszta** |

**Javasolt merge-sorrend.**
1. **learner-loop** (`…-5ydqyy`) — tisztán merge-elhető, saját zöld kapuval; ez zárja a
   `full-app-verification` L4+L5-öt.
2. **motion** (`…-u9z9ht`) — rebase a friss `main`-re, a `record-goldens.yml` add/add
   ütközést a `main` `bedfd1e` verziója javára oldani, a UI-ütközéseket kézzel, majd a
   goldeneket **újrafelvenni** a `record-goldens.yml` dispatch-csel.
3. **#594** — rebase a fenti kettő után (150 fájl, a legnagyobb ütközési felület).
4. **#593** — a friss `main`-re rebase-elve; érdemben csak akkor, ha a `hold → pending`
   átállítás valóban kívánt (ez emberi döntés, §5 P2).
5. **#601** — bármikor mehet, független.

---

## 5. Production-ready hiánylista

### P0 — a kiadás nélkülük fogalmilag lehetetlen

| # | mi hiányzik | bizonyíték | zárási feltétel | ki |
|---|---|---|---|---|
| P0-1 | **Aláírt produkciós APK.** A 4 GitHub-secret (`ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`) beállítása és **egy sikeres `release-apk.yml` futás** | `release-apk.yml:10` előfeltétel-job; 30514352164 + 30521935406 bukott; `docs/release/blockers.md` R-SIGN-01 (P0) | egy `release-apk.yml` dispatch zölden előállít egy aláírt APK-t, és a run-link bekerül a `docs/release/program-baseline.md`-be | **ember** (keystore + secret) + 1 ellenőrző kör |
| P0-2 | **Valódi gitáros eszköz-teszt** — a végső acceptance predikátum | `docs/sdd/program-completion-report.md:145` (`NYITOTT`); `docs/roadmap/next-six-months.md` §1 (≥1 dokumentált munkamenet, ≥10 akkordváltás, ≥3 irányváltás, 0 összeomlás); jegyzőkönyv a learner-loop ágon: `docs/manual-testing/learner-loop-device-run.md` | egy kitöltött jegyzőkönyv a `docs/release/` alatt, a fenti küszöbökkel | **ember** (gitáros + telefon) |

### P1 — a kiadás enélkül nem védhető / nem tölthető fel

| # | mi hiányzik | bizonyíték | zárási feltétel | ki |
|---|---|---|---|---|
| P1-1 | **Verzió/build-szám emelési politika** — nincs automatikus emelés | `pubspec.yaml:5` (`1.0.0+1`); `docs/release/release-history-audit.md` §4 (26 Release, 27 tag); R-VER-01 (P1) | a build-szám minden kiadáskor gépileg emelkedik; checklist 6. sora pipálva | 1 kör (`E12-R06` tartalom) |
| P1-2 | **Valódi support-postafiók** — a `privacy-support@strumsight.app` placeholder | `docs/legal/privacy-policy-draft.md:93` („placeholder cím"); R-PRIV-01 (P1) | valós, működő postafiók a policy-ban és a store-listingben | **ember** |
| P1-3 | **Staging migrációs próbafuttatás** — a 21 backend-migráció staging-en végigfuttatva dokumentálva | `docs/release/blockers.md` R-STAGE-01 (P1); `docs/governance/04-release-checklist.md` 15. sor pipálatlan | egy próbafuttatási jegyzőkönyv + a checklist-sor pipálva | 1 kör + **ember** (staging környezet) |
| P1-4 | **Store-listing képernyőképek + Play Console feltöltés** | `docs/store/listing.md:75` („Screenshot plan (placeholder — real captures pending device-lab pass)"); R-STORE-01 (P1) | valós képernyőképek, ikon, tartalmi besorolás, és egy feltöltött build a Play Console-on | **ember** |
| P1-5 | **Megnevezett incident owner** | `docs/release/blockers.md` R-MONITOR-01; `docs/governance/04-release-checklist.md` 47-48. sor | névvel megnevezett felelős + dashboard-hivatkozás | **ember** |
| P1-6 | **RC-workflow telepítése** — ma csak javaslat | `docs/release/workflows/release-candidate.proposal.yml`; `docs/release/known-issues.md` `K-RC-01` (ADR 0488 D1/D8) | `.github/workflows/release-candidate.yml` létezik és lefutott egyszer | 1 kör |
| P1-7 | **A checklist tényleges kipipálása a MEGLÉVŐ bizonyítékokból.** Több „nyitott" blocker valójában tisztán karbantartási adósság: a threat model létezik (`docs/security/threat-model.md`, R-SEC-01), a rollback-próba lefutott (`docs/operations/disaster-recovery-drill.md`, R-ROLLBACK-01), a device-mátrix létezik (`docs/testing/device-matrix.yaml`, R-DEVICE-01), a csatorna-elkülönítést ADR 0445 rögzíti (R-CHANNEL-01) | `docs/release/known-issues.md` (2026-09-02): a tulajdonos-körök `done`, de a zárási feltételek nincsenek pipálva; `docs/release/blockers.md` Owner-annotációi elavultak | a 30 checklist-sorból mind, aminek már megvan a bizonyítéka, pipálva; a `blockers.md` sorai lezárva vagy újramérve | 1 kör (dokumentum-szinkron) |

### P2 — funkcionális és program-szintű adósság

| # | mi hiányzik | bizonyíték | zárási feltétel | ki |
|---|---|---|---|---|
| P2-1 | **`E17-R02`…`R14` „full wiring"** — 13 kör `hold`-on; emiatt a közösségi képernyők üresek (nincs `clubs.py` / `notifications.py`) | `docs/execution/pipeline-queue.tsv` (53 `hold`, ebből 13 `E17`); PR #594 leírása | a 13 kör `pending` → `done`, a közösségi képernyők valós adatot mutatnak | ember (hold feloldás) + 13 kör |
| P2-2 | **Epic 9 öt `hold` köre** (`E09-R28`…`R32`: privacy-center, offline sync, rate-limit, a11y, integráció) | `docs/execution/pipeline-queue.tsv`; `docs/roadmap/next-six-months.md` §3 (5 → 0) | mind az 5 `done` | ember + 5 kör |
| P2-3 | **Epic 10 (offline AI) döntés** — 32 kör `hold`-on, se nem fut, se nincs visszavonva | `docs/execution/pipeline-queue.tsv` (`E10-R01`…`R32`); `docs/roadmap/next-six-months.md` §4 | ≥1 kör `done` **vagy** egy visszavonási ADR | **ember** (scope-döntés) |
| P2-4 | **Ch14 valós adat-korpusz** — a modelltanításhoz nincs valós felvétel | `docs/rounds/e14-r20-strum-model-grouped-holdout-training.md` (a learner-loop ágon) STOP-feltételei: ≥3 játékos × 2 gitár × 2 szoba; `ml/corpus` **0 valós felvétel**, 0 dokumentált valós gitáros munkamenet | a korpusz-küszöb teljesül, és megvan az első hard-negative mérés (`docs/roadmap/next-six-months.md` §5) | **ember** (felvételek) + körök |
| P2-5 | **Technikai adósság alapvonal ne nőjön** | `docs/release/technical-debt.md`; `docs/roadmap/next-six-months.md` §7 | a leltár nem növekvő trendet mutat két egymást követő mérésben | kör |

---

## 6. Javasolt sorrend az első valódi produkciós kiadásig

**Gépi munka (körök, a szokásos zöld kapuval):**

1. **Merge-lánc felgöngyölítése** a §4 sorrendjében: learner-loop → motion (+ golden
   újrafelvétel `record-goldens.yml`-lel) → #594 rebase → #593 → #601.
2. **Checklist- és blocker-szinkron kör** (P1-7): a már meglévő bizonyítékokból
   (`docs/security/threat-model.md`, `docs/operations/disaster-recovery-drill.md`,
   `docs/testing/device-matrix.yaml`, ADR 0445) a `04-release-checklist.md` sorainak
   kipipálása és a `blockers.md` Owner-annotációinak újramérése.
3. **Verzió/build-szám emelési politika** bevezetése (P1-1), hogy a következő build ne
   `1.0.0+1` legyen.
4. **RC-workflow telepítése** a meglévő javaslatból (P1-6) és egy próbafuttatása.

**Emberi műveletek (gép nem tudja elvégezni):**

5. **Keystore létrehozása és a 4 GitHub-secret beállítása**, majd egy
   `release-apk.yml` dispatch — ez zárja a **P0-1**-et és adja az első aláírt APK-t.
6. **Support-postafiók** élesítése és a privacy policy placeholder cseréje (P1-2),
   valós **képernyőképek** + Play Console feltöltés belső tesztsávra (P1-4),
   **incident owner** megnevezése (P1-5).
7. **Staging migrációs próba** lefuttatása és jegyzőkönyvezése (P1-3).
8. **Valódi gitáros eszköz-teszt** az aláírt (vagy sideloadolt) buildből, a
   `docs/manual-testing/learner-loop-device-run.md` jegyzőkönyve szerint — ez a **P0-2**
   és egyben a program végső acceptance predikátuma.
9. **Belső tesztsáv élesítése** a Play Console-on; a `docs/release/ga-record.md`
   `ga_status` `not-yet` → `in-progress`, a `staged-rollout-log.md` első szakasza
   megnyitva. Ezzel nyílik meg az első emberi kapu
   (`docs/sdd/program-completion-report.md:138`).
10. **Scope-döntés a `hold` sorokra** (P2-1…P2-4): mi kell az 1.0-hoz és mi vár — az
    Epic 10 32 köre és az `E17` 13 köre **nem** előfeltétele az első belső kiadásnak,
    de amíg `hold`-on állnak, a közösségi képernyők üresek maradnak, és ezt a
    kiadási jegyzetben ki kell mondani.

> **Fontos:** az 1–4. lépés gépi munka, elindítható azonnal. Az 5–9. lépés **emberi**;
> a program ma ezeken áll, nem kódhiányon.

---

## 7. Mérés forrásai

**Fájlok:** `.github/workflows/build-apk.yml`, `full-gate.yml`, `release-apk.yml`,
`record-goldens.yml`, `router-ci.yml`, `lab-apk.yml`, `backend-ci.yml`,
`chord-train.yml`, `ml-train.yml`, `dsp-probe.yml`, `tutor-eval.yml` ·
`android/app/build.gradle.kts` · `pubspec.yaml` · `docs/execution/pipeline-queue.tsv` ·
`docs/sdd/program-completion-report.md` · `docs/governance/04-release-checklist.md` ·
`docs/release/blockers.md`, `known-issues.md`, `ga-record.md`, `staged-rollout-log.md`,
`release-history-audit.md`, `program-baseline.md`, `technical-debt.md`,
`workflows/release-candidate.proposal.yml` · `docs/legal/privacy-policy-draft.md` ·
`docs/store/listing.md` · `docs/security/threat-model.md` ·
`docs/operations/disaster-recovery-drill.md` · `docs/testing/device-matrix.yaml` ·
`docs/roadmap/next-six-months.md` · `docs/adr/0086`, `0445`, `0448`, `0488`.

**Workflow-futások:** 33961449605, 33998450680, 34373102220, 34955802156, 34955804305,
34981957665, 34982557486, 30514352164, 30521935406.

**PR-ek:** #593, #594, #600 (`E17-R01`, `done`), #601.

**Ágak:** `main` @ `bedfd1e` · `claude/sdd-plans-quality-clarity-5ydqyy` @ `f7bcb90` ·
`claude/ui-design-viral-elements-u9z9ht` @ `a8a287b`.

**Helyben újramért ebben a körben:** `grep -c '\[ \]'
docs/governance/04-release-checklist.md` → **30**, `grep -c '\[x\]'` → **0** ·
`pipeline-queue.tsv` státusz-oszlop → **332 done / 53 hold / 0 pending** ·
`pubspec.yaml:5` → `version: 1.0.0+1` · `docs/release/ga-record.md:33` →
`ga_status: not-yet` · `python3 -m pytest tools/tests -k "release or freeze or dated or
handoff"` → **17 passed** (a dokumentum-őrök nem sérülnek ettől az új fájltól; a
`docs/` prefixet a `feature-freeze.md` `documentation` osztálya fedi).
