# ADR 0490 — A hotfix-út: a gyorsaság a SCOPE szűkítéséből jön, nem a kapuk elhagyásából

- **Státusz:** Elfogadva
- **Dátum:** 2026-09-02
- **Kör:** E12-R34 (Chapter 12 — Release Roadmap, Sprint Planning & Final Integration)
- **Kontextus-ADR-ek:**
  [0052](0052-ci-apk-automerge-session-per-round.md) (zöld kapu — a teljes mérce-lánc),
  [0062](0062-ci-gate-chain-and-fail-closed-release-signing.md) (CI gate-sor és
  fail-closed release signing),
  [0321](0321-gateguard-round-hold-not-chain-halt.md) (`PROTECTED_GLOBS` — a
  `.github/workflows/**` védett mérce-zóna),
  [0372](0372-gate-edit-policy.md) (a gate-szerkesztés álló felhatalmazásának fájlja),
  [0447](0447-release-manifest-provenance-and-sbom.md) (release manifest / SBOM;
  javaslat-fájl a védett workflow helyett; D5: `python3` az EGYETLEN külső bináris
  a gate-tesztben),
  [0448](0448-production-signing-policy-and-secret-hardening.md) (production signing
  policy; korlátozott YAML-részhalmaz parszer a javaslat-fájlra),
  [0481](0481-program-threat-model-and-release-security-scan.md) (release security scan),
  [0488](0488-release-candidate-assembly-and-approval-gate.md) (RC-összeállítás:
  jóváhagyás a build ELŐTT, javaslat-fájl mint kimenet — a hotfix-út ennek
  SZŰKÍTETT változata),
  [0489](0489-ga-scope-classification-and-contract-freeze.md) (GA scope és contract
  freeze — a hotfix a freeze utáni EGYETLEN engedett változtatási út),
  [0112](0112-self-healing-pipeline.md) (a merge UTÁNI orchesztrátor/emberi lépés)

## Kontextus

A GA (Kör 33) után a program első ízben szembesül azzal, hogy egy production-hibát
**órákon belül** kell javítani. A gyorsaság iránti nyomás pontosan az a pillanat,
amikor a kiadási védelem szokásosan kiürül: a „sürgős, ezért most kihagyjuk a
scant" ág egyetlen kapcsolóval semmissé teszi a Kör 6/7/18/25 négy környi
bizonyíték-építését.

A kör pre-flightja a fán ÚJRAMÉRTE a hotfix-út előfeltételeit:

1. **A `.github/workflows/**` MA is védett zóna.** A `PROTECTED_GLOBS`
   (`.claude/hooks/protect_factory_files.py:56-63`) tartalmazza a
   `.github/workflows` és `.github/workflows/*` mintát, az ADR 0372 álló
   felhatalmazásának fájlja (`.claude/gate-edit-policy`) pedig a fán **nem
   létezik** (mérve: `ls -la .claude/gate-edit-policy` → nincs ilyen fájl).
   Egy implementer-session tehát `H-GATEGUARD`-dal állna meg az első
   workflow-íráson.
2. **A Kör 25 RC-workflow-ja SINCS telepítve.** A fán a
   `.github/workflows/` tíz fájlja között `release-candidate.yml` **nem
   szerepel**; az RC a `docs/release/workflows/release-candidate.proposal.yml`
   javaslat-fájlban él. A hotfix-út tehát ugyanezt a javaslat-formát örökli, nem
   egy telepített workflow-t módosít.
3. **A jóváhagyás a Kör 25-ben a build ELŐTT áll.** A mért sorrend az RC
   javaslatban: `approve-release-candidate` (az EGYETLEN `environment:` kulcs) →
   `quality-gates` / `backend-tests` (`needs: approve-release-candidate`) →
   `build-release-candidate` (`needs: [quality-gates, backend-tests]`). A
   jóváhagyás tehát nem a gate UTÁN következik, hanem elöl áll, és minden
   építő/publikáló job tranzitívan `needs:`-eli.
4. **A közös mérce-lánc egyetlen composite actionben él**
   (`.github/actions/flutter-gates`) — a hotfix-javaslat ezt HÍVJA, nem másolja.
5. **A verzió-monotonitás ellenőrzése már létezik** a Kör 6
   `tool/release/verify_artifacts.py`-jában; a hotfix-út ezt HÍVJA, nem
   duplikálja a szabályt.

## Döntés

