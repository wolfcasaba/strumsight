# E04-R23 — Security Review (READ-ONLY)

- **Kör:** E04-R23 — Safety, prompt-injection, usage & evaluation gate
- **Branch:** `codex/e04-r23-safety-injection-usage-evaluation-gate`
- **Diff:** `616cb15..ea90c18` (worktree: `/home/ubuntu/ss-deepseek-e04-r23`)
- **Reviewer szerep:** biztonsági reviewer (READ-ONLY, nem javít, nem ír production kódot)
- **Risk:** high — kötelező security review
- **Dátum:** 2026-08-06

## Áttekintés — mit néztem végig

| Terület | Fájl(ok) | Bizonyíték |
|---|---|---|
| Prompt-injection / tool-permission | `tutor_safety_policy.dart`, `backend/app/tutor/safety.py` | `evaluate()` teljes kódútvonala olvasva |
| Invented-metric hard-block | `tutor_claim_validator.dart`, safety policy | `validate()` + `inventedMetric` ág |
| Redaction / PII / telemetria | `backend/app/tutor/redaction.py` | teljes modul + import-lista + tesztek |
| Eval-gate integritás | `evaluation/tutor/run_eval.dart`, `.github/workflows/tutor-eval.yml` | metrika-számítás + exit-kód + trigger |
| Secret a workflow/dataset-ben | `tutor-eval.yml`, `safety_categories.json`, tesztek | regex-scan (AKIA/ghp_/AIza/sk-…) + szemantikus nézet |
| Dataset → dev/CI injection | `safety_categories.json` | értékek felhasználásának nyomonkövetése |
| Export-határ | `public.dart` | additív export, nincs belső leak |

Módszertani megjegyzés: a kör `allowed_paths` listája **csak** a policy/validator/eval
könyvtárrétegeket engedi (nincs benne orchestrátor/runtime wiring). A leletek ehhez a
szándékolt scope-hoz mérve értendők.

---

## Leletek

### MAJOR

