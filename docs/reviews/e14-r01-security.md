# E14-R01 — Security / Privacy / Prompt-injection review

Brief: `docs/rounds/e14-r01-recovery-kickoff-and-release-guard.md`
Diff: `git diff 17670d4f..3e11e92d` (PR #275, head reviewed `3e11e92d`; base `main @ 17670d4f`)
Reviewer: Claude (security-reviewer subagent) · Dátum: 2026-08-15
Verdikt: **APPROVED** (merge nem blokkolt)

## Összegzés

CRITICAL: 0 · BLOCKER: 0 · MAJOR: 0 · MINOR: 1 (FIXED) · NOTE: 3

`risk = "high"` a brief `ai-router` blokkjában (26. sor) — a besorolást a
reviewer ellenőrizte, valós, tehát a dedikált security-pass kötelező volt. A
tényleges diff 4 fájl (+221/−3): flag-scaffolding + két markdown + teszt.
Nincs `lib/features/**`, hálózat, tárolás, AI-provider, natív kód vagy asset.
A három recognition-recovery flag minden környezetben `false`, sehol nem
olvassa consumer, a `usesNetwork` érintetlen → nulla új adat-/hálózati-/
log-sink. Egy MINOR (baseline-provenance elírás a release-guard docban, azóta
javítva) és három forward-looking NOTE.

**Eljárási near-miss (rögzítendő, nem e-köri lelet):** a reviewernek átadott
lokális fa (`/home/ubuntu/music-theory`) branch-cache-e 3 committal elmaradt a
valódi PR-headtől (a párhuzamosan futó E07-R06 miatt a helyi
remote-tracking ref nem volt friss). A reviewer ezt észlelte, és a GitHubról
frissen fetchelt valódi fejen (`3e11e92d`) végezte el a review-t — a hibás
lokális klónt eldobta. Tanulság a jövőbeli review-diszpécsereknek: mindig
`git clone <github-url>`-lal dolgozz, ne a helyi shared tree cache-elt
remote-trackingjével, ha párhuzamos kör futhat.

## Acceptance criteria (security)

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Nincs forbidden-zone érintés (`.github/**`, `tool/ci`, round-gate, pubspec, `.mcp`, AGENTS/CLAUDE, assets, backend) — H-GATEGUARD | ✅ | `git diff --name-only 17670d4f..3e11e92d` = 4 fájl; forbidden-grep = NONE; a release-guard doc maga is kimondja: „does not modify `.github/**`" |
| 2 | Mindhárom flag `false` MINDEN környezetben, mind az öt FeatureFlags-helyen | ✅ | konstruktor-default, `forEnvironment` literal `false` (NEM `nonProd`), field-decl, `operator ==`, `hashCode`/`additionalBits`, `toString` |
| 3 | Nincs dart-define/`fromEnvironment` override a 3 flagre | ✅ | grep: az egyetlen `STRUMSIGHT_`/`fromEnvironment` találat az `accountEnabled` doc-kommentje |
| 4 | Nincs új hálózati/consent-sink | ✅ | `usesNetwork => accountEnabled \|\| diagnosticsEnabled` — a recognition flagek nem szerepelnek benne |
| 5 | Flagek unwired (nincs consumer) | ✅ | `git grep` a 3 flag-névre `lib/`-ben a config-fájlon kívül = 0 találat |
| 6 | Nincs secret/PII/injection az új sorokban | ✅ | secret-grep + injection-grep = 0; a `check_secrets` gépi kapu is 0 finding |
| 7 | Scope = engedélyezett fájllista | ✅ | `allowed_paths` = pontosan a megváltozott fájlok (scope-audit OK) |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.** `AppEnvironment` pontosan
három értékű (`development`, `lab`, `production`); a teszt mindhármat lefedi.

## Megállapítások

### F1 — MINOR — Baseline-provenance elírás a release-guard docban

- **Fájl:** `docs/eval/recognition-release-guard.md:10-14` (eredeti szöveg)
- **Probléma:** a doc három számot — chord 67.1%, onset F1@50ms 67.4%,
  direction 80.7% — együtt a „82-recording phone-guitar corpus documented in
  `real-audio-dsp-baseline.md`" forráshoz kötötte. A chord és onset F1
  valóban onnan való. A **direction 80.7% NEM**: a hivatkozott baseline-doc
  nem mér irány-metrikát. A 80.7% a live 3-osztályos CRNN eval-foldjának
  mért száma (`docs/handoff-archive.md` round 175: „direction on true
  strums 0.807", n_pos=2013), amit `docs/adr/0271-recognition-recovery-program.md`
  helyesen „direction accuracy (true-strum eval eseményeken)"-ként címkéz
  saját táblázatában.
- **Failure scenario:** ha egy jövőbeli kör (pl. E14-R02, ami a
  `baseline_manifest.json`-t építi) ezt a prózát átveszi és a 80.7%-ot a
  82-korpuszhoz rendelt direction-baseline-ként rögzíti, egy aktiválási
  döntés a jelölt modell irány-pontosságát egy MÁS eval-foldon mért számhoz
  hasonlítaná — a contract saját „Corpus identity" sora ezt tiltja.
- **Sértett szabály:** evidence-integritás; boundary 5 közeli.
- **Státusz:** **FIXED** (`234f84a7`) — a Status szakasz szövege pontosítva:
  a két forrás külön mondatban, mindegyik a saját méréséhez kötve; a
  `docs/rounds/e14-r01-…md` §10.1 rögzíti a javítást. A célzott gate a
  javítás után újra zöld (docs-only diff, Dart-kódot nem érint).

### F2 — NOTE — Az aktiválási contract nem rögzít kvantitatív elfogadási küszöböt

- **Fájl:** `docs/eval/recognition-release-guard.md` (Evaluation report sor)
- **Megfigyelés:** a „regression" definiálatlan, nincs per-csoport numerikus
  non-regression korlát. Forward-looking javaslat egy jövőbeli aktiválási
  körnek/E14-R02-nek — nem e-köri lelet.
- **Státusz:** OPEN (follow-up, nem blokkoló)

### F3 — NOTE — Az `UNKNOWN > CONFIDENTLY WRONG` szabályt egyetlen artefaktum sem méri

- **Fájl:** `docs/eval/recognition-release-guard.md` (Status vs. Activation contract)
- **Megfigyelés:** a governing rule egy runtime abstention/kalibrációs
  tulajdonság, de az 5 kötelező artefaktum egyike sem kér bizonyítékot
  kalibrált tartózkodásra. Forward-looking javaslat: adj hozzá kalibráció/
  abstention elfogadási kritériumot egy jövőbeli körben.
- **Státusz:** OPEN (follow-up, nem blokkoló)

### F4 — NOTE — A teszt explicit 3 környezetet sorol, nem `AppEnvironment.values`-t iterál

- **Fájl:** `test/app/config/feature_flags_test.dart`
- **Megfigyelés:** ma teljes lefedettség (az enum pontosan három érték), de
  egy jövőbeli 4. környezetet a guard némán nem fedne le.
- **Státusz:** OPEN (follow-up, nem blokkoló)

## Pozitív megállapítások

- `forEnvironment` mindhárom flagre literal `false`-t ad (nem `nonProd`) —
  helyes fail-closed default, az ADR 0220 V2-mintáját követi.
- A doc explicit kimondja, hogy nem módosít `.github/**`-ot; ellenőrizve.
- Az implementer valódi „valódi-sértés" próbát futtatott ÉS a review saját
  kézzel megismételte (lásd `docs/reviews/e14-r01-review.md`): a guard
  ténylegesen elkapja a tiltott gyengítést.
- Flagek unwired + `usesNetwork` érintetlen → a kör privacy-semleges, nulla
  új sink.

## Prompt-injection / AI-provider (ADR 0131–0136)

Nincs érintés: a kör nem ad hozzá prompt-építést, tool-hívást, provider-
hívást, tudásbázis-visszakeresést vagy felhasználói üzenetkezelést. A
release-guard doc egy jövőbeli aktiválási contract; szövege nem tartalmaz
agent-nek címzett utasítást (injection-grep = 0).

## Importált tartalom / ellátási lánc

Nincs zip/MXL/MIDI/GP kicsomagolás; nincs új dependency; nincs új asset. A
hivatkozott `evaluation/recognition/baseline_manifest.json` szándékosan az
E14-R02-re halasztva.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | 1519 files (0 changed) | ✅ |
| analyze | No issues found! | ✅ |
| célzott teszt | 8/8 „All tests passed!" | ✅ |
| architecture | OK (12 allowlisted deviation) | ✅ |
| secret scan | 0 findings | ✅ |
| Router CI (exact-SHA) | success | ✅ |
| Full Gate (no APK) (exact-SHA) | success | ✅ |

## Merge-döntés

ADR 0052: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge engedélyezett.
**0 CRITICAL, 0 BLOCKER, 0 MAJOR.** Az egyetlen MINOR (F1) javítva. **Verdikt:
APPROVED.**
