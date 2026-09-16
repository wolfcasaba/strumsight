# Release blockers — StrumSight

**Mérés SHA-ja:** `main @ 92576977` (`chore(pipeline): a Chapter 12 sáv AKTIVÁLÁSA …`, 2026-08-28 01:42:55 +0200).
**Mérte:** E12-R01 implementer (Claude Sonnet 5), 2026-08-28.

Minden sor a [program-baseline.md](program-baseline.md)/[release-history-audit.md](release-history-audit.md)
mérésből vagy a [docs/governance/04-release-checklist.md](../governance/04-release-checklist.md)
pipálatlan tételeiből következik —
**egyik sort sem javítja ez a kör** (a §3 scope-tilalma szerint, brief §9
„Scope-csúszás javítás felé"). Az `Owner` mező a Chapter 12 tervezett körére
mutat (`docs/execution/pipeline-queue.tsv`), amelynek `allowed_paths`-a majd
lefedi a javítást — egyik owner-kör sem futott le a mérés pillanatáig
(mind `pending`).

> **Az `Owner (kör) … (pending)` annotációk ELAVULTAK** (mérve 2026-09-16): a
> `docs/execution/pipeline-queue.tsv` szerint mind a tíz owner-kör (`E12-R04`,
> `E12-R06`, `E12-R07`, `E12-R08`, `E12-R13`, `E12-R17`, `E12-R18`, `E12-R19`,
> `E12-R24`, `E12-R26`) `done` — a fenti sorok a 2026-08-28-i mérés
> változatlanul hagyott története, a MAI állapot a lenti
> „Újramérés 2026-09-16" szakaszban van.

| ID | Severity | Cím | Owner (kör) | Chapter | Bizonyíték | Zárási feltétel |
|---|---|---|---|---|---|---|
| R-SIGN-01 | P0 | Production signing nem ellenőrizhető ebből a munkapéldányból | [E12-R07](../rounds/e12-r07-production-signing-and-secret-hardening.md) (`pending`) | Ch12 | `android/app/build.gradle.kts:58-70` (fail-closed `GradleException`), `.github/workflows/release-apk.yml:9-36` (`signing-prerequisites` job, 4 kötelező secret), helyi `android/key.properties` hiánya (`ls -la android/key.properties` → `No such file or directory`); a 4 GH secret (`ANDROID_KEYSTORE_BASE64` stb.) tényleges megléte `gh` nélkül nem igazolható | `release-apk.yml` egy valódi dispatch-futása sikeresen előállít egy aláírt production APK-t, és ennek run-linkje a `program-baseline.md`-be kerül |
| R-VER-01 | P1 | Nincs monoton verzió/build-szám és artifact-provenance a kiadásokhoz | [E12-R06](../rounds/e12-r06-versioning-provenance-and-sbom.md) (`pending`) | Ch12 | `pubspec.yaml:5` (`1.0.0+1`, változatlan 26 Release és 27 tag mellett — `release-history-audit.md` §4); `docs/governance/04-release-checklist.md:6` (`[ ] verzió és build number monoton.`) pipálatlan | a build-szám minden kiadáskor automatikusan emelkedik, és a checklist 6. sora pipálva |
| R-PRIV-01 | P1 | Nincs egységes, store-képes privacy policy / data inventory | [E12-R17](../rounds/e12-r17-privacy-data-inventory-and-consent-enforcement.md) (`pending`) | Ch12 | `ls docs/privacy/` → egyetlen fájl, `practice-planning-data.md` (csak az AI Practice Generator feature-t fedi, `docs/privacy/practice-planning-data.md:1-7`); `docs/governance/04-release-checklist.md:24` (`[ ] privacy policy és data inventory friss.`) pipálatlan | egy teljes, minden feature adatgyűjtését lefedő privacy policy létezik, és a checklist 24. sora pipálva |
| R-SEC-01 | P1 | Nincs release-szintű threat model / biztonsági szkennelés | [E12-R18](../rounds/e12-r18-threat-model-and-release-security-scan.md) (`pending`) | Ch12 | `ls docs/security/` → `community-access-matrix.md`, `community-threat-model.md` (mindkettő a community feature-re szűkített, nem release-szintű); `docs/governance/04-release-checklist.md:29-33` (Security szakasz mind az 5 sora) pipálatlan | egy release-szintű threat model dokumentum létezik, és a checklist Security szakasza (29-33. sor) pipálva |
| R-STAGE-01 | P1 | Nincs staging backend / migrációs próbafuttatás dokumentálva | [E12-R08](../rounds/e12-r08-staging-backend-migrations-and-recovery.md) (`pending`) | Ch12 | `docs/governance/04-release-checklist.md:15` (`[ ] migration rehearsal zöld.`) pipálatlan; a 21 backend migráció (`program-baseline.md` §5) létezik, de staging-környezeti próbafuttatásuk erről a munkapéldányról nem bizonyítható | a 21 migráció staging-en végigfuttatva dokumentált, és a checklist 15. sora pipálva |
| R-STORE-01 | P1 | Nincs store-listing / legal csomag | [E12-R24](../rounds/e12-r24-store-listing-and-legal-package.md) (`pending`) | Ch12 | nincs Fastlane- vagy store-metaadat fájl (`find . -iname "*fastlane*" -not -path "./.git/*"` üres), nincs `.aab` (`find . -iname "*.aab" -not -path "./.git/*"` üres); `docs/governance/04-release-checklist.md:37-41` (Store szakasz mind az 5 sora) pipálatlan — részletezve `release-history-audit.md` §5 | store-listing artefaktumok (ikon, screenshot, leírás, content rating, support/privacy URL) léteznek, és a checklist Store szakasza (37-41. sor) pipálva |
| R-DEVICE-01 | P2 | Nincs device matrix / device lab | [E12-R13](../rounds/e12-r13-device-matrix-and-device-lab.md) (`pending`) | Ch12 | `docs/governance/04-release-checklist.md:16` (`[ ] device matrix kötelező sora zöld.`) pipálatlan | a device matrix kötelező sora zöld, és a checklist 16. sora pipálva |
| R-CHANNEL-01 | P2 | Nincs elkülönített release-csatorna (dev/staging/prod) | [E12-R04](../rounds/e12-r04-environment-and-channel-isolation.md) (`pending`) | Ch12 | `docs/governance/04-release-checklist.md:7` (`[ ] release channel azonosítható.`) pipálatlan; a mért 10 workflow (`program-baseline.md` §2) egyike sem különíti el explicit release-csatornaként a buildeket (mind `workflow_dispatch`, csatorna-címke nélkül) | a release channel azonosítható minden artifactnál, és a checklist 7. sora pipálva |
| R-ROLLBACK-01 | P2 | Nincs rollback-artefaktum / disaster-recovery próba | [E12-R26](../rounds/e12-r26-rollback-and-disaster-recovery-drill.md) (`pending`) | Ch12 | `docs/governance/04-release-checklist.md:46` (`[ ] rollback artifact.`) pipálatlan | a rollback artefaktum létezik és tesztelt, és a checklist 46. sora pipálva |
| R-MONITOR-01 | P2 | Nincs rollout-monitoring dashboard / incident owner | [E12-R19](../rounds/e12-r19-privacy-safe-observability-and-slo.md) (`pending`, az infrastruktúra-előfeltétel; a fogyasztó kör [E12-R27](../rounds/e12-r27-closed-beta-launch-and-monitoring.md), szintén `pending`) | Ch12 | `docs/governance/04-release-checklist.md:47-48` (`[ ] monitoring dashboard.`, `[ ] incident owner.`) pipálatlan | monitoring dashboard és incident owner dokumentálva, és a checklist 47-48. sora pipálva |

## Újramérés 2026-09-16

**Mérés alapja:** `main` @ `bedfd1e` + a
[`production-readiness-gap-2026-09-16.md`](production-readiness-gap-2026-09-16.md)
mért pillanatképe; a checklist-oldali átvezetés ugyanebben a körben történt
(`docs/governance/04-release-checklist.md`, 6/30 sor pipálva).

**A fenti, 2026-08-28-i táblázat egyetlen sorát sem írja át ez a szakasz** — se
ID-t, se súlyosságot, se zárási feltételt. Ennek gépi oka is van: a
`tool/release/verify_freeze.py`, a `tool/release/verify_ga_record.py` és a
`test/tooling/ga_scope_test.dart` a `| R-… | P0-P4 |` alakú sorokat parszolja
a nyitott P0/P1 halmaz megállapításához, ezért az itteni ID-k szándékosan
backtick-ben állnak — ez a szakasz állapotjelentés, nem regiszter. A
`LEZÁRHATÓ` státusz NEM lezárás: a tényleges lezárás (sor törlése vagy
átsorolása) emberi döntés, külön körben.

| ID | mai állapot | bizonyíték | mi hiányzik még |
|---|---|---|---|
| `R-SIGN-01` (P0) | **NYITVA** | `release-apk.yml` élete során kétszer futott (**30514352164**, **30521935406**, 2026-07-30), mindkettő a `Production signing prerequisites` jobon bukott (`release-apk.yml:10`); aláírt produkciós APK soha nem állt elő | a 4 GitHub-secret (`ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`) beállítása **emberi lépés**, majd egy zöld `release-apk.yml` dispatch, és a run-link a `program-baseline.md`-be |
| `R-VER-01` (P1) | **NYITVA** | `pubspec.yaml:5` ma is `1.0.0+1`, miközben `release-history-audit.md` §4 szerint 26 Release és 27 tag van; a checklist „verzió és build number monoton" sora pipálatlan maradt | gépi build-szám-emelés (a `verify_artifacts.py --previous` csak ELLENŐRIZ, nem emel) — egy kör munkája |
| `R-PRIV-01` (P1) | **NYITVA** | `docs/legal/privacy-policy-draft.md:93` — a `privacy-support@strumsight.app` a saját NOTE-ja szerint kitalált placeholder | valós, működő support-postafiók és a tervezet store-véglegesítése — **emberi lépés** |
| `R-SEC-01` (P1) | **CSAK CHECKLIST (részleges)** | a release-szintű threat model MA létezik (`docs/security/threat-model.md`) — a 2026-08-28-i „csak community-szűkített dokumentum" állítás elavult; a Security szakaszból ma **1/5** sor pipálható bizonyítékkal („secret scan tiszta", `full-gate.yml` **34373102220**) | a maradék 4 Security sorhoz (`dependency/container scan`, `authorization és rate limit`, `insecure default`, `signing key hozzáférés`) ez a kör NEM mért hivatkozható bizonyítékot; a credential-hozzáférés auditja **emberi** |
| `R-STAGE-01` (P1) | **NYITVA** | `docs/adr/0449-*` tervezési ADR, nem jegyzőkönyv; a 21 migráció létezik, staging-futásuk nincs dokumentálva | egy valódi staging-környezet + próbafuttatási jegyzőkönyv — **ember + kör** |
| `R-STORE-01` (P1) | **NYITVA** | a store-csomag dokumentumai léteznek (`docs/store/listing.md`, `permissions-rationale.md`, `data-safety.yaml`), de `listing.md:75` a screenshot-tervet kimondottan placeholder-ként jelöli („real captures pending device-lab pass") | valós képernyőképek (eszköz-futás után), ikon, content rating és a Play Console-feltöltés — **emberi lépés** |
| `R-DEVICE-01` (P2) | **NYITVA** | `docs/testing/device-matrix.yaml` + `docs/testing/device-lab.md` léteznek, de a regiszterben MINDEN eszköz `camera_result: pending` és `audio_result: pending` — nulla mért futás; a `release_blocking: true` sorok (Pixel 6a, Pixel 7) sem futottak | egy valódi eszköz-futás a CI-ból származó APK-val (`device-lab.md` §2) és egy `tool/device_report.py --results` eredményfájl — **ember** |
| `R-CHANNEL-01` (P2) | **LEZÁRHATÓ** | [ADR 0445](../adr/0445-environment-value-set-and-staging-isolation.md) + a csatorna minden buildbe belefordítva: `build-apk.yml:64` (`STRUMSIGHT_ENV=development`), `release-apk.yml:122` (`STRUMSIGHT_ENV=production`); a checklist „release channel azonosítható" sora ezzel MA pipálva | semmi érdemi — a sor formális lezárása (törlés/átsorolás) emberi döntés |
| `R-ROLLBACK-01` (P2) | **LEZÁRHATÓ** | [`docs/operations/disaster-recovery-drill.md`](../operations/disaster-recovery-drill.md) — 2026-09-02-én ténylegesen lefuttatott gyakorlat, `tool/release/verify_rollback.py`, `test/tooling/rollback_policy_test.dart` A5/A6; a checklist „rollback artifact" sora ezzel MA pipálva | a store/APK szintű app-release visszagörgetés (drill §6) — ez az `R-SIGN-01`-en múlik, nem ezen a soron |
| `R-MONITOR-01` (P2) | **NYITVA** | `docs/operations/slo.yaml` séma és `docs/operations/release-dashboard.md` — az utóbbi saját fejléce szerint „schema only — this round does not build the dashboard UI or wire a data source into it"; működő dashboard és névvel megnevezett incident owner nincs | egy valós dashboard (vagy manuális readiness-review jegyzőkönyv) + egy megnevezett incident owner — **emberi lépés** |

**Összegzés:** 10-ből **2 LEZÁRHATÓ** (`R-CHANNEL-01`, `R-ROLLBACK-01`), **1
részlegesen checklist-adósság** (`R-SEC-01`), **7 érdemben NYITVA** — ezek közül
6-hoz emberi művelet kell (secret/keystore, support-postafiók, staging,
store-feltöltés, eszköz-futás, incident owner), 1 tiszta kör-munka
(`R-VER-01` build-szám-emelés). A P0 (`R-SIGN-01`) nyitva marad, tehát a
`docs/release/ga-record.md` `ga_status: not-yet` logikája (A7) változatlanul áll.

## Miért pont ezek — módszertan

A tíz sor mindegyike a `docs/governance/04-release-checklist.md` egy vagy
több, a mérés pillanatában pipálatlan sorára vezethető vissza (a fájl mind a
30 sora pipálatlan — `program-baseline.md` §8), **és** van hozzá a
Chapter 12 tervben egy konkrét, `pending` státuszú owner-kör
(`docs/execution/pipeline-queue.tsv`). Azok a checklist-sorok, amelyekhez
NEM tartozik ilyen kettős bizonyíték (pl. „format/analyze/test/property gate
zöld" — ez már MOST is zöld, csak a checklist-doksi nincs frissítve),
szándékosan KIMARADTAK — a blocker-lista valódi hiányt jelöl, nem a
checklist-dokumentum karbantartási elmaradását.

## Severity-skála

- **P0** — a mérés pillanatában nem igazolható, hogy egyáltalán elő lehet
  állítani egy aláírt production artifactot.
- **P1** — a store-beadáshoz vagy a felelős kiadáshoz (privacy, security,
  staging, verziózás) szükséges, jelenleg hiányzó előfeltétel.
- **P2** — a biztonságos, fokozatos rollout-hoz szükséges, jelenleg hiányzó
  előfeltétel (device-lefedettség, csatorna-izoláció, rollback, monitoring).
- **P3** — ebben a mérésben nem került elő P3-as tétel; a séma fenntartja a
  szintet a későbbi Chapter 12 körök számára.
