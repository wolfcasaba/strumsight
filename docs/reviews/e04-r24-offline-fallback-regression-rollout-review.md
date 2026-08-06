# Review — E04-R24 Offline fallback, teljes regresszió és fokozatos rollout (EPIC-4 ZÁRÓ)

- **Kör:** E04-R24 · branch `codex/e04-r24-offline-fallback-regression-rollout`
- **Implementer:** DeepSeek v4 Pro (`deepseek/deepseek-v4-pro`, Kilo/codex-harness)
- **Reviewer:** Claude Opus 4.8 (orchestrátor, független, read-only)
- **Diff:** `e5f0696..ded21da`, 7 fájl, scope-audit **ok** (0 listán kívüli).
- **Pre-flight §0.0-R1:** `public.dart` scope-szűkítve (nincs érintve) — betartva.
- **Verdikt (1. pass):** **CHANGES REQUESTED** — 1 MAJOR, 1 MINOR.
- **Verdikt (2. pass, javító kör után `8d3d388`):** **APPROVED** — MAJOR-1 és MINOR-1 zárva (lásd §Re-review).

## Módszer

Read-only olvasás + falszifikáció. Mért: `local_tutor_fallback.dart`,
`local_tutor_fallback_test.dart`, `offline_network_guard_test.dart` diff,
`RemoteTutorModelGateway` transport-útja, `tutor_providers` gateway-wiring,
`DeterministicCoach`/`SessionDebriefBuilder` kimenet. Scope-audit artefaktum:
`scope_audit=ok`. Router CI zöld a merge-SHA-n (`ded21da`).

## Leletek

### MAJOR-1 — Az „offline ⇒ nincs tutor network request" cella NEM falszifikálható (acceptance §6 bullet 2)

**Hol:** `test/app/offline_network_guard_test.dart` új cellája
(`aiTutor enabled with cloud OFF: tutor home screen stays offline`).

**Mért gyökér:**
1. A cella csak a `tutorHome` route-ra navigál, amely egy **provider nélküli**
   `StatelessWidget` (`TutorHomeScreen extends StatelessWidget`, semmit nem olvas);
   **egyetlen tutor turn sem fut le**, tehát a `LocalTutorFallback`/gateway-út nincs
   gyakorolva.
2. Az újrahasznált `_expectNoNetwork` KIZÁRÓLAG az **account** Dio-factoryt
   (`accountDioFactoryProvider`) és a diagnostics-klienst figyeli. A tutor cloud-út
   (`RemoteTutorModelGateway`) egy **külön** `TutorStreamTransport` fölött streamel
   (ADR 0142), amit ez a probe **nem lát** — és amit a futó app cloud-OFF alatt nem is
   konstruál (`tutor_providers.dart` nem drótoz gatewayt).

**Következmény:** a brief §6 explicit acceptance-e szerint egy eldobható mutációnak
(„offline-ban cloud-hívás") **pirosra** kell váltania. A tutor-út bármely cloud-hívása
NEM váltaná pirosra ezt a cellát (a probe nem a tutor-transportot méri, és a cella nem
is indít turnt). Ez az Epic **fő biztonsági garanciája** (§36 „Cloud off állapotban
nincs tutor network request") — a záró körben dekoratív őr nem elfogadható.

**Javaslat (scope-on belül, csak a két teszt-fájl):** a
`local_tutor_fallback_test.dart`-ba (vagy a guard-tesztbe) írj **valódi falszifikáló**
cellát, amely a tutor-út gateway-választását próbálja: konstruálj `TutorOrchestrator`-t
egy **spy** `TutorModelGateway`/`TutorStreamTransport`-tal, és igazold, hogy cloud-OFF
/ consent-off / usage-limit inputnál a `LocalTutorFallback` fut, a spy gateway `start()`
/ a transport `openTurnStream()` **soha nem hívódik**, és egy mutáció (a spy megnyitása
offline) a cellát **pirosra** váltja. A `_expectNoNetwork` account-only garanciáját ne
lazítsd — bővítsd a tutor-transport szintjére.

### MINOR-1 — A no-input default debrief mért-eredményt szintetizál (§37 „nem talál ki mért eredményt")

**Hol:** `local_tutor_fallback.dart:155-169` (`_buildDebrief` + `_defaultDebriefInput`).

**Mért gyökér:** ha `debriefInput == null`, a fallback egy **hardkódolt** szintetikus
inputból (`stableTempoBpm: 80`, `pairedEventCount: minimumPairedEvidence`,
`sessionEvidenceRef: 'session.offline-fallback'`) épít debriefet, amit a
`SessionDebriefBuilder`/`DeterministicCoach` `stableTempo`/`measuredSession` insighttá
alakíthat — nemlétező sessionre mutató `evidenceRef`-fel. Ma **latens** (nincs élő
hívó, flag OFF), és a kimenet lokalizációs-kulcs alapú sablon (nem konkrét szám), ezért
nem BLOCKER; de a záró kör az Epic „soha ne találj ki mért eredményt" elvét mércévé
teszi.

**Javaslat:** `debriefInput == null` esetén `debriefOutput` legyen `null`, vagy egy
egyértelműen **generikus, nem-mért** „még nincs session-adat" insight — ne szintetizálj
`measuredSession`/`stableTempo` tényt. A `local_tutor_fallback_test.dart` „minimal
debrief" cellája eszerint módosuljon.

## NOTE-ok

- N1: a capability-resolver (`TutorCapability` online/offline/consent/limit) **őszinte**
  és gateway-mentes — a `resolve()` szinkron, nincs I/O; a 3 falszifikációs cella
  (consent-off, usage-limit, gateway-unavailable) jó irányban méri a capability-t.
  A MAJOR-1 nem ezt, hanem a **network-guard falszifikálhatóságát** érinti.
- N2: a completion-report/performance-baseline/rollout-runbook dokumentumok jelen
  vannak; a completion-report §36-lefedettségét a MAJOR-1 fix után újra kell nézni
  (a „cloud off ⇒ no tutor request" cella evidenciája erősödik).

## Re-review (javító kör után, `f529e87..8d3d388`, 2 fájl, scope-audit ok)

- **MAJOR-1 — ZÁRVA.** A `local_tutor_fallback_test.dart` új
  `TutorOrchestrator gateway selection` csoportja **valódi turn-úton**, spy
  `TutorModelGateway`-jel méri a cloud-elérést: consent-revoked → `startCalls == 0`
  (mutáció: gateway-hívás consent-revokednál → RED), usage-limit → `startCalls == 1`
  retry NÉLKÜL (mutáció: retry usage-limit után → RED). Ez erősebb bizonyíték a
  statikus képernyő-rendernél: a reducer consent-kapuját és a usage-limit „nincs
  repair" ágát falszifikálhatóan őrzi. A §36 „Cloud off ⇒ nincs tutor request"
  garancia mostantól mért, nem dekoratív.
- **MINOR-1 — ZÁRVA.** `_buildDebrief` `debriefInput == null` esetén `null`-t ad
  (a szintetikus `_defaultDebriefInput` törölve); a teszt „returns null debriefOutput
  when debriefInput is null" cellája ezt őrzi. Nincs többé fabrikált
  `measuredSession`/`stableTempo` tény nemlétező sessionre.

**Verdikt:** **APPROVED.** 12/12 fallback-teszt zöld, scope ok, nulla OPEN
BLOCKER/MAJOR. Merge exact-SHA zöld CI-n (Full Gate + Router CI a `8d3d388`/merge SHA-n).
