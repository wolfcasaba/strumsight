# E12-R34 — Post-launch stabilization, hotfix és incident automation

- **Státusz:** READY (pre-flight újramérve 2026-09-02, `main @ aefe4755`; eredetileg előre megírva 2026-08-27, `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 34
- **Kör-azonosító:** `E12-R34`
- **Branch:** `<motor>/e12-r34-post-launch-stabilization-and-hotfix`
- **Előfeltétel:** `E12-R33` merge-elve (GA-rekord)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** ~~`ADR 0465`~~ → **`ADR 0490`** (a §0.0.P1 pre-flight revízió szerint: a foglalótól MÉRVE; a `0465` a Chapter 12 batch elavult, sosem kiosztott száma).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "post launch stabilization hotfix workflow incident postmortem"` → a `halts/halted-20260813T040134.txt` (E06-R23 H-INDEP) és a `halts/round-status-E{07,08}-R*` merge-elt körök. Release-domain előzmény nincs; a hotfix-út a Kör 25 RC-workflow-jának SZŰKÍTETT változata.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 25 `release-candidate.yml` szerkezetét (composite gate-hívás + manuális jóváhagyás) — a hotfix-workflow ugyanazt a composite actiont használja, csak szűkebb scope-pal. Ha a Kör 25 workflow-ja időközben változott, a §3 igazodjon.
>
> **ELVÉGEZVE (2026-09-02, §0.0.P2/P4):** a Kör 25 workflow-ja **nincs
> telepítve** — javaslat-fájlként él. A mért szerkezet a §0.0.P4-ben.

## 0.0.P — Pre-flight revízió (2026-09-02, `main @ aefe4755`)

Az orchestrátor (Claude, Opus 5) a fán ÚJRAMÉRTE a brief állításait. Négy
lelet; mindegyik a kör SAJÁT, még nem merge-elt briefjét érinti, tehát az
ADR 0087 §2 szerint az orchestrátor hatáskörében oldható fel.

**Visszakeresés (ADR 0312, KÖTELEZŐ, szűkítve → teljes):**
`--corpus lessons,halts,adr "post launch stabilization hotfix workflow incident postmortem"` →
release-domain előzmény NINCS (a találatok merge-elt kör-jelzések: E07-R23/R26/R30, E08-R09).
`--corpus lessons,halts "workflow proposal yaml parser static gate python verify script security scan signing bypass"` →
[L245](../LESSONS.md#l245) (a `gate_shape=VIOLATION` jelző hamis pozitív lehet: a
gate SZKRIPT FORRÁSÁNAK olvasása nem csonkított gate-futtatás),
[L130](../LESSONS.md#l130) (a factory-őr egy `rm`/`cp`/`tee` MELLETT ugyanabban a
Bash-hívásban futó `round-gate.sh`-t is védett-írásnak látja → a gate KÜLÖN parancs
legyen), [L139](../LESSONS.md#l139) (a domain-only kör-gate nem a teljes suite),
`halts/halted-20260819T095318.txt` (E99-R17 **H-GATEGUARD**: a `tool/ci/*` glob
blokkolta a szerkesztést). Teljes korpuszon: a Ch12 SDD §12 „Kötelező tesztek"
listája (regression suite minden hotfixhez; hotfix signing/provenance gate;
missing incident ID fail; version increment enforcement) — a §6 acceptance ezt fedi.

### P1 — Az előre kiosztott `ADR 0465` elavult → **`ADR 0490`**

**Mérve:** `tools/round-slots.py reserve-adr --round E12-R34` → `0490`.
A `docs/adr/` a `0489`-ig telített, a `0465` pedig LYUK: sosem került kiosztásra.
A Chapter 12 batch előre kiosztott számai (`0460`–`0465`) végig elavultak — a
Kör 22 (`0461` → `0486`) és a Kör 25 (`0463` → `0488`) ugyanígy, pre-flight
revízióval cserélte le őket. **Feloldás:** a kör ADR-je a **0490**; a §5 címe és
minden hivatkozás erre a számra mutat. A `0465`-öt a kör NEM használja.

### P2 — A §2 első mért ténye HAMIS: `release-candidate.yml` nincs telepítve

**Mérve:** `ls .github/workflows/` → `backend-ci.yml`, `build-apk.yml`,
`chord-train.yml`, `dsp-probe.yml`, `full-gate.yml`, `lab-apk.yml`,
`ml-train.yml`, `release-apk.yml`, `router-ci.yml`, `tutor-eval.yml`.
`release-candidate.yml` **nincs köztük**; a Kör 25 terméke a
`docs/release/workflows/release-candidate.proposal.yml` **javaslat-fájl**
(a `.github/workflows/**` védettsége miatt, ADR 0488 D1).
**Feloldás:** a §2 első sora a mért állapotra javítva (lentebb). Ez a kör
irányát MEGERŐSÍTI: a hotfix ugyanazt a javaslat-formát örökli.

### P3 — A §2 `tool/release/` felsorolása hiányos

**Mérve:** `ls tool/release/` a §2-ben felsoroltakon túl tartalmazza:
`ai_report_schema.json`, `build_diagnostics_bundle.py`, `generate_beta_notes.py`,
`production_smoke.py`, `verify_beta_profile.py`, `verify_ga_scope.py`.
`verify_hotfix.py` **nincs** — a kör terméke tehát valóban ÚJ fájl.
**Feloldás:** a §2 listája a mért állapotra javítva.

### P4 — Az A6 lépés-sorrendje MÉRTEN fordított

**Mérve** a `release-candidate.proposal.yml` job-gráfjából: a jóváhagyás a
build ELŐTT áll, nem utána —
`approve-release-candidate` (az EGYETLEN `environment:` kulcs, `needs:` nélkül) →
`quality-gates` és `backend-tests` (`needs: approve-release-candidate`) →
`build-release-candidate` (`needs: [quality-gates, backend-tests]`).
A brief A6 zárójeles sorrendje („composite gate → jóváhagyás → build") tehát a
precedens ELLENTÉTE. **Feloldás:** az A6 a mért mintára javítva (lentebb),
és az ADR 0490 D3 ezt szerződésbe önti.

### P5 — A `verify_hotfix.py` CLI-szerződése rögzítve

A §7 csak a `--workflow` hívást mutatja, az A1/A3 viszont *kérés*-szintű
ellenőrzést ír elő (hiányzó incident-azonosító, elmaradt verzió-emelés), amit
egy dokumentum-statikus mód nem tud mérni. Az ADR 0088 „egy szkript, két mód"
kétértelműsége javító kört okozna, ezért a szerződés itt kötött (a
`verify_signing_policy.py` / `verify_rollout_decision.py` argparse-mintája
szerint, `main(argv) -> int`, `sys.exit(main(...))`):

| Mód | Kapcsolók | Mit mér | Kilépési kód |
|---|---|---|---|
| **statikus** (default) | `--workflow` (default: `docs/release/workflows/hotfix.proposal.yml`) | a javaslat-dokumentum: `required: true` incident-input; feltétel NÉLKÜLI security-scan és production signing lépés; jóváhagyó job `environment:`-tel, amit minden építő job tranzitívan `needs:`-el | 0 = megfelel, 1 = sértés (a sértés SZÖVEGESEN kiírva) |
| **kérés** | `--incident-id`, `--previous-version`, `--version` | az incident-azonosító nemüres, és a `--version` **szigorúan nagyobb** a `--previous-version`-nél | 0 = megfelel, 1 = sértés |

A két mód UGYANABBAN a szkriptben él; a `--incident-id` megadása kapcsolja a
kérés-módot. A verzió-összehasonlítás szemantikája a Kör 6
`tool/release/verify_artifacts.py` monotonitás-ellenőrzéséé — **azzal azonos
vagy szigorúbb**, sosem lazább (ADR 0490 D5).

## 0.0 Mit szállít a kör, és mit a user

A napi health-review és a 7./14. napi riport ADATA a GA utáni valóságból jön (user + support); a riportok KITÖLTÉSE emberi lépés.

**A hotfix-workflow ráadásul VÉDETT zóna:** a `.github/workflows/**` a `protect_factory_files.py` `PROTECTED_GLOBS` listáján van (ADR 0321), és az ADR 0372 álló felhatalmazásának fájlja (`.claude/gate-edit-policy`) a fán MA NEM létezik — a pre-flight ezt MÉRTE. Az implementer terméke ezért: a hotfix-workflow teljes tartalma JAVASLATKÉNT (`docs/release/workflows/hotfix.proposal.yml`), a `verify_hotfix.py` mérce, a runbook és a sablonok. A telepítés és a dispatch orchesztrátor/emberi lépés a merge UTÁN.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "docs/release/workflows/hotfix.proposal.yml",
  "tool/release/verify_hotfix.py",
  "docs/operations/hotfix-runbook.md",
  "docs/operations/postmortem-template.md",
  "docs/release/post-launch-day7.md",
  "docs/release/post-launch-day14.md",
  "test/tooling/hotfix_policy_test.dart",
  "docs/rounds/e12-r34-post-launch-stabilization-and-hotfix.md",
]
gate_tests = [
  "test/tooling/hotfix_policy_test.dart",
  "test/tooling/rc_assembly_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a hotfix-út a leggyorsabb út a production felé; ha megkerülhetővé válik a security/signing kapu, az a teljes release-védelmet üresíti ki. A `security-reviewer` futtatása a review-ban KÖTELEZŐ.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a hotfix-workflow-hoz a merge-kapu (`build-apk.yml` / `full-gate.yml`) módosítása kellene, a kimenet a `stopped` jelzés.

## 1. Cél

Auditálható, gyors, de kapukat NEM megkerülő hotfix-út, incident- és postmortem-eljárás, valamint a 7./14. napi stabilizációs riport váza.

## 2. Jelenlegi állapot — mért tények

- `.github/workflows/` (MÉRVE 2026-09-02, §0.0.P2): `backend-ci.yml`, `build-apk.yml`, `chord-train.yml`, `dsp-probe.yml`, `full-gate.yml`, `lab-apk.yml`, `ml-train.yml`, `release-apk.yml`, `router-ci.yml`, `tutor-eval.yml`. **`release-candidate.yml` NINCS** — a Kör 25 terméke a `docs/release/workflows/release-candidate.proposal.yml` javaslat-fájl. `hotfix.yml` szintén **nincs**.
- `docs/release/workflows/` (a javaslat-fájlok mai helye): `release-apk-fingerprint.proposal.md`, `release-apk-provenance.proposal.md`, `release-candidate.proposal.yml`. `hotfix.proposal.yml` **nincs**.
- `tool/release/` (MÉRVE, §0.0.P3): `ai_report_schema.json`, `assemble_rc.py`, `build_ai_report.py`, `build_diagnostics_bundle.py`, `generate_beta_notes.py`, `generate_sbom.py`, `production_smoke.py`, `security_scan.py`, `verify_artifacts.py`, `verify_beta_profile.py`, `verify_freeze.py`, `verify_ga_record.py`, `verify_ga_scope.py`, `verify_rollback.py`, `verify_rollout_decision.py`, `verify_signing_policy.py`. **`verify_hotfix.py` nincs.**
- `.claude/hooks/protect_factory_files.py:56-63` `PROTECTED_GLOBS`: `tool/ci`, `tool/ci/*`, `.github/workflows`, `.github/workflows/*`. A **`tool/release/*` NEM védett** — a `verify_hotfix.py` írható. A `.claude/gate-edit-policy` (ADR 0372) a fán **nem létezik**.
- `docs/operations/`: `backend-deploy.md`, `database-recovery.md`, `disaster-recovery-drill.md`, `capacity-review.md`, `slo.yaml`, `release-dashboard.md`, Community moderation runbook; hotfix-runbook és postmortem-sablon **nincs**.
- A verzió-monotonitás ellenőrzése a Kör 6 `verify_artifacts.py`-jában él — a hotfix-út ezt HÍVJA.

## 3. Scope

**Benne van:** `docs/release/workflows/hotfix.proposal.yml` — a JAVASOLT hotfix-workflow teljes tartalma (hotfix branch-ről indítható, manuális jóváhagyással; a `flutter-gates` composite + az ÉRINTETT terület teljes regressziója; kötelező incident-azonosító input; a Kör 6/7 provenance és signing lépések VÁLTOZATLANUL) · `tool/release/verify_hotfix.py` (kötelező incident-azonosító, verzió-emelés kényszerítése, a security-scan és signing lépés MEGLÉTÉNEK statikus ellenőrzése a workflow-ban) · `docs/operations/hotfix-runbook.md` · `docs/operations/postmortem-template.md` · `docs/release/post-launch-day{7,14}.md` (váz kötelező mezőkkel) · `test/tooling/hotfix_policy_test.dart`.

**NINCS benne (tilos):**

- **Bármely `.github/workflows/**` fájl írása** (a §0.0 szerint: védett mérce-zóna).
- Tényleges hotfix kiadása.
- A security/signing lépések kihagyása vagy feltételessé tétele.
- `docs/adr/**` — az **ADR 0490**-et a Claude MÁR MEGÍRTA a pre-flightban (§0.0.P1); az implementer csak HIVATKOZIK rá.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/release/workflows/hotfix.proposal.yml` | ÚJ — a hotfix-workflow JAVASLATA (a telepítés emberi lépés) |
| `tool/release/verify_hotfix.py` | ÚJ — a hotfix-mérce |
| `docs/operations/hotfix-runbook.md` | ÚJ — eljárás |
| `docs/operations/postmortem-template.md` | ÚJ — postmortem sablon |
| `docs/release/post-launch-day7.md` | ÚJ — 7. napi riport váza |
| `docs/release/post-launch-day14.md` | ÚJ — 14. napi riport váza |
| `test/tooling/hotfix_policy_test.dart` | a §6 cellái |

**Tilos zóna:** `.github/workflows/**` (MIND, a §0.0 szerint) · `.github/actions/**` · `lib/**` · `backend/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések ([ADR 0490](../adr/0490-hotfix-path-gates-incident-binding-and-regression-obligation.md))

> Az ADR 0490-et az orchestrátor a pre-flightban MEGÍRTA és commitolta — a §5
> alábbi pontjai az ADR D1–D8 döntéseinek kör-szintű összefoglalói. Ütközés
> esetén az ADR szövege a mérvadó.

### 5.1 A hotfix NEM kerüli meg a security és signing kaput

**NEM elfogadható gyengítés:** „sürgős, ezért kihagyjuk a scant" ág — a gyorsaság a SCOPE szűkítéséből jön (kevesebb változás), nem a kapuk elhagyásából.

### 5.2 Incident-azonosító nélkül nincs hotfix

**NEM elfogadható gyengítés:** opcionális mező.

### 5.3 Minden hotfixhez tartozik regressziós teszt

A javítás mellé a hibát REPRODUKÁLÓ cella kerül. **NEM elfogadható gyengítés:** „a manuális ellenőrzés elég".

### 5.4 A jóváhagyás a build ELŐTT áll (ADR 0490 D3, §0.0.P4)

A javaslatban PONTOSAN EGY job hordoz `environment:` kulcsot, és minden olyan
job, amely buildel, aláír, összeállít vagy feltölt, közvetlenül vagy tranzitívan
`needs:`-eli ezt. **NEM elfogadható gyengítés:** jóváhagyás a build UTÁN, vagy
olyan `workflow_dispatch` input, amely a jóváhagyó jobot kihagyhatóvá teszi.

### 5.5 A verzió-emelés kényszerített (ADR 0490 D5)

A `verify_hotfix.py` kérés-módja nem-nulla kóddal lép ki, ha a hotfix verziója
nem **szigorúan nagyobb** az előzőnél. A szemantika a Kör 6
`tool/release/verify_artifacts.py` monotonitás-ellenőrzéséé — azzal azonos vagy
szigorúbb, sosem lazább.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A javaslatban az incident-azonosító KÖTELEZŐ input (`required: true`), és a `verify_hotfix.py` a hiányát nem-nulla kóddal jelzi | `hotfix_policy_test.dart` |
| A2 | A workflow tartalmazza a security-scan és a production signing lépést | `hotfix_policy_test.dart` statikus cellája |
| A3 | Verzió-emelés nélkül a `verify_hotfix.py` nem-nulla kóddal lép ki | `hotfix_policy_test.dart` |
| A4 | A hotfix-runbook megköveteli a regressziós cellát a javítás mellé | a runbook + `hotfix_policy_test.dart` |
| A5 | A 7./14. napi riport váza kötelező mezőket definiál (crash, migráció, akku, audio, support) | a dokumentumok + a teszt cellája |
| A6 | A javaslat YAML-je valid, és a job-gráf a Kör 25 RC-mintáját követi (**§0.0.P4 MÉRT sorrend: jóváhagyás → composite gate → build**): PONTOSAN EGY job hordoz `environment:` kulcsot, és minden építő/aláíró/összeállító/feltöltő job tranzitívan `needs:`-eli | `hotfix_policy_test.dart` |
| A7 | A javaslat a közös mérce-láncot a composite actionnel HÍVJA (`uses: ./.github/actions/flutter-gates`), és egyetlen lépése sem MÁSOLJA a composite `run:` parancsait | `hotfix_policy_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

Minden sor MUTÁCIÓS PRÓBA: az implementer a fixtúrán bizonyítja, hogy a hibás
alak a megnevezett cellát TÉNYLEG pirosra váltja (L563 — a cella ne legyen zöld
a törött implementáción). A próbák a teszt saját fixtúráin futnak, nem a
valódi fájlokon (kivéve a §6.2 kötelező valódi-sértés próbát).

| Hibás implementáció | Melyik cella vált PIROSRA | Melyik őr méri |
|---|---|---|
| A javaslat `if: inputs.skip_scan != true` ágat kap a security-scan lépésre | **A2** | statikus fixtúra-cella (`verify_hotfix.py --workflow <fixtúra>` → exit 1) |
| A security-scan lépés teljesen kimarad a javaslatból | **A2** | ua. |
| A production signing lépés kimarad vagy `continue-on-error: true`-t kap | **A2** | ua. |
| Az incident-azonosító `required: false` (vagy hiányzó `required:`) input lesz | **A1** | statikus fixtúra-cella |
| A `verify_hotfix.py` üres `--incident-id`-ra 0-val lép ki | **A1** | kérés-módú cella |
| A `verify_hotfix.py` azonos vagy csökkenő verzióra 0-val lép ki | **A3** | kérés-módú cella (`--previous-version 1.2.0 --version 1.2.0` → exit 1) |
| A runbook nem követel regressziós cellát a javítás mellé | **A4** | dokumentum-cella (kulcsszó-invariáns a runbookon) |
| A 7./14. napi riportból hiányzik a kötelező mezők bármelyike (crash, migráció, akku, audio, support) | **A5** | dokumentum-cella mind az öt mezőre, MINDKÉT riporton |
| A jóváhagyó job a build UTÁN áll, vagy egy építő job nem `needs:`-eli tranzitívan | **A6** | job-gráf cella (tranzitív `needs:` bejárás) |
| Két job kap `environment:` kulcsot (a jóváhagyás megkerülhetővé válik) | **A6** | ua. |
| A javaslat a composite `run:` parancsait MÁSOLJA a `uses:` hívás helyett | **A7** | pontos-egyezés cella a composite parancsokra |

### 6.2 Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva)

Vedd ki a security-scan lépést a **valódi** `docs/release/workflows/hotfix.proposal.yml`-ből,
futtasd a §7 gate-et → az **A2** cellának PIROSNAK kell lennie (a gate
kimenetét szó szerint másold a §10-be) → állítsd vissza, és a gate legyen
újra ZÖLD (ezt is dokumentáld).

### 6.3 Numerikus küszöb — a verzió-monotonitás cellahármasa (S3)

Az A3 egyetlen numerikus küszöbe a verzió-összehasonlítás. A `hotfix_policy_test.dart`
mindhárom oldalt mérje, a `verify_hotfix.py` kérés-módján:

| Cella | `--previous-version` | `--version` | Elvárt exit |
|---|---|---|---|
| alatta | `1.2.3` | `1.2.2` | **1** (csökkenő verzió) |
| rajta | `1.2.3` | `1.2.3` | **1** (nincs emelés — a küszöb SZIGORÚ) |
| fölötte | `1.2.3` | `1.2.4` | **0** |

A „rajta" cella a lényeg: a szigorú `>` és a megengedő `>=` KÖZÖTT ez az
egyetlen különbség — enélkül az A3 egy `>=` implementáción is zöld maradna.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/hotfix_policy_test.dart test/tooling/rc_assembly_test.dart
```

A hotfix-mérce közvetlen futtatása MINDKÉT módban (kimenet a §10-be, a §0.0.P5
CLI-szerződés szerint):

```bash
python3 tool/release/verify_hotfix.py --workflow docs/release/workflows/hotfix.proposal.yml
python3 tool/release/verify_hotfix.py --incident-id INC-2026-0001 --previous-version 1.2.3 --version 1.2.4
python3 tool/release/verify_hotfix.py --incident-id INC-2026-0001 --previous-version 1.2.3 --version 1.2.3
```

Az első kettő `0`-val, a harmadik `1`-gyel lép ki (§6.3 „rajta" cella). A
kilépési kódot `echo "exit=$?"`-fel írd ki — csővezeték és `tail` nélkül.

A javaslat telepítése és a dispatch orchesztrátor/emberi lépés a merge UTÁN — az implementer sem `.github/`-ot nem ír, sem `gh`-t nem hív.

## 8. Implementációs sorrend

1. `tool/release/verify_hotfix.py` — a statikus mérce ELŐSZÖR.
2. `test/tooling/hotfix_policy_test.dart`.
3. `docs/release/workflows/hotfix.proposal.yml` — a composite gate + manuális jóváhagyás + incident-input.
4. `docs/operations/hotfix-runbook.md` és `postmortem-template.md`.
5. A két post-launch riport váza + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Kapu-megkerülés.** A hotfix a legvalószínűbb hely, ahol a „sürgősség" kikapcsolja a védelmet (A2).
- **Regresszió nélküli javítás.** A hiba visszatér a következő kiadásban (A4).
- **Riport-illúzió.** Kitöltetlen váz nem stabilizáció — a dokumentum kimondja, hogy a kitöltés emberi lépés.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