### D1 — A hotfix nem kerüli meg a security és signing kaput

A hotfix-javaslatban a release security scan és a production signing lépés
**feltétel nélküli**: nincs `if:`, nincs `continue-on-error`, és nincs olyan
`workflow_dispatch` input, amely kihagyná őket. A gyorsaság a SCOPE
szűkítéséből jön (kevesebb változás, szűkebb regresszió), nem a kapuk
elhagyásából.

**Elutasított alternatíva:** `skip_scan` / `emergency` input. Egy ilyen
kapcsoló a *leggyorsabb* úton teszi *legkönnyebbé* a védelem kikapcsolását —
pontosan fordítva, mint ahogy a kockázat kívánná.

### D2 — Incident-azonosító nélkül nincs hotfix

Az incident-azonosító **kötelező** `workflow_dispatch` input (`required: true`),
és a `tool/release/verify_hotfix.py` a hiányát **nem-nulla** kóddal jelzi. Az
azonosító köti a kiadást a postmortemhez: azonosító nélküli hotfix
utólag nem auditálható.

**Elutasított alternatíva:** opcionális mező „ha van, töltsd ki" felszólítással.
A mérés szerint (`docs/release/rollout-decision.md`, `ga-record.md` precedens) a
nem kényszerített mező üresen marad.

### D3 — A jóváhagyás a build ELŐTT áll, és tranzitívan kötelező

A hotfix-javaslatban PONTOSAN EGY job hordoz `environment:` kulcsot, és minden
olyan job, amely buildel, aláír, összeállít vagy feltölt, közvetlenül vagy
tranzitívan `needs:`-eli ezt a jóváhagyó jobot (ADR 0488 D3 mintája).

### D4 — Minden hotfixhez tartozik a hibát reprodukáló regressziós cella

A hotfix-runbook a javítás mellé **kötelezővé** teszi a hibát reprodukáló
tesztcellát: a javítás előtt PIROS, utána ZÖLD. **Elutasított alternatíva:** „a
manuális ellenőrzés elég" — az a hibát a következő kiadásban visszaengedi.

### D5 — A verzió-emelés kényszerített

A `verify_hotfix.py` nem-nulla kóddal lép ki, ha a hotfix verziója nem
szigorúan nagyobb az előzőnél. A szabály forrása a Kör 6 `verify_artifacts.py`
monotonitás-ellenőrzése; a hotfix-mérce ezt HÍVJA vagy azzal AZONOS
szemantikát mér, nem lazábbat.

### D6 — A kör terméke JAVASLAT, nem telepített workflow

A `.github/workflows/**` védettsége (kontextus 1.) miatt a kör kimenete a
`docs/release/workflows/hotfix.proposal.yml` — önmagában teljes, szintaktikailag
valid GitHub Actions dokumentum (nem fragmens). A telepítés és a dispatch
orchesztrátor/emberi lépés a merge UTÁN (ADR 0112 §3, ADR 0488 D1 precedens).

### D7 — A javaslat gépi mércéje saját, korlátozott YAML-parszerrel mér

A `test/tooling/hotfix_policy_test.dart` az ADR 0447 D5 / 0448 D6 / 0488 D6
precedenst követi: `python3` az EGYETLEN külső bináris, a `package:yaml`
**nincs importálva** (a fán csak tranzitív függőség, importja a
`depend_on_referenced_packages` linttel `flutter analyze`-t pirosra vinné). A
job/step-szintű parszer fail-OPEN: fel nem ismert sorra `FormatException`, nem
néma `continue` (L566).

### D8 — A post-launch riportok VÁZAT szállítanak, az adat emberi

A 7./14. napi riport kötelező mezőket definiál (crash, migráció, akku, audio,
support), de a kitöltés a GA utáni valóságból jön: user + support. A dokumentum
ezt KIMONDJA — a kitöltetlen váz nem stabilizáció (riport-illúzió).

## Következmények

- A hotfix-út auditálható és gyors, de a kapuk mérhetően a helyükön maradnak:
  a `verify_hotfix.py` statikus cellái pirosra váltanak, ha a scan vagy a
  signing lépés eltűnik vagy feltételessé válik.
- A hotfix-javaslat telepítése emberi lépés marad, amíg a `.claude/gate-edit-policy`
  álló felhatalmazás nem létezik a fán.
- A hotfix-kiadás a postmortemhez kötött: azonosító → postmortem-sablon →
  regressziós cella.