**M1 — Az eval-gate két metrikát mért értékként közöl, de hardcode-olt 100%**
- **Fájl:sor:** `evaluation/tutor/run_eval.dart:157-160`
  (`final schemaValidity = 100; final actualValidity = 100;`), a küszöb-ellenőrzés
  `run_eval.dart:196-206`, a workflow-fejléc `tutor-eval.yml:6` („Four metrics … ANY
  metric below threshold → RED").
- **Failure scenario:** egy jövőbeli változás elrontja a tutor kimeneti JSON-sémáját
  vagy egy action-validitást. A `tutor-eval` gate ettől függetlenül `schema_validity:
  100% / action_validity: 100%` sort ír, zöldet ad, a reviewer/CI pedig a „4-metrikás
  kapu" ígéretében bízva mergel. A négy hirdetett gate-dimenzióból kettő **soha nem tud
  pirosra váltani** — a kód nem méri őket, konstansként jelenti.
- **Sértett szabály:** eval-gate integritás (feladat #4, „Megkerülhető-e a gate?"), és
  szellemében a §5.1/§5-ös „gyenge/nem mért confidence nem jelenhet meg biztos
  állításként" — a gate saját maga állít bizonyíték nélküli „100% mért" értéket, épp
  abban a körben, amelynek fő tétele az invented-metric hard-block.
- **Enyhítés (a kódban dokumentálva):** a séma/action validitást az R16
  `TutorOutputValidator`/`TutorActionValidator` unit-tesztjei fedik — tehát a regresszió
  máshol elbukna. Ettől ez nem határsértés, de a `tutor-eval` gate ezt a két számot ne
  jelentse „mért 100%"-ként.
- **Javasolt irány:** vagy ténylegesen számítsd a két metrikát a datasetből, vagy vedd
  ki őket a jelentett metrika-halmazból (és a workflow-leírásból), hogy ne keltsen hamis
  biztonságérzetet. Ne konstans 100%-ként közöld.

---

### MINOR

**m1 — Coverage-metrikák `.round()`-olása elfedhet küszöb-alatti bukást (látens)**
- **Fájl:sor:** `run_eval.dart:150-155` (`(safetyPassed / totalEntries * 100).round()`,
  `(groundedPassed / groundedTotal * 100).round()`), küszöb-check `:196-206`.
- **Failure scenario:** ha a dataset ≥ ~200 cellára nő és pontosan 1 bukik (pl. 199/200 =
  99.5%), a `.round()` 100%-ra kerekít, a `safetyCoverage < 100` hamis lesz → a gate
  **zöld marad** egy valós safety-miss ellenére. A `failures` lista kiíródik, de az
  `allGreen` csak a kerekített számot nézi. A jelenlegi 16-cellás dataseten még nem
  kihasználható (15/16 = 94% → piros), ezért MINOR/látens.
- **Sértett szabály:** eval-gate integritás (#4).
- **Javasolt irány:** egész-arány összehasonlítás (`safetyPassed == totalEntries`) vagy
  `floor`/exact-tört küszöbölés a `.round()` helyett.

**m2 — A `sk-` redaction/detekció minta kihagyja a modern `sk-proj-`/`sk-svcacct-` kulcsokat**
- **Fájl:sor:** `backend/app/tutor/safety.py:99-105` (`_REDACTION_PATTERN`, `sk-[a-zA-Z0-9]{8,}`),
  tükrözve `tutor_safety_policy.dart:167-173`.
- **Failure scenario:** egy `sk-proj-ABCD1234...` alakú kulcs a kimenetben nem illeszkedik
  (a `sk-` után `proj` csak 4 alfanumerikus, majd `-` megtöri a `{8,}`-at), így nem vált
  ki `REDACTION_REQUIRED` blokkot — heurisztikus detekciós rés.
- **Sértett szabály:** §5.3 (secret nem szivároghat) — itt csak detektor-heurisztika, nem
  a gépi `check_secrets` kapu; jelenleg egyik modul sincs runtime-ba kötve (lásd N1).
- **Javasolt irány:** engedd meg a kötőjelet a kulcstestben (`sk-[a-zA-Z0-9-]{8,}`) vagy
  fedd le a prefixelt formákat.

**m3 — A credential-request regex szinonimákkal megkerülhető**
- **Fájl:sor:** `safety.py:85-92` / `tutor_safety_policy.dart:151-157`.
- **Failure scenario:** „Type your password here", „Send me your login", „Share the API
  key with me" NEM illeszkedik (a minta csak `enter/provide/what is/share your/tell me`
  variánsokat fed). Az AI ilyen megfogalmazású credential-kérése átmegy a
  `credentialRequest` szűrőn.
- **Sértett szabály:** defense-in-depth heurisztika (nem határsértés).
- **Javasolt irány:** bővítsd az ige-listát, vagy egészítsd ki egy általánosabb
  „password|api key|credentials" + kérő-kontextus mintával.

---

### NOTE

- **N1 — A policy/redaction egyik oldalon sincs runtime-ba kötve.** `grep` szerint sem a
  Dart `TutorSafetyPolicy`/`TutorClaimValidator`, sem a Python `SafetyPolicy`/`Redactor`/
  `ContentSizeGuard` nincs meghívva production-útvonalon (csak tesztek + `run_eval.dart`).
  Ez a kör `allowed_paths`-ával összhangban van (nincs orchestrátor-fájl a listában), de
  rögzítendő: a safety-garanciák jelenleg **izoláltan tesztelve**, nem futásidőben
  kényszerítve élnek. A wiring-kört követni kell.
- **N2 — Az injection flag-vezérelt.** A policy `hasInjection`/`has_injection` bemenő
  flaget fogyaszt; a mintázat-detekció upstream (R12 / ADR 0141) történik, nem ebben a
  diffben. Ha a hívó elmulasztja beállítani a flaget, az injection csendben átmegy
  (a flagre nézve fail-open). Ez a diffből nem bizonyítható rés, de a wiring-review-ban
  ellenőrizni kell, hogy a detektor mindig kitölti a flaget. Pozitívum: maga a policy
  helyesen **soha nem emel tool-permissiont** (lásd lent).
- **N3 — `redaction.py` nem szállít alapértelmezett szabálykészletet.** A `Redactor`
  szabályokat a hívótól kapja; `test_no_rules_means_no_redaction` igazolja, hogy üres
  szabálylistával passthrough. Nem kötve → jelenleg nincs futásidejű következmény, de a
  wiringnél gondoskodni kell valós PII/credential-szabályok injektálásáról.
- **N4 — A workflow path-szűrő nem tartalmazza a backend `safety.py`-t.** A `tutor-eval.yml`
  csak a két `.dart` service-re + eval-fájlokra triggerel; egy backend-only változás nem
  indítja a gate-et (a gate amúgy is csak a Dart policyt teszteli). Required-status
  konfiguráció repo-beállítás, scope-on kívül.

---

## Pozitív igazolások (üres-lelet = bizonyíték)

1. **Prompt-injection SOHA nem emel tool-permissiont (ADR 0133).** A `evaluate()` mindkét
   nyelven kizárólag a `blocked` halmazhoz *ad hozzá* kategóriát; sehol nincs
   permission-adó/emeloő kódág (nincs is tool-permission fogalom a modulban).
   `safety.py:113-115`, `tutor_safety_policy.dart:191-192`. Megfelel §5.1-nek és a #1
   fókusznak.
2. **Invented-metric HARD block, nem „figyelmeztetés".** `tutor_claim_validator.dart:112-119`
   `unsupportedClaimEvidence` issue-t ad (bizonyíték nélküli `measuredFact`/`computedTrend`/
   `knowledgeFact`), az `isValid` ettől `false`; a safety policy `inventedMetric`-et a
   `blocked`-hoz adja. Nincs „warn-and-pass" ág. Megfelel §5.1 / #5 fókusznak és a R16
   grounding taxonómia újrahasznált (nem forkolt): `groundedClaimTypes` egyezik.
3. **Nincs cloud-secret a workflow-ban.** `tutor-eval.yml`: `permissions: contents: read`,
   nincs `secrets.*` hivatkozás, csak `subosito/flutter-action` + `dart run`. Fake/approved
   provider. Megfelel §5.3 / #3 fókusznak.
4. **Nincs valódi secret a datasetben/tesztekben.** Regex-scan (`AKIA|ghp_|xox|AIza|glpat-|
   BEGIN`) üres. A `sk-abc123`, `secret=xyz789`, `Bearer eyJ…` értékek nyilvánvaló, rövid
   placeholder-fixture-ök; a gépi őr a `check_secrets`, szemantikailag valódi fake-ek. A
   secret értékét itt nem közlöm, csak a helyét (dataset `redaction-01`, backend-teszt
   redaction-cellák).
5. **A dataset „ignore previous instructions…" / „enable forbiddenTool" sztringjei inertek.**
   Az eval-harness ezeket `outputText`-ként olvassa és regex/flag-illesztéssel hasonlítja
   — soha nem értelmezi utasításként, nem hajtja végre. Nincs dev-rendszer/CI-injection
   (§5.1 / #6 fókusz). A `injection-02-no-permission` cella épp azt pinneli, hogy az
   injection csak blokkot ad, permissiont nem.
6. **Nincs rejtett hálózat / telemetria / content-logging az új backend modulokban.** A
   `safety.py` és `redaction.py` kizárólag stdlib `re`/`enum`/`dataclasses`-t importál;
   nincs `requests`/`httpx`/`socket`/`logging`/`print`. A `ContentSizeGuard` hibaüzenete
   csak méretet közöl, tartalmat nem (`redaction.py:80-83`). Így ADR 0132
   (content-telemetry csak consenttel) itt nem is sérthető — nincs telemetriai kód. Nincs
   silent-swallow `try/except` a redaction/size-guard úton.
7. **Eval-gate küszöb-alatt piros.** `run_eval.dart` `exitCode = allGreen ? 0 : 1`; a
   `dart run` nem-nulla kilépése a job step-et bukatja. A „Verify eval exits green" step
   csak echo, és csak a bukó step *sikere után* fut — nincs „warning-pass" megkerülés.
   (A gate-integritás gyengeségeit lásd M1/m1.)

---

## Összegzés

Nincs CRITICAL és nincs BLOCKER: bizonyított titok-szivárgás, consent-megkerülés,
path-traversal/RCE vagy nem-tárgyalható termékhatár-sértés nem található. A safety-policy
helyesen fail-closed és soha nem emel permissiont; az invented-metric hard-block; a
workflow secret-mentes; a dataset injection-sztringjei inertek. A leletek az eval-gate
integritásának hitelességét (M1, m1) és néhány heurisztikus detekciós rést (m2, m3), illetve
a még-nem-bekötött voltot (N1–N3) érintik — ezek follow-up/wiring-review tárgyai, nem
merge-blokkolók.

| Súlyosság | Darab |
|---|---|
| CRITICAL | 0 |
| BLOCKER | 0 |
| MAJOR | 1 |
| MINOR | 3 |
| NOTE | 4 |

SECURITY VERDICT: PASS

Nyitott leletlista (nem blokkoló): M1 (eval-gate két metrikája hardcode 100%), m1
(round()-elfedés látens), m2 (sk-proj kulcs kimarad), m3 (credential-regex szinonima-rés),
N1–N4 (wiring/flag/default-rules/path-filter follow-up).
