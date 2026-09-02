# Known issues — StrumSight Release Candidate előtt

**Mérés SHA-ja:** `main @ 4ac78365` (`docs(handoff): E12-R29 KÉSZ — Open Beta
és canary cohort; queue done, RTM, L577`, 2026-09-02) — a jelen kör
(`E12-R30`) `freeze_base_sha`-ja, [`feature-freeze.md`](feature-freeze.md) §2.
**Mérte:** E12-R30 implementer (Claude Sonnet 5), 2026-09-02.

Ez a lista **őszinte** (§5.2): minden MÉRT, nyitott hiba felkerül, még ha
kellemetlen is, és „nincs megkerülő út" is kimondva ott, ahol tényleg nincs.
Egyik sort sem fokoztuk le súlyosságban azért, hogy elférjen a
`blockers.md` zárt P0/P1 halmazában (§0.0 P2/4. pont STOP-protokollja) — ahol
egy tétel a `blockers.md`-ben NEM szerepel, ott a súlyossága ITT legfeljebb
`P2`.

A három szakasz (§1–§3) alábbi táblázatai EGY közös, gépileg parszolt
blokkot alkotnak (`<!-- known-issues:begin/end -->`) — a `tool/release/
verify_freeze.py` a blokkon belüli minden `|`-sort (fejléc/elválasztó
kivételével) kötelező adatsornak tekinti, a köztük álló prózát/alcímeket
figyelmen kívül hagyja (ugyanaz a két-lépcsős szűrés, mint a
`verify_ga_scope.py` tábla-parszerében).

<!-- known-issues:begin -->

## 1. A `blockers.md` TÍZ sorának MAI, soronkénti mérése

**Elavultság kimondva:** a `blockers.md` fejléce `main @ 92576977`
(2026-08-28), és mind a 10 sor `Owner (kör) … (pending)` annotációt hordoz. A
`docs/execution/pipeline-queue.tsv` MAI állapota szerint viszont mind a tíz
owner-kör (`E12-R04`, `E12-R06`, `E12-R07`, `E12-R08`, `E12-R13`, `E12-R17`,
`E12-R18`, `E12-R19`, `E12-R24`, `E12-R26`) **`done`**. Az `Owner … (pending)`
annotáció tehát elavult szöveg — ezt a fájlt ez a kör **nem** írja át (§0.0
P2, tilos zóna). Amit ez a szakasz mér: az owner-kör lefutása **nem**
jelenti azt, hogy a `blockers.md`-ben leírt **zárási feltétel** is
teljesült — azt soronként, ma kell megmérni, és — kimondott mérés — a
`docs/governance/04-release-checklist.md` mind a **30** sora ma is
pipálatlan (`grep -c '\[ \]' docs/governance/04-release-checklist.md` → 30,
`grep -c '\[x\]' …` → 0), és minden egyes zárási feltétel része a saját
checklist-sorának kipipálása is — emiatt **egyik blocker sem tekinthető
lezártnak**, függetlenül attól, hogy az owner-kör mögötte milyen érdemi
munkát szállított.

