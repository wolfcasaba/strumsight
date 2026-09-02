# Rollout decision packet — sablon

**Forrás:** `docs/sdd/12-release-roadmap-final-integration.md` §26.1
(„Rollout decision packet") — a szakasz kilenc kötelező elemet sorol fel
minden lépcső előtt. Ez a sablon azok gépi tükre: `test/tooling/
production_readiness_test.dart`'s A6 cellája méri, hogy mind a kilenc
`## `-szintű szakaszcím jelen van, ebben a sorrendben, és hogy a
`rollback_target` és a `decision_maker` szakasz nem marad üresen a
kitöltött csomagban.

Minden production/belső-cohort lépcső ELŐTT egy másolatot kell kitölteni
ebből a sablonból (pl. `docs/release/rollout-packets/<dátum>-<lépcső>.md`
néven) — maga a sablon sosem hordoz valódi adatot, csak helykitöltőt.

---

## 1. Build és commit

- Verzió/build szám: `<app.version+app.buildNumber, tool/generate_release_manifest.dart`-ból>`
- Commit SHA: `<short SHA>`
- Csatorna: `<internal | canary | staged | ga>`

## 2. Active flags

- Feature-flag profil neve/forrása: `<pl. docs/beta/cohort-profiles.yaml egy cohortja, vagy a production alapértelmezés>`
- Eltérés a korábbi lépcsőtől: `<lista, vagy "nincs">`

## 3. Migration version

- Alembic head a deploy pillanatában: `<revision id>`
- `GET /health/ready` mért állapota a deploy után: `<ready | not_ready + reason>`

## 4. Model version

- `assets/ml/model_manifest.json` verzió/hash: `<mező érték>`

## 5. Known issues

- Hivatkozás: `docs/release/known-issues.md` adott sora/verziója a deploy
  pillanatában: `<mérés SHA-ja>`
- Ehhez a lépcsőhöz releváns, nyitott P0/P1: `<lista, vagy "nincs">`

## 6. Dashboard snapshot

- Mérés időpontja: `<UTC időbélyeg>`
- Hiba-ráta / p95 latencia / crash-free session arány: `<érték + forrás link>`

## 7. Support readiness

- Support-csapat értesítve: `<igen/nem + dátum>`
- Ismert hibák átadva a support-csapatnak: `<igen/nem>`

## 8. Rollback target

- A build/commit, amire vissza lehet állni hiba esetén: `<short SHA vagy build szám>`
- Visszaállítási eljárás hivatkozása: `docs/operations/disaster-recovery-drill.md` vagy a vonatkozó runbook

## 9. Döntéshozó

- Név/szerepkör: `<a lépcsőt jóváhagyó személy>`
- Jóváhagyás dátuma: `<UTC időbélyeg>`
