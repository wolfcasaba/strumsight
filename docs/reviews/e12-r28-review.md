# E12-R28 — Review (Beta stabilization és scope cut)

- **Kör:** `E12-R28` · **Branch:** `sonnet-impl/e12-r28-beta-stabilization-and-scope-cut`
- **Implementer:** Claude Sonnet 5 (`sonnet-impl`), commit `99451ed9`
- **Reviewer:** Claude (orchesztrátor), 2026-09-02 — **read-only**, production kód nem íródott
- **Kör-induló HEAD (pre-flight):** `e3d4a1a5`
- **ADR:** [0489](../adr/0489-ga-scope-classification-and-contract-freeze.md)

## 1. menet — VERDIKT: **CHANGES REQUESTED** (2 MAJOR, 0 BLOCKER)

> **2. menet (javító kör, commit `25cad21f`) — VÉGSŐ DÖNTÉS: APPROVED.**
> Mindkét MAJOR zárva, leletenként ÚJRAMÉRVE friss `/tmp/review-e12-r28b`
> klónban. A záró mérés a jelentés végén (**„2. menet"** szakasz).

## Amit magam mértem (nem bemondásra)

### Gate — izolált klónban ÚJRAFUTTATVA

`/tmp/review-e12-r28` (a GitHub-remote-ról klónozva, `99451ed9`), a
`tools/prepare-flutter-generated.sh` után:

```
tools/round-gate.sh test/tooling/ga_scope_test.dart test/tooling/beta_profile_test.dart
    format                                                     zöld
    analyze                                                    zöld
    test test/tooling/ga_scope_test.dart                       zöld
    test test/tooling/beta_profile_test.dart                   zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
GATE_EXIT=0
```

Az A6 (a Kör 27 `beta_profile_test.dart` VÁLTOZATLANUL zöld) ezzel igazolt — a
fájl a diffben nem szerepel.

### Scope-audit — a hiteles eszközzel

```
Legacy scope audit OK (e3d4a1a54bda..99451ed9afb3, 6 changed path(s), 0 generated/ignored)
```

A 6 útvonal pontosan a brief `allowed_paths` listája. A
`docs/beta/cohort-profiles.yaml` egyetlen commitolt sora sem változott — a §6.1
valódi-sértés próba mutációja tényleg vissza lett állítva.

### Eldobható próbatesztek (a klónban, mind visszaállítva)

| # | Mutáció | Várt | Mért |
|---|---|---|---|
| P1 | core-path lépés `preview` capabilityre mutat | piros | **exit 1**, `labModeAvailable … classified 'preview'` (D5) |
| P2 | capability-kulcs backtick nélkül (row_start-miss) | piros | **exit 1**, `'accountEnabled' has no classification row` (D1) |
| P3 | evidence egy **nem létező** béta-riportra mutat | piros | **exit 1**, `'docs/beta/closed-beta-results.md' does not exist` (D3) |
| P4 | NOT-READY fejléc → `GA-kész`, nyitott P0 mellett | piros | **exit 1**, két lelet (hiányzó marker + GA-kész állítás) (D7) |
| P5 | freeze feloldó feltétel → „szükség esetén módosítható" | piros | **exit 1**, `banned non-event` (D6) |
| P6 | egy capability-sor teljesen törölve | piros | **exit 1**, `'visionEnabled' has no classification row` (D1) |
| P8 | freeze-sor szóköz nélküli `|` + backtickes első cella, ÜRES feltétel | piros | **exit 1**, `empty resolution condition` (D6) |
| **P7** | **core-path sor szóköz nélküli `\|` + backtickes lépés-cella** | **piros** | **ZÖLD, exit 0** — lásd **MAJOR-1** |

A **D3 anti-fabrikációs őr tehát ténylegesen működik** (P3): a „hivatkozzunk egy
béta-riportra, ami nincs" támadás nem-nulla kilépés. Ez a kör legfontosabb
mércéje, és bizonyítottan piros.

### A dokumentum MÉRT állításainak visszaellenőrzése (tartalmi hűség)

| Állítás (`ga-scope.md`) | Mérés | Ítélet |
|---|---|---|
| `practiceEngineV2Enabled` kapuzza `AppRoutes.practiceHub`-ot (`app_router.dart:180-183`) | `lib/app/routing/app_router.dart:180-183` — `final practiceEnabled = ref.read(appConfigProvider).flags.practiceEngineV2Enabled` | ✅ pontos |
| ADR 0467 „a production GA-döntést erre a körre halasztja" | ADR 0467 **D2** szó szerint: „A GA-scope-ot a Chapter 12 **Kör 28** dönti el" | ✅ pontos, és a `preview` besorolás ténylegesen ki is mondja a döntést |
| `diagnosticsEnabled` production build-ben `false` | `lib/app/config/feature_flags.dart:77` — `diagnosticsEnabled: nonProd` | ✅ pontos |
| `aiTutorEnabled` / `visionLabCaptureEnabled` minden környezetben hardcode `false` | `feature_flags.dart:82`, `:96` | ✅ pontos |
| Epic 3 „release blockers still open" | `docs/sdd/epic-03-completion-report.md:65` — „## Nyitott release blockerek" | ✅ pontos |
| Epic 6 „rollout stays at shadow", `ShadowAnalysisRunner` hívó nélkül | `epic-06-completion-report.md:5` szó szerint; `ShadowAnalysisRunner` a `lib/`-ben csak a saját fájljában, hívó nélkül (csak contract-teszt) | ✅ pontos |
| Vision modell-manifest bejegyzések `deferred` | `assets/ml/model_manifest.json:131,150` — `"status": "deferred"` | ✅ pontos |

**Nulla kitalált béta-adat.** A `beta-findings.md` a MÉRT NOT-launched állapotot
rögzíti; egyetlen besorolás sem hivatkozik terepi mérésre. A kör az ADR 0489 D8
szerződését betartja.

---

## Leletek

### MAJOR-1 — a core-path tábla egy sora NÉMÁN eldobható, és ezzel az A3/D5 őr fail-OPEN

**Fájl:** `tool/release/verify_ga_scope.py:210-223` (`_parse_table`),
`_CORE_PATH_ROW_START` (`:176`).

**Mérés (P7, reprodukálható a klónban):** a core-path tábla egy sorát erre
cseréltem —

```
|`LabMode` overlay is required to finish onboarding | `labModeAvailable` | `test/e2e/returning_user_restart_test.dart` |
```

— azaz a vezető `|` után **nincs szóköz**, és a lépés-cella **backtickkel
kezdődik**, miközben a sor egy `preview` besorolású capabilityt (`labModeAvailable`)
jelöl a core út kötelező elemének. Ez pontosan az a tiltott állapot, amit az
ADR 0489 D5 / a brief A3 cellája hivatott megfogni. Mért kimenet:

```
verify_ga_scope: ok — 16 capability classification(s), 3 core-path step(s), 4 frozen contract(s), 6 open P0/P1 blocker(s)
exit=0
```

**ZÖLD.** A sor nem hibás — a sor **nem létezik** a tool számára: a
`_CORE_PATH_ROW_START` (`^\|\s*[^|` + backtick + `]`) nem illeszkedik, a
`_parse_table` pedig ilyenkor `continue`-t hajt végre (`:215`), tehát némán
eldobja. A kiírt darabszám 4-ről 3-ra esik, de ez a szám **semmihez nincs
kötve**, ezért nem is bukik el semmi.

Ez az `L566` fail-OPEN hibaosztály: ami nem illeszkedik a várt alakra, az nem
hibás, hanem NEM LÉTEZIK, és a tiltott állapot vákuumban „teljesíti" az
elvárást. A capability-tábla ugyanettől a hiánytól **véletlenül** védve van (a
független `missing_keys` teljességi ellenőrzés fogja meg — P2 pirosra váltott),
a core-path táblának viszont **nincs** teljességi ellenőrzése.

**Súlyosbító körülmény:** a modul-docstring (`:34-38`) kifejezetten az
ellenkezőjét állítja — „the number of candidate data-row line starts is
cross-checked against the number of fully-matched rows … never a
silently-dropped row". Ilyen kereszt-ellenőrzés a kódban NINCS. Egy nem
tesztben bizonyított doc-comment-állítás önmagában is szabálysértés (a
brief-prompt §4 „doc-commentben csak tesztben bizonyított állítás").

**Javasolt irány (NEM kész patch):** a `_parse_table` kösse a ténylegesen
parse-olt sorok számát a szekció nyers adat-sorainak számához (a
`_extract_table` már visszaadja mindet: a marker-blokk minden `|`-lel kezdődő,
nem-fejléc, nem-elválasztó sora **kötelezően** parse-olandó — ami nem
illeszkedik, az `VerifyError` a sor számával, nem `continue`). A javításnak
tartozzon **cella** is: a P7 mutáció (szóköz nélküli `|` + backtickes első
cella) a javítás ELŐTTI eszközzel zöld, utána piros. A docstring állítását
vagy implementáld, vagy javítsd a valóságra.

### MAJOR-2 — az EGYETLEN `ga` besorolású capability production build-ben `false`, és ezt a dokumentum nem rögzíti

**Fájl:** `docs/release/ga-scope.md:48` (és a §3 core-path tábla `:75`).

`practiceEngineV2Enabled` a kör egyetlen `ga` besorolása, és a core tanulási út
egyetlen capability-függő lépése rá támaszkodik. A `note` a **router-kaput**
idézi (`app_router.dart:180-183`) — ez pontos —, de **nem** rögzíti a mért
alapértelmezést:

```
lib/app/config/feature_flags.dart:73   final nonProd = environment != AppEnvironment.production;
lib/app/config/feature_flags.dart:78   practiceEngineV2Enabled: nonProd,
```

`FeatureFlags.forEnvironment`-ben **nincs** dart-define felülíró ág erre a
flagre (mérve: `grep -rn "practiceEngineV2" lib/app/config lib/core/feature_flags`
— csak a mező, a `nonProd` hozzárendelés, az `==`/`hashCode`/`toString`, és két
`app_config.dart`-beli **függőségi** szabály). Következmény: egy **production**
buildben a flag `false`, a `/practice*` route-ok nincsenek regisztrálva, tehát a
`ga-scope.md` §3 első sorában leírt core-út-lépés (Quick Start → offline
gyakorlás) **ma nem járható végig production build-en**.

A dokumentum tehát `ga`-nak minősít egy capabilityt, amelynek mért production
alapértelmezése `false`, és ezt a tényt sehol nem mondja ki. Ez a §9
„Rejtett GA" kockázatának tükörképe (rejtett NEM-GA): egy későbbi kör a
`ga-scope.md`-ből azt olvassa ki, hogy a gyakorlás production-ON, holott nincs.
A NOT-READY fejléc ezt **nem** fedi le — az a blocker-listáról szól (D7), nem a
flag-feloldásról, és nincs egyetlen cella sem, amely egy `ga` besorolást a
production-beli feloldhatóságához kötné.

**Javasolt irány (NEM kész patch, `lib/**` NEM módosítható):**

1. a `ga-scope.md` rögzítse a mért production alapértelmezést a `ga` sor(ok)
   `note`-jában (fájl:sor hivatkozással), és mondja ki nevesített feltételként,
   mi kell a production bekapcsoláshoz — a `contract-freeze.md`
   feloldási-feltétel mintája szerint;
2. a `verify_ga_scope.py` kapjon egy `ga`↔production-alapértelmezés
   konzisztencia-ellenőrzést (a `lib/app/config/feature_flags.dart`
   `forEnvironment` törzsét OLVASVA, fail-closed parse-szal), vagy — ha ez a
   kör kereteit feszítené — a `ga-scope.md` sor kötelezően hordozzon egy
   géppel ellenőrzött, kimondott `production_default` oszlopot/mezőt, amit
   cella köt a mért forráshoz;
3. tartozzon hozzá cella, amely a javítás ELŐTTI állapotban piros.

A kettő közül a **2.b** (kimondott, cellával kötött mező) a kisebb diff és
elegendő — a lényeg, hogy a tény kimondva és géppel őrizve legyen, ne
kimaradjon.

---

### MINOR-1 — a `postponed` besorolás flag-állapotát semmi nem köti

`tool/release/verify_ga_scope.py:383-391` csak a `disabled` besorolásra méri a
cohort-profilt (D4). Egy `postponed` capability, amit egy cohort `true`-ra
állít, ma nem lelet. **Élő rés nincs:** mind a hét `postponed` flag `false`
mindkét cohortban (mérve a `cohort-profiles.yaml`-ban). Az ADR 0489 D4 sem
követeli meg — ezért MINOR, nem MAJOR. Ha a javító kör hozzáér a toolhoz,
olcsón bezárható; egyébként follow-up.

### NOTE-1 — az evidence-útvonal a processz CWD-jéhez képest oldódik fel

`verify_ga_scope.py:377`, `:450` — `Path(evidence).exists()`. A gate a repó
gyökeréből fut, ezért helyes; de a temp-fixture-ös cellák CSAK azért működnek,
mert a CWD közben a repó gyökere marad. Érdemes a docstringben kimondani (nem
blokkol).

### NOTE-2 — `_GA_READY_CLAIM` csak magyarul mér

`verify_ga_scope.py:82` — `\bga[\s-]*kész\b`. Egy angol „GA-ready" fejléc-állítást
nem fogna meg. Élő rés nincs, mert a NOT-READY marker **hiánya** önmagában
lelet (D7 első ága, P4-ben mérve), tehát a fejléc nem tud csendben GA-késszé
válni. Nem blokkol.

---

## Acceptance criteria — tételes állás (1. menet)

| # | Kritérium | Állás | Bizonyíték |
|---|---|---|---|
| A1 | minden capability pontosan egy besorolást kap, mért indoklással | ✅ | P2/P6 piros; 16/16 sor; a `note`-ok mért forrásai visszaellenőrizve (fenti tábla) |
| A2 | besorolás ↔ cohort-flag-profil konzisztens | ✅ | §6.1 valódi-sértés próba (implementer) + a Dart A2 cella + tool-független sanity |
| A3 | preview capability nélkül a core flow végigjárható | ❌ **MAJOR-1** | P1 piros, de **P7 ZÖLD** — az őr megkerülhető |
| A4 | minden befagyasztott contracthoz feloldási feltétel | ✅ | P5/P8 piros |
| A5 | nyitott P0/P1 mellett explicit „nem kész" | ✅ | P4 piros, két ágon |
| A6 | a Kör 27 `beta_profile_test.dart` változatlanul zöld | ✅ | saját gate-futás, a fájl a diffben nincs |
| — | D8 (nincs kitalált béta-adat) | ✅ | P3 piros; a `beta-findings.md` a mért NOT-launched állapotot rögzíti |

## Architektúra / termékhatárok

`lib/**`, `backend/**`, `.github/**`, `docs/eval/**`, `docs/adr/**`, `tools/**`
érintetlen (scope-audit). Új futásidejű függőség nincs; a `verify_ga_scope.py`
stdlib + `yaml` (a testvér `verify_beta_profile.py` precedense). Az `architecture`
és `secrets` gate zöld.

## Merge-feltétel

A két MAJOR zárásáig **merge TILOS**. A javító kör ugyanezzel a motorral megy,
ezzel a leletlistával.

---

# 2. menet — javító kör (commit `25cad21f`) — VERDIKT: **APPROVED**

Reviewer: Claude (orchesztrátor), 2026-09-02. Friss, izolált klón:
`/tmp/review-e12-r28b` (a GitHub-remote-ról, `25cad21f`). Read-only; production
kód a review alatt nem íródott.

## Leletenkénti zárás — ÚJRAMÉRVE

### MAJOR-1 — ZÁRVA

A `_parse_table` már nem dob el sort némán: a marker-blokk minden nem-fejléc,
nem-elválasztó sora **kötelező adatsor**, és ha nem illeszkedik a tábla
alakjára, `VerifyError` a sor számával. A P7 mutáció (a lelet reprodukciója)
a javítás UTÁN:

```
verify_ga_scope: docs/release/ga-scope.md:92: table row does not match the expected shape — '|`LabMode` overlay is required to finish onboarding | `labModeAvailable` | `test/e2e/returning_user_restart_test.dart` |'
exit=2
```

(Javítás ELŐTT ugyanez `exit=0`, „3 core-path step(s)" — a lelet mérése.) A
javítás mindhárom táblára kiterjed, nem csak a core-path-ra. A modul-docstring
állítása immár a kódot írja le, és nevesíti a mérést (`E12-R28 MAJOR-1`) —
a nem bizonyított doc-comment-állítás megszűnt.

### MAJOR-2 — ZÁRVA

A capability-tábla új, géppel kötött `production_default` oszlopot kapott, és a
tool a **mért forrásból** olvassa vissza (`lib/app/config/feature_flags.dart`
`FeatureFlags.forEnvironment`, fail-closed parse). Három mérés:

| Próba | Mutáció | Mért |
|---|---|---|
| P9 | a dokumentum `production_default`-ja `true`-ra írva | **exit 1** — `production_default is documented as True but the measured FeatureFlags.forEnvironment default … is False` |
| P10 | `ga` + `production_default false`, a nevesített feloldó feltétel kivéve | **exit 1** — `classified ga with production_default false but its note names no 'Production unlock:' condition` |
| P11 | a mért forrásban ismeretlen alak (`someWeirdHelper(environment)`) | **exit 2** — `an unrecognized shape for a fail-closed production-default read` |

A `ga-scope.md:64` sor immár KIMONDJA a mért tényt („Measured production default
is `false` (`lib/app/config/feature_flags.dart:78` … no dart-define override) —
the `/practice*` routes are NOT reachable in a production build today"), és
nevesített feloldó feltételt hordoz. A besorolás — helyesen — `ga` maradt: a
lelet nem a besorolás volt, hanem a kimondatlan, őrizetlen production-tény.

### Regresszió-próbák a javítás UTÁN (a korábbi őrök nem lazultak)

| # | Mutáció | Mért |
|---|---|---|
| P3 | evidence egy nem létező béta-riportra (D3 anti-fabrikáció) | **exit 1** |
| P4 | NOT-READY fejléc → `GA-kész`, nyitott P0 mellett (D7) | **exit 1**, két ágon |
| — | tiszta fa | **exit 0** — 16 capability, 4 core-path step, 4 frozen contract, 6 open P0/P1 |

### MINOR-1 — NYITVA HAGYVA (follow-up, nem blokkol)

A `postponed` besorolás cohort-flag állapotát továbbra sem köti cella. Ez a
javító-prompt szerint kifejezetten **opcionális** volt (élő rés nincs: mind a
hét `postponed` flag `false` mindkét cohortban; az ADR 0489 D4 sem követeli
meg). Follow-up körre marad, nem merge-akadály.

NOTE-1 / NOTE-2 változatlanul nem blokkol.

## Gate — SAJÁT kézzel, a friss klónban

```
tools/round-gate.sh test/tooling/ga_scope_test.dart test/tooling/beta_profile_test.dart
    format / analyze / test ga_scope_test.dart / test beta_profile_test.dart
    / architecture / secrets / l10n                            mind ZÖLD
GATE_EXIT=0
```

## Scope-audit — a hiteles eszközzel, a teljes körre

```
Legacy scope audit OK (e3d4a1a54bda..25cad21ff8c4, 7 changed path(s), 1 generated/ignored)
```

A 7. útvonal a saját review-jelentésem (`generated/ignored` — állandó,
kód szintű mentesség, ADR 0138). A `docs/beta/**` és a `lib/**` érintetlen.

## Acceptance criteria — záró állás

| # | Állás | Bizonyíték |
|---|---|---|
| A1 | ✅ | P2/P6 piros; 16/16 sor; a `note`-ok mért forrásai visszaellenőrizve |
| A2 | ✅ | §6.1 valódi-sértés próba + Dart A2 cella + tool-független sanity |
| A3 | ✅ **(javítva)** | P1 piros ÉS **P7 immár exit 2** — az őr nem kerülhető meg |
| A4 | ✅ | P5/P8 piros |
| A5 | ✅ | P4 piros, két ágon |
| A6 | ✅ | `beta_profile_test.dart` változatlan, saját gate-futáson zöld |
| — | D8 (nincs kitalált béta-adat) | ✅ P3 piros; `beta-findings.md` a mért NOT-launched állapotot rögzíti |
| — | D3+production-tény (MAJOR-2) | ✅ P9/P10/P11 |

**VÉGSŐ DÖNTÉS: APPROVED.** 0 nyitott BLOCKER/MAJOR. A merge a zöld
exact-SHA CI-kapun (Full Gate + Router CI a merge SHA-ján) múlik.
