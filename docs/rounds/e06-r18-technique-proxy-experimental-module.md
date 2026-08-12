# E06-R18 — Technique proxy kísérleti modul

- **Státusz:** PLANNING (pre-flight revízió: 2026-08-12, main @ `b9859f06`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 18; §18.1–18.5, §4.3
- **Branch:** `codex/e06-r18-technique-proxy-experimental-module`
- **Előfeltétel:** **E06-R11, E06-R16, E06-R17 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/engine/metrics/technique_proxies.dart",
  "lib/features/audio_analysis/engine/metrics/transition_analysis.dart",
  "lib/features/audio_analysis/domain/analysis_metric_catalog.dart",
  "lib/features/audio_analysis/public.dart",
  "lib/app/config/feature_flags.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/audio_analysis/domain/technique_metric_catalog_test.dart",
  "test/features/audio_analysis/engine/technique_proxies_test.dart",
  "test/features/audio_analysis/engine/transition_analysis_test.dart",
  "test/tooling/analysis_claim_safety_test.dart",
  "docs/adr/0236-analysis-technique-proxy-safety-and-naming.md",
  "docs/manual-testing/analysis-eval-matrix.md",
  "docs/rounds/e06-r18-technique-proxy-experimental-module.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/tooling",
  "test/app",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R11/R16/R17 merge.
> **ADR 0236** a pre-flight foglalója által kiosztva. Olvasd újra az R11 §5.1 OD-01 következményét:
> ha a chord-evidence `derived` (nincs top-k, nincs no-chord valószínűség),
> akkor a „confidence collapse duration" proxy **nem számolható** — ilyenkor
> az adott proxy `unavailable` `modelUnavailable` okkal, és ezt a §0.0-ban
> rögzíteni kell. Ellenőrizd a `docs/manual-testing/analysis-eval-matrix.md`
> mai formátumát (az R01 hozta létre). PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PLANNING — pre-flight revízió (2026-08-12, `b9859f06`).** Az
`tools/round-slots.py reserve-adr --round E06-R18` foglaló a már elfoglalt
előreírt 0208 helyett **0236**-ot adott ki; ez a kör ADR-je. A mért
`ChordFrameEvidence.derived` top-k és no-chord valószínűség nélkül marad, ezért
a confidence-collapse proxy minden ilyen inputon `unavailable/modelUnavailable`.

**Dokumentumhatár.** A jelenlegi `AnalysisDocument`-nek nincs diagnosztikai
ága, és a document/codec/pipeline fájlok nem részei e körnek. Ezért a "Lab
diagnosztikai ág" ebben a körben egy önálló, immutable
`TechniqueProxyReport` visszatérési érték: csak a hívó explicit `Lab mode` és
`analysisTechniqueProxiesEnabled` bemenetén számolható, nem kerül
`AnalysisDocument.metrics`-be és nem tárolódik. R23/R24 kötheti majd a Lab
panelhez; e kör nem változtat V1/V2 pipeline- vagy perzisztencia-viselkedést.

## 1. Cél

Váltási folyamatosság, extra onset és hang-stabilitás **auditálható proxyk**
bevezetése **kizárólag Lab módban**, olyan elnevezéssel és
állítás-korláttal, ami nem ígér kéz-/ujjdiagnózist.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- **Nincs technikai proxy** sehol. A Lab-panel ma az ML–DSP akkord-egyezést
  mutatja (`MlChordDiagnostics.agreement`), semmi mást.
- Az SDD §4.3 hét **kifejezetten tiltott állítást** sorol fel („rossz ujjat
  használtál", „a harmadik húr zörgött", „a csuklód helytelenül állt", …) —
  ezek hangból nem bizonyíthatók.
- Az R11 adja a chord-szegmenseket és a `derived` evidence-t, az R16 a
  dinamikai eventértékeket, az R17 a pitch-szegmenseket, az R10 az onseteket.
- A Lab elérhetőségét a `labModeAvailable` flag + a `labModeProvider`
  felhasználói kapcsoló adja (`lib/features/settings/public.dart`).

## 3. Scope

**Benne:** öt dokumentált proxy — chord change gap; confidence collapse
duration (ha az evidence engedi); extra onset a váltás körül; sustained note
dropout; attack instability. Mindegyik: **külön metric ID + verzió**,
`experimental` jelölés, confidence-kapu, óvatos ARB-név;
`TechniqueProxySafety` őr (gépi állítás-ellenőrzés); **ADR 0236**;
**egy** új flag: `analysisTechniqueProxiesEnabled` (default OFF);
eval-terv sorok az eval-mátrixban.

**Kívül — TILOS:** a proxyk megjelenítése a normál (nem Lab) UX-ben,
kamerás/vision evidence bevonása, bármely „technique score" összesítés,
DSP-konstans, UI-widget (a Lab-panel bekötése az R23/R24 dolga).

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../engine/metrics/technique_proxies.dart` | ÚJ | az öt proxy |
| `.../engine/metrics/transition_analysis.dart` | ÚJ | váltás-környéki elemzés |
| `.../domain/analysis_metric_catalog.dart` | meglévő | **additív** ID-k |
| `.../public.dart` | meglévő | export |
| `lib/app/config/feature_flags.dart` | meglévő | **additív** 1 flag, OFF |
| `lib/l10n/*.arb` | meglévő | **additív**, óvatos nevek |
| `test/tooling/analysis_claim_safety_test.dart` | ÚJ | gépi állítás-őr |
| `docs/adr/0236-…md` | ÚJ | elnevezési/állítási határ |
| `docs/manual-testing/analysis-eval-matrix.md` | meglévő | eval-terv sorok |

**Tilos zóna:** `lib/features/vision/**`, `lib/features/analyze/**`,
`lib/features/audio_analysis/presentation/**`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **ADR 0236 — a proxy neve azt mondja, amit MÉR.** Engedett alakok:
   „Hangindítás tisztasága", „Váltás folyamatossága", „Kitartás stabilitása",
   „Nem várt extra hangindítások" (SDD §18.3). **NEM elfogadható:**
   „Technique score", „Cleanliness", „Skill", vagy bármely testrészre,
   kéztartásra, ujjazatra utaló név/üzenet.
2. **A hét tiltott állítás gépi őrt kap:** a `analysis_claim_safety_test.dart`
   végigmegy **minden** analysis-eredetű ARB-kulcson és metrikanéven, és
   elutasít minden olyan szöveget, ami illeszkedik a tiltott mintákra
   (`ujj|finger|csukló|wrist|húr zörg|buzz|pengető szög|pick angle|
   nyak görbe|neck bow|helytelen(ül)? (tart|fog)`). **NEM elfogadható:** a
   minta gyengítése — bővítése igen.
3. **Experimental = Lab-only:** flag OFF (a default) esetén a proxyk
   **ki sem számolódnak**; flag ON **és** Lab mód esetén a
   dokumentum diagnosztikai ágába kerülnek, a publikus `metrics` listába
   **nem**. **NEM elfogadható:** a proxy a normál overview-n.
4. **Confidence-kapu:** target ismert **és** input nem clipped **és** a
   backing track nem domináns **és** elegendő ismétlés — mind a négy feltétel
   szükséges (SDD §18.4). **NEM elfogadható:** részleges kapu.
5. **Nincs egészségügyi állítás** (SDD §18.5): sem az ARB, sem a doc-comment
   nem utalhat sérülésre, fájdalomra, ergonómiára.
6. **Minden proxyhoz eval-terv:** az eval-mátrix kap egy PENDING sort a
   proxy → valós technikai jelenség kapcsolatának igazolására; az ADR
   kimondja, hogy **eval nélkül a proxy soha nem lép ki a Labből**.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Mi történik, ha a chord-evidence `derived` (nincs top-k)?
    blocking: true
    resolution_policy: use_default
    default: >-
      a "confidence collapse duration" proxy `unavailable`
      (`modelUnavailable`), a másik négy proxy fut. NEM elfogadható a
      szegmens-confidence-ből "collapse" kitalálása.
  - id: OD-02
    question: Mekkora a váltás körüli ablak?
    blocking: true
    resolution_policy: use_default
    default: >-
      a chord-váltás időpontja körül [−150 ms, +250 ms] — aszimmetrikus,
      mert a váltás UTÁNI zörej a jellemző; néven nevezett konstansok.
  - id: OD-03
    question: Mennyi az "elegendő ismétlés"?
    blocking: false
    resolution_policy: use_default
    default: "ugyanannak a váltás-párnak legalább 4 előfordulása a klipben."
```

## 6. Acceptance criteria

- [ ] **Proxy-fixture mátrix — hat cella:** tiszta váltás; csend-rés a
      váltásnál; extra attack a váltás után; ring-out átfedés; gyenge minőségű
      (clippelt) bemenet; ismétlés a minimum alatt. Mindegyikre a **teljes**
      proxy-halmaz státusza és értéke.
- [ ] **Lab-kapu mátrix — négy cella:** (flag OFF, Lab OFF), (flag OFF,
      Lab ON), (flag ON, Lab OFF), (flag ON, Lab ON) — **kizárólag** az utolsó
      cellában keletkezik proxy, és az első háromban a **számító hívásszáma 0**.
- [ ] **Publikus lista tisztasága:** flag ON + Lab ON esetén a
      `TechniqueProxyReport` külön diagnosztikai érték, és az e körben
      változatlan `AnalysisDocument.metrics` **egyetlen** `technique.*` ID-t
      sem tartalmaz. A teszt méri a reportot és a dokumentumlistát; nincs
      document/codec/pipeline-wiring.
- [ ] **Confidence-kapu mátrix:** a négy feltétel mindegyikét külön-külön
      megbuktatva (target hiány / clipping / backing dominancia / kevés
      ismétlés) a proxy `unavailable` a **megfelelő** okkal — négy cella,
      **külön** ok-értékekkel.
- [ ] **Ismétlés-küszöb hármas** (4 előfordulás): **3 / 4 / 5** előfordulás —
      a **4** átmegy (inkluzív), a 3 `insufficientEvents`.
- [ ] **Váltás-ablak küszöb hármas** (+250 ms): egy extra onset a váltás után
      **249 ms**, **250 ms**, **251 ms** — a **250 ms** még **beleszámít**
      (inkluzív), a 251 ms nem. Ugyanez a −150 ms oldalon:
      **−149 / −150 / −151 ms**, a **−150** beleszámít.
- [ ] **Állítás-őr valódi-sértés próbája (§10):** ideiglenesen felveszünk egy
      `analysisTechniqueFingerPlacement` ARB-kulcsot „rossz ujjat használtál"
      szöveggel → a `analysis_claim_safety_test.dart` **PIROS** →
      visszaállítás. A próba a §10-ben dokumentálva.
- [ ] **ADR 0236** kimondja: az engedett névalakokat, a tiltott mintákat, a
      Lab-only szabályt, és hogy **eval nélkül nincs kilépés a Labből**.
- [ ] **Eval-mátrix:** mind az öt proxyhoz **egy-egy** PENDING sor, felelőssel
      és a mérendő számmal.
- [ ] **Flag-őr:** az új flag minden környezetben `false`.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A proxy a publikus `metrics` listába kerül | a „publikus lista tisztasága" cella |
| A flag OFF mellett is számol | a Lab-kapu mátrix első három cellája (hívásszám 0) |
| Csak a Lab kapcsolót nézi, a flaget nem (vagy fordítva) | a (flag OFF, Lab ON) és (flag ON, Lab OFF) cella |
| A confidence-kapu részleges | a négy külön ok-cella közül a kihagyott |
| Az ismétlés-küszöb exkluzív | a **pontosan 4 előfordulás** cella |
| A váltás-ablak szimmetrikus | a −150/+250 ms aszimmetria cellái |
| Az ablakhatár exkluzív | a **pontosan 250 ms** beleszámít-cella |
| A `derived` evidence-ből „collapse"-t talál ki | a `modelUnavailable` cella |
| Testrészre utaló ARB-név | az állítás-őr (`analysis_claim_safety_test.dart`) |
| **Valódi-sértés próba (§10):** a tiltott-minta lista ideiglenes kiürítése → a hamis kulccsal futtatott őr **NEM** fog pirosat adni → az őr maga bizonyítottan hatástalan; ezért a próba a KULCS felvételével történik (lásd fent), nem a minta törlésével |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/tooling test/app
```

Külön processzek, nincs `&&`/pipe/`tail`.

## 8. Implementációs sorrend

1. ADR 0236 (nevek, tiltott minták, Lab-only, eval-feltétel).
2. `test/tooling/analysis_claim_safety_test.dart` (az őr **előbb**).
3. RED: Lab-kapu, confidence-kapu, küszöb- és ablak-mátrix.
4. `transition_analysis.dart` (váltás-környéki ablak).
5. `technique_proxies.dart` (öt proxy, hívásszámlálóval tesztelhető seam).
6. Katalógus + ARB + flag; eval-mátrix sorok; gate.

## 9. Kockázatok

- **A proxyk „hasznosnak tűnnek", és nyomás lesz kivinni őket a Labből** —
  az ADR 0236 ezt eval-hoz köti, és az őr a nevekre gépi kaput ad.
- **Az `derived` evidence korlátja** (OD-01) miatt az öt proxyból négy lesz
  ténylegesen mérhető — a §10 rögzítse, melyik.
- **A tiltott-minta regex hamis pozitívja** (pl. „fingerpicking" mint
  gyakorlatnév) — a mintát úgy kell írni, hogy a **metrikanevekre és az
  analysis-eredetű kulcsokra** vonatkozzon, és a §10 rögzítse a hatókört.

**STOP:** a proxy normál UX-be emelése, „technique score" bevezetése vagy a
tiltott-minta gyengítése helyett `stopped` + brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

**Implementáció: Claude Sonnet 5 (sonnet-impl), 2026-08-12.**

### 10.1 Új fájlok

- `lib/features/audio_analysis/engine/metrics/transition_analysis.dart` —
  `ChordTransition`, `TransitionWindow` (`[-150ms, +250ms]` inkluzív mindkét
  határon), `buildChordTransitions`, `countTransitionRepetitions`,
  `maxTransitionRepetition`, `onsetsInWindow`.
- `lib/features/audio_analysis/engine/metrics/technique_proxies.dart` —
  `TechniqueProxyGate` (4 feltétel, egyik hiánya is teljes blokkolás),
  `TechniqueProxyReport` (`disabled`/`unavailable`/`available` factory),
  `TechniqueProxyCalculator` hívásszámlálható seam, `buildTechniqueProxyReport`
  belépési pont, `computeTechniqueProxyMetrics` + öt privát proxy-számító.
- `test/features/audio_analysis/domain/technique_metric_catalog_test.dart`,
  `test/features/audio_analysis/engine/transition_analysis_test.dart`,
  `test/features/audio_analysis/engine/technique_proxies_test.dart`,
  `test/tooling/analysis_claim_safety_test.dart`.

### 10.2 Módosított fájlok (additív)

- `lib/app/config/feature_flags.dart` — `analysisTechniqueProxiesEnabled`
  mező (default `false`, `forEnvironment` mindig `false`, equality/hash/
  toString frissítve).
- `lib/features/audio_analysis/domain/analysis_metric_catalog.dart` — öt
  `technique.*.v1` ID a `known` halmazban + `TechniqueProxyMetricIds`.
- `lib/features/audio_analysis/public.dart` — a két új engine-fájl exportja.
- `lib/l10n/app_en.arb` / `app_hu.arb` — hat `analysisTechnique*` kulcs
  (öt proxy-név + egy disclaimer), óvatos, testrészre nem utaló szöveggel.
- `docs/manual-testing/analysis-eval-matrix.md` — EVAL-22..26 PENDING sorok.

### 10.3 OD-01 hatása (mért)

A `derived` chord-evidence (nincs top-k, nincs no-chord valószínűség) miatt
a `confidence_collapse_duration` proxy `unavailable`/`modelUnavailable`,
amikor a bemenetben nincs `ChordFrameEvidence.complete` bejegyzés a
váltás-ablakban vagy egyáltalán nincs `complete` evidence — ezt a
`technique_proxies_test.dart` „OD-01" csoportja két külön esetre (csak
`derived` evidence; nincs evidence) bizonyítja. A másik négy proxy ilyenkor
is lefut. Ez a mérés megerősíti a pre-flight §0.0 döntését: a battle jelenlegi
adatforrásokból (R11 chord evidence) csak négy proxy futtatható megbízhatóan
minden bemeneten, az ötödik feltételesen.

### 10.4 Állítás-őr valódi-sértés próbája

`test/tooling/analysis_claim_safety_test.dart` első futtatása ZÖLD volt.
Ezután ideiglenesen felvettem `lib/l10n/app_en.arb`-be egy
`"analysisTechniqueFingerPlacement": "You used the wrong finger"` kulcsot,
újrafuttattam a tesztet — **PIROS** lett (`analysis claim safety (ADR 0236)
no analysis-origin ARB key or metric ID matches a forbidden claim pattern`
hibázott a `finger` mintán) —, majd eltávolítottam a kulcsot és a teszt ismét
ZÖLD lett. A minta hatóköre: `analysisArbKeyPrefixes` listája (`analysis`,
`pitchMetric`, `pitchFeedback`, `timingMetric`, `timingFeedback`,
`rhythmMetric`, `rhythmFeedback`, `dynamicsMetric`, `dynamicsFeedback`,
`harmonyMetric`, `technique`) — a `fingerpicking`-szerű álnegatívok elkerülése
végett a minta csak ezekre az analysis-eredetű ARB-kulcs-prefixekre és a
`AnalysisMetricId.known` ID-halmazra vonatkozik, nem minden ARB-kulcsra.

### 10.4.1 F1 javítás (review: MAJOR, 2026-08-12)

A review mért reprodukciója megmutatta, hogy az őr csak `entry.value`-ra
hívta a mintát — egy `analysisTechniqueFingerPlacement` kulcs semleges
értékkel átcsúszott. Javítás:

- `test/tooling/analysis_claim_safety_test.dart` — új `violatesClaimSafety(key, value)`
  segédfüggvény, amely a mintát **mind a kulcsra, mind az értékre** futtatja;
  a fő teszt ciklusa erre lett átállítva (korábban csak `entry.value`-t nézte).
- Új, dedikált regressziós teszt („a forbidden analysis-origin ARB key name is
  rejected even with a neutral value") egy **fake, csak in-memory** map-pel
  (`analysisTechniqueFingerPlacement` → semleges érték) — nem kerül be a
  valódi ARB fájlokba. Első futtatás a régi (csak érték) `violatesClaimSafety`
  mellett **PIROS** volt (`Expected: non-empty, Actual: []`); a kulcs-ellenőrzés
  hozzáadása után **ZÖLD**.
- A minta nem szűkült, csak a lefedettség bővült (kulcs + érték).
- `flutter test test/tooling/analysis_claim_safety_test.dart` a javítás után:
  4 teszt, mind ZÖLD.

### 10.5 Mérce-mátrix lefedettség

Mind a nyolc mérce-mátrix sor (§6.1) lefedve:
`Lab-gate mátrix` (4 cella, hívásszám-bizonyítással), `confidence-gate mátrix`
(4 cella, külön okokkal), `ismétlés-küszöb hármas` (3/4/5, 4 inkluzív),
`váltás-ablak küszöb hármas` (249/250/251ms és −149/−150/−151ms, mindkét
határ inkluzív), OD-01 (fentebb), állítás-őr valódi-sértés próba (fentebb),
és a hat cellás proxy-fixture mátrix (tiszta váltás; csend-rés; extra attack;
átfedő ablakok — "ring-out" robusztussági eset; clippelt bemenet;
ismétlés a minimum alatt).

### 10.6 Gate eredmény

```
tools/round-gate.sh test/features/audio_analysis test/tooling test/app
```

`format` (a négy új/módosított Dart-fájlon `dart format` lefuttatva a
gate PIROS jelzése után, majd a gate újrafuttatva) → ZÖLD; `analyze` → ZÖLD;
`test test/features/audio_analysis` → ZÖLD; `test test/tooling` → ZÖLD
(60 teszt); `test test/app` → ZÖLD (69 teszt); `architecture` → ZÖLD;
`secrets` → ZÖLD; `l10n` → ZÖLD. Minden gate zöld.

### 10.7 Scope

Nem nyúltam `AnalysisDocument`-hez, a codechez, a pipeline-hoz, a
presentation/UI-hoz vagy `docs/adr/0236-...md`-hez (a pre-flight már
elfogadott állapotban tartalmazta a szükséges döntéseket). Minden módosított/
új fájl a brief `allowed_paths` listáján belül van.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r18-technique-proxy-experimental-module-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
**Kötelező:** `security-reviewer` (risk = high, adat- és állítás-biztonság).