| id | severity | title | impact | workaround |
|---|---|---|---|---|
| `R-SIGN-01` | `P0` | Production signing nem igazolható erről a munkapéldányról | Aláírt production APK nem állítható elő erről a boxról; a 4 kötelező GH secret (`ANDROID_KEYSTORE_BASE64` stb.) tényleges megléte `gh` nélkül nem ellenőrizhető innen — a `gh` hitelesítés ezen a boxon a proxy 403-a miatt blokkolt (CLAUDE.md „REMOTE Claude Code konténerben"). `android/key.properties` helyben nem létezik (várt, nem hiba). | Nincs megkerülő út erről a munkapéldányról — a `release-apk.yml` egy valódi dispatch-futása szükséges, ami sikeresen aláírt APK-t termel, és a run-link bekerül a `program-baseline.md`-be (`blockers.md` zárási feltétele). |
| `R-VER-01` | `P1` | Nincs automatikus verzió/build-szám emelés | `pubspec.yaml:5` ma is `1.0.0+1`. A `tool/release/verify_artifacts.py --previous` a monotonicitást csak ELLENŐRZI, ha kap egy korábbi manifestet (`docs/release/supply-chain.md` „Build number monotonicity" szakasz) — automatikus emelést egyik eszköz sem végez. `docs/governance/04-release-checklist.md:6` pipálatlan. | Emberi fegyelem: minden release előtt kézzel emelni a build-számot, és a `verify_artifacts.py --previous`-t futtatni; nincs gépi kényszerítő az emelésre magára. |
| `R-PRIV-01` | `P1` | Privacy policy MA is tervezet (draft), nem store-végleges | `docs/legal/privacy-policy-draft.md` létezik (Kör 24), de a `privacy-support@strumsight.app` cím a Kör 24 saját NOTE-ja szerint kitalált PLACEHOLDER. `docs/governance/04-release-checklist.md:24` pipálatlan. | Nincs megkerülő út — a valódi támogatási e-mail cím megerősítése és a checklist-sor kipipálása store-beadás előtti emberi lépés. |
| `R-SEC-01` | `P1` | Release-szintű threat model MA létezik, de a checklist pipálatlan | `docs/security/threat-model.md` (Kör 18) MA release-szintű dokumentum — a `blockers.md` 2026-08-28-i állítása, hogy csak community-szűkített dokumentum van, MA elavult. `docs/governance/04-release-checklist.md:29-33` mind az öt sora mégis pipálatlan. | A checklist 5 sorának emberi átvezetése a meglévő `docs/security/threat-model.md` + `exceptions.yaml` alapján — a dokumentum megvan, a checklist karbantartása maradt el. |
| `R-STAGE-01` | `P1` | Staging migrációs próbafuttatás nincs dokumentálva | A 21 backend migráció létezik, de `docs/adr/0449-staging-readiness-traffic-gate-and-recovery.md` tervezési ADR, nem egy tényleges staging-rehearsal jegyzőkönyv — `grep -rn "rehears" docs/adr/0449-*.md` üres. `docs/governance/04-release-checklist.md:15` pipálatlan. | Nincs megkerülő út — a staging-környezeti próbafuttatás és annak dokumentálása külön kör vagy emberi lépés. |
| `R-STORE-01` | `P1` | Store-listing csomag megvan, checklist Store szakasza pipálatlan | `docs/store/listing.md`, `permissions-rationale.md`, `data-safety.yaml` (Kör 24) léteznek, gépi mércével (`test/tooling/store_package_test.dart`). `docs/governance/04-release-checklist.md:37-41` mind az öt sora pipálatlan, és a tényleges Play Console feltöltés emberi lépés marad. | A checklist 5 sorának emberi átvezetése a meglévő csomag alapján, plusz a tényleges store-feltöltés. |
| `R-DEVICE-01` | `P2` | Device matrix megvan, checklist sora pipálatlan | `docs/testing/device-matrix.yaml` + `docs/testing/device-lab.md` (Kör 13) léteznek. `docs/governance/04-release-checklist.md:16` pipálatlan. | A checklist sor emberi átvezetése a meglévő device-matrix alapján. |
| `R-CHANNEL-01` | `P2` | Environment/channel izoláció megvan, checklist sora pipálatlan | `docs/rounds/e12-r04-environment-and-channel-isolation.md` (Kör 4) és `docs/adr/0445-environment-value-set-and-staging-isolation.md` léteznek. `docs/governance/04-release-checklist.md:7` pipálatlan. | A checklist sor emberi átvezetése. |
| `R-ROLLBACK-01` | `P2` | A rollback-gyakorlat TÉNYLEGESEN lefutott, checklist sora mégis pipálatlan | `docs/operations/disaster-recovery-drill.md:1-6` szerint a gyakorlat 2026-09-02-én valóban lefutott ezen a boxon, gépi mércével (`test/tooling/rollback_policy_test.dart` A5/A6). `docs/governance/04-release-checklist.md:46` mégis pipálatlan — tiszta checklist-karbantartási elmaradás, nem hiányzó munka. | A checklist 46. sorának emberi kipipálása — az alátámasztó munka megvan. |
| `R-MONITOR-01` | `P2` | Monitoring SLO-séma megvan, checklist sorai pipálatlanok, incident owner névvel nincs dokumentálva | `docs/operations/slo.yaml` + `docs/adr/0484-privacy-safe-telemetry-contract-and-release-slo-schema.md` (Kör 19) léteznek. `docs/governance/04-release-checklist.md:47-48` pipálatlan. | A checklist 2 sorának emberi átvezetése, plusz egy konkrét incident owner kijelölése. |

## 2. A Kör 25 RC-workflow-ja MÉG SOHA NEM FUTOTT

| id | severity | title | impact | workaround |
|---|---|---|---|---|
| `K-RC-01` | `P2` | Az RC-assembly workflow (`release-candidate.yml`) egyszer sem futott zölden — ténylegesen nem is létezik telepítve | `ls .github/workflows/` → 10 workflow (`backend-ci`, `build-apk`, `chord-train`, `dsp-probe`, `full-gate`, `lab-apk`, `ml-train`, `release-apk`, `router-ci`, `tutor-eval`); `release-candidate.yml` NINCS köztük. A Kör 25 szándékosan JAVASLATKÉNT szállította (`docs/release/workflows/release-candidate.proposal.yml`) — a telepítés [ADR 0488](../adr/0488-release-candidate-assembly-and-approval-gate.md) D1/D8 szerint emberi lépés egy jóváhagyói environment mögött. Ez a tény közvetlenül a `R-SIGN-01` P0 zárási feltételéhez kötődik: amíg az RC-kapu nem fut, egy aláírt production APK sikeres, dokumentált előállítása sincs bizonyítva. | A javaslat-fájl (`docs/release/workflows/release-candidate.proposal.yml`) telepítése és egy jóváhagyói environment mögötti dispatch — emberi lépés, önálló kör hatókörén kívül. |

## 3. Gazdátlan, korábbi körökben MÉRT nyitott leletek (a `HANDOFF.md` sorolja fel, mindegyik itt újra ellenőrizve a fán)

| id | severity | title | impact | workaround |
|---|---|---|---|---|
| `K-E12R23-01` | `P2` | Sérült legacy dokumentum után a frissítő ÜRES dokumentumot lát (adat a lemezen megmarad) | `lib/core/storage/json_document_store.dart:86` (`readBody()`) `null`-t ad egy sérült legacy dokumentumra, tehát a felhasználó frissítés után üres dalkönyvtárat lát, míg a nyers bájtok a lemezen maradnak (a következő `write()` karanténba menti). Pinnelve `test/e2e/upgrade_migration_test.dart` A3b cellájával „ISMERT KORLÁT (ADR 0487)" jelöléssel, dokumentálva `docs/release/client-migration.md` §6. A javítás `lib/**`-ot érintene — ennek a körnek tilos zónája. | Nincs futásidejű workaround a felhasználó felé; a védelem a pinnelt teszt, ami szól, ha egy jövőbeli kör megjavítja VAGY tovább rontja a viselkedést. Adatvesztés nincs (a lemezen megmaradó bájtok a következő íráskor helyreállnak), csak átmeneti üres nézet. |
| `K-E12R21-01` | `P3` | 10 `practiceCatalog*Description` ARB-kulcs hiányzik mindkét locale-ból; 17 `Lesson.name` beégetett angol | `grep -c "practiceCatalog.*Description" lib/l10n/app_en.arb lib/l10n/app_hu.arb` → 0/0 (mérve ezen a körön) — a beépített gyakorlat-katalógus leírás-felülete ma egyetlen nyelven sem oldható fel. Nyilvántartva `docs/content/catalog-inventory.yaml` `known_exceptions:` blokkjában (`owner: strumsight-content`, `expiry: 2026-12-31`, mérve `docs/content/catalog-inventory.yaml:312` és `:317`). | Nincs futásidejű workaround; a tartalom-forrás (`lib/**`/`assets/**`) módosítása egy jövőbeli, content-hatókörű kör feladata, a kivétel-lejárat előtt. |
| `K-E12R20-01` | `P2` | Három accessibility-túlcsordulás `textScale 2.0`-n, dátumozott review-val | `practice_setup_screen.dart:418` 43px túlcsordulás mindkét locale-on; `practice_feedback.dart:89` 65px túlcsordulás csak `hu`-n; `ss_switch_row.dart` DS-komponens két szemantikai csomópontot ad egy sor helyett szimulált akadálymentességi bejáráson. Mindhárom nyilvántartva `docs/accessibility/known-exceptions.yaml`-ben, `review_by: "2026-12-01"`. | Nincs futásidejű workaround; a `lib/**` javítás a kivétel-lejárat előtti, önálló kör feladata. A P2 súlyosság miatt a Kör 20 saját mérése szerint a STOP-protokoll akkor nem lépett életbe. |
| `K-E12R24-01` | `P3` | `privacy-support@strumsight.app` kitalált PLACEHOLDER cím; a `data-safety.yaml` `play_category` mezői nincsenek a Play hivatalos taxonómiájához kötve | Mindkettő a Kör 24 saját, nem merge-blokkoló NOTE-ja — a valódi cím megerősítése és a Play Console taxonómia-megfeleltetés store-feltöltés előtti emberi lépés. | Nincs futásidejű workaround; mindkettő store-feltöltés előtti emberi megerősítést igényel. |
| `K-E12R29-01` | `P2` | A Community router nincs mountolva a fő backend appban | `grep -n community backend/app/main.py` → 0 találat (mérve ezen a körön). Emiatt a nyitott Open Beta canary cohort ma nulla Community-terhelést tud generálni — ez tesztlefedettségi rés, nem éles hiba, mert a végpontok egyáltalán nem érhetők el. | Nincs futásidejű workaround; a router mountolása egy jövőbeli, `backend/**`-et érintő kör feladata. |
| `K-E12R29-02` | `P2` | A `backend/app/routers/settings.py` `PUT /settings` végpontja nem visel saját rate limitert | `grep -n limiter backend/app/routers/settings.py` üres (mérve ezen a körön); a végpont hitelesítést IGÉNYEL (`CurrentUser` dependency, `backend/app/routers/settings.py:9-30`), tehát a rés kihasználásához érvényes fiók kell — ez a `docs/beta/open-beta-launch.md` §4 saját szavaival „rés, nem guard". | Nincs futásidejű workaround; a rate limiter hozzáadása (a `login`/`register` limiterek mintájára, `backend/app/ratelimit.py`) egy jövőbeli, `backend/**`-et érintő kör feladata. |

<!-- known-issues:end -->

## 4. Miért pont ezek — módszertan

A `blockers.md` tíz sora a mai fán soronként újramérve (§1); a Kör 25
RC-workflow ténye külön tétel, mert a `.github/**` ennek a körnek tilos
zónája, tehát az A5-bizonyíték nem ez, hanem az orchesztrátor
`build-apk.yml`/`full-gate.yml` dispatchja (§0.0 P3, [`feature-freeze.md`](feature-freeze.md));
és a `HANDOFF.md`-ben már dokumentált, gazdátlan `lib/**`/`backend/**`
leletek (Kör 21/23/24/29), amelyek egyike sem tartozik a `blockers.md`
zárt hatókörébe, de nyitottak és MÉRTEK. A „nem reprodukálható" kategóriába
söprés egyik tételnél sem történt meg (§5.2 tiltása) — minden sor a fenti
konkrét `grep`/fájl:sor méréssel van alátámasztva.

**Súlyosság-fegyelem:** a `blockers.md`-ben NEM szereplő tételek egyike sem
kapott `P0`/`P1` besorolást — ha a mérés valódi `P0`/`P1` hibát talált volna a
`blockers.md`-n kívül, a helyes válasz a §0.0 STOP-protokollja lett volna
(`tools/codex-signal.sh stopped`), nem a súlyosság lefokozása. Egyik tétel
sem indokolta ezt: a `K-E12R23-01` adatvesztés nélküli, átmeneti üres nézet;
a `K-E12R29-02` hitelesítést igénylő rés; a többi tesztlefedettségi vagy
dokumentációs elmaradás.
