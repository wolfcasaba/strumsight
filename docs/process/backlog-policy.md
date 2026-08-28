# Backlog policy — label- és severity-rendszer

- **Kör:** `E12-R03` — GitHub delivery workflow, branch protection és review policy
- **Normatív döntés:** [ADR 0444](../adr/0444-delivery-workflow-and-repository-policy.md)
- **Hatály:** `.github/ISSUE_TEMPLATE/*.yml` és a jövőbeli GitHub issue-k. A
  severity-skálát **nem** ismétli meg szó szerint — a
  [`docs/release/blockers.md`](../release/blockers.md) „Severity-skála"
  szakasza a forrás, ide csak a leképezés kerül.

## 1. Type-label — az issue-sablon adja

| Label | Sablon | Kötelező mezők (lásd §3) |
|---|---|---|
| `feature` | `.github/ISSUE_TEMPLATE/feature.yml` | chapter, round, acceptance, test_plan, rollback, privacy |
| `bug` | `.github/ISSUE_TEMPLATE/bug.yml` | chapter, round, acceptance, test_plan, rollback, privacy |
| `security` | `.github/ISSUE_TEMPLATE/security.yml` | chapter, round, acceptance, test_plan, rollback, privacy |
| `migration` | `.github/ISSUE_TEMPLATE/migration.yml` | chapter, round, acceptance, test_plan, rollback, privacy |
| `release` | `.github/ISSUE_TEMPLATE/release.yml` | chapter, round, acceptance, test_plan, rollback, privacy |

Minden sablon `needs-triage` labellel nyílik — ez az `[E01-R01]`-stílusú
issue-elnevezés ([`docs/governance/01-github-milestones-and-issues.md`](../governance/01-github-milestones-and-issues.md))
kiegészítője, nem helyettesítője.

## 2. Area-label — a CODEOWNERS öt területével egyezik

A `.github/CODEOWNERS` (ADR 0444 D4) az alábbi öt terület jelölő tulajdonosát
rögzíti; az issue-kon ugyanez az öt area-label használható triage-hoz:

| Area-label | Lefedett útvonalak |
|---|---|
| `area/audio` | `lib/core/audio/`, `lib/features/audio_analysis/`, `lib/features/live/`, `lib/features/tuner/` |
| `area/backend` | `backend/` |
| `area/security` | `lib/features/auth/`, `lib/core/storage/`, `lib/core/network/`, `docs/security/` |
| `area/model` | `lib/core/ml/`, `assets/ml/` |
| `area/release` | `.github/workflows/`, `android/`, `docs/release/` |

Az area-label **nem kapuz** — ugyanaz a jelölő, nem-blokkoló szerep, mint a
CODEOWNERS-é (ADR 0444 D1). Egy area-label hiánya nem tartja vissza a triage-t
vagy a merge-et.

## 3. Kötelező mezők minden issue-sablonon

A `docs/governance/01-github-milestones-and-issues.md` „Issue body" szakaszával
egyező hat mező, minden sablonon `required: true`:

| Mező id | Jelentés |
|---|---|
| `chapter` | SDD fejezet/terület (pl. „Chapter 07 — Practice & Gamification") |
| `round` | Kör-azonosító, ha ismert (pl. `E07-R12`), vagy „nincs még kiosztva" |
| `acceptance` | Elfogadási kritériumok |
| `test_plan` | Tesztparancs(ok), amivel a lezárás bizonyítható |
| `rollback` | Hogyan vonható vissza |
| `privacy` | Privacy/security hatás — vagy „nincs" |

A hiányzó kötelező mezőt a `test/tooling/repository_policy_test.dart` A1
cellája és a `tool/audit_repository_policy.py` egyaránt méri.

## 4. Severity leképezés (`docs/release/blockers.md`)

A `security.yml` és a `bug.yml` sablon egy `severity` dropdown mezőt ajánl fel,
a [`docs/release/blockers.md`](../release/blockers.md) „Severity-skála"
szakaszának **négy szintjével** (P0–P3) — a szöveg maga ott marad, itt csak a
leképezés:

- **P0** → nem igazolható aláírt production artifact — release-blokkoló.
- **P1** → store-beadási/felelős kiadási előfeltétel hiányzik.
- **P2** → biztonságos, fokozatos rollout előfeltétele hiányzik.
- **P3** → fenntartott szint, jelenleg nincs ide sorolt tétel.

A severity **nem kapuz** a CI-ban — triage-jelölés, amit a
`docs/process/branch-protection.md`-ben leírt required status check nem néz.

## 5. Release asset változás — magyarázat kötelező (ADR 0444, SDD Ch12 Kör 3)

Egy release-asset (`android/`, aláíró/verziós konfiguráció, store-metaadat,
`docs/release/**` alatti kiadási bizonyíték) módosítása **magyarázat nélkül
nem mehet be**: a PR-sablon (`.github/pull_request_template.md`) kötelezően
kitöltendő release-asset sort tartalmaz erre a célra. Ha a PR nem érint
release assetet, a sor kitöltendő értéke „nincs".

Ez a szabály **dokumentum-szintű**, nem CI-kapu: a `full-gate` / `build-apk`
required check (ADR 0052) változatlan marad, a release-asset magyarázatot a
kör-review nézi át PR-onként, ugyanúgy, ahogy a HANDOFF/traceability
checklistet (`docs/execution/05-branch-and-pr-rules.md` „Kötelező PR
tartalom").

## 6. Ami NEM ennek a dokumentumnak a dolga

- A branch/commit/PR alapszabályok — azok
  [`docs/execution/05-branch-and-pr-rules.md`](../execution/05-branch-and-pr-rules.md)-ben
  élnek, ez a fájl csak a label/severity réteget adja hozzá.
- A branch-protection required-check listája — azt
  [`docs/process/branch-protection.md`](branch-protection.md) írja le.
- Élő GitHub label-szinkron (`gh label create` stb.) — operátori lépés, nem
  ennek a körnek a scope-ja (§3, brief tilos zóna: nincs `gh` hívás az
  implementer részéről).
