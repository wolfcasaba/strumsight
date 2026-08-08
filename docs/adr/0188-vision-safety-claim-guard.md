# ADR 0188 — Vision safety claim guard

- **Státusz:** Elfogadva (E05-R20 pre-flight, 2026-08-08)
- **Kör:** E05-R20 — Posture metric engine és safety policy
- **Implementer motor:** MiniMax M3 (`claude`-harness, `~/.claude-minimax`,
  `tools/mm-round.sh`) — az ADR-t az orchesztrátor (Claude) írta a
  pre-flightban (ADR 0055, pipeline-prompt §2).
- **Epic:** [Chapter 6 — Epic 5: Computer Vision](../sdd/06-epic-05-computer-vision.md) Kör 20; §21
- **Kontext-ADR-ek:** [0179](0179-vision-capability-aware-feedback.md)
  (vision capability-aware feedback — a metrika-fél gyökér-elve),
  [0177](0177-ai-tutor-safety-injection-usage-evaluation-gate.md) (AI Tutor
  safety-kategória + fail-closed claim-provenance — a legrelevánsabb sibling
  precedens), [0132](0132-ai-tutor-privacy-and-consent.md),
  [0141](0141-ai-tutor-prompt-output-schema-injection-boundary.md)

## Kontextus

Az E05-R14 (`PostureBaseline`/`PostureObservation`,
`lib/features/vision/domain/landmarks/posture_baseline.dart`) és az E05-R18/R19
metric-engine mintázat (`MetricDefinition`/`MetricObservation`,
`lib/features/vision/domain/metrics/`) megadja a **mérési** oldalt:
baseline-relatív, capability/confidence-gated proxy metrikák, `notObservable`
szemantika ([ADR 0179](0179-vision-capability-aware-feedback.md)). Az Epic 5
hat alapozó ADR-je (0178–0183: privacy-by-default, capability-aware-feedback,
android-first-camera-strategy, manual-calibration-fallback,
audio-priority-degradation, no-raw-frame-persistence) egyike sem szabályozza,
hogy a vision réteg **milyen tartalmú állítást tehet a felhasználó testéről** —
mindegyik capability/privacy/platform kérdés, nem tartalom-policy.

A testtartás/ergonómiai insight kockázata más jellegű: egy naiv „ez a
testtartás hosszú távon fájdalmat okozhat" jellegű megfogalmazás
egészségügyi/diagnosztikai állítássá csúszhat át észrevétlenül (kör-brief §9 —
a kör legfőbb kockázataként megnevezve). A sibling AI Tutor epic már megoldotta
a szerkezetileg analóg problémát a generatív szöveg rétegén:
[ADR 0177](0177-ai-tutor-safety-injection-usage-evaluation-gate.md) (elfogadva
**2026-08-06** — egy nappal a jelen kör-brief batch-írása, **2026-08-05**,
UTÁN) determinisztikus safety-kategória taxonómiát (`TutorSafetyCategory`)
vezet be — mérve (`lib/features/ai_tutor/domain/services/tutor_safety_policy.dart`):
kötelező hard-block kategóriák között `painResponse` és `medicalRefusal` —, és
egy fail-closed claim-provenance validátort
(`TutorClaimValidator.groundedClaimTypes` — mérve
`lib/features/ai_tutor/domain/services/tutor_claim_validator.dart:78-93`:
ismeretlen claim-típus → `unsupportedClaim`, bizonyíték nélküli
measured/computed/knowledge-claim → hard block `unsupportedClaimEvidence`).
A kör-brief saját, batch-írási idejű pre-flight jegyzete („AI Tutor safety
policy… ADR 0132/0141") ezért **stale** a legrelevánsabb sibling-ADR
tekintetében — ADR 0177 az időzítés miatt nem szerepelhetett benne; ez az ADR
pótolja a hivatkozást.

A vision réteg ugyanakkor **nem** a tutor generatív-szöveg rétege: itt nincs
LLM-kimenet, amit validálni kellene — a metric engine egy **zárt, véges
claim-kód katalógusból** (pl. `postureShoulderAsymmetryIncreasedVsBaseline`)
emittál, sosem szabad szöveget (kör-brief §5 pont 3: „a kimenet claim-kód, nem
mondat"). A guard tehát korábban fut le (a katalógus összeállításakor,
fordítás-közeli időben ellenőrizhető), mint a tutor validátor (futásidőben,
szabad szövegen mintaillesztéssel).

## Döntés

1. **A vision safety claim-guard kód-katalógust validál, nem szabad
   szöveget.** `VisionSafetyPolicy` egy fail-closed allowlistet tart karban:
   minden posture claim-kódnak deklarálnia kell egy engedélyezett osztályát; a
   `SafetyClaimGuard` **mindkét irányban** őriz — ellenőrzi, hogy a katalógus
   minden kódja engedélyezett osztályba esik-e, ÉS elutasít minden, a
   katalógusban nem szereplő/nem deklarált kódot (kör-brief §5 pont 6).
2. **Tiltott osztályok kód-szinten zártak, nem prózai tiltólistával.**
   Diagnózis, sérülés-jóslat, fájdalom-magyarázat, gyógyulási tanács, „ez
   ártalmas" minősítés — egyik sem elfogadható enyhébb megfogalmazásban sem
   (kör-brief §5 pont 1). A guard a kód **osztályát** nézi, nem a hozzá
   tartozó (ebben a körben még nem létező, R23-as) megjelenítési szöveget.
3. **Fájdalom-bejelentést a vision réteg nem értelmez, csak jelez.** A
   user-kezdeményezett fájdalom-jelzés kezelése a **meglévő**
   [ADR 0177](0177-ai-tutor-safety-injection-usage-evaluation-gate.md)
   `painResponse` kategóriájának dolga (tutor-oldali hard-block, már
   elfogadva és implementálva); a vision réteg csak egy jelzést ad tovább,
   hogy a coaching-cue-kat el kell hallgattatni (a tényleges bekötés R27),
   nem duplikálja és nem verseng a tutor safety policyjével (kör-brief §5
   pont 4).
4. **Abszolút ítélet csak baseline mellett.** Baseline nélkül (R14 kapuja)
   minden posture metrika `notObservable`
   ([ADR 0179](0179-vision-capability-aware-feedback.md) megerősítése ebben a
   doménben) — populációs átlagra alapozott „helyes tartás" ítélet sosem
   elfogadható, baseline mellett sem (kör-brief §5 pont 2).

**NEM elfogadható:** a tutor `TutorSafetyPolicy`/`TutorClaimValidator`
importja vagy forkolása a vision rétegbe (cross-feature import, ADR
0131-stílusú boundary-sértés) — a két guard szándékosan **külön**
mechanizmus, ugyanazzal a fail-closed filozófiával, más rétegen (zárt
kód-katalógus, szemben a szabad szövegen futó mintaillesztéssel).

## Következmények

- `lib/features/vision/domain/safety/vision_safety_policy.dart` +
  `safety_claim_guard.dart` — új, vision-lokális modul; nem importál
  `lib/features/ai_tutor/`-t, és a `ai_tutor` sem importálja ezt (a réteg
  határa mindkét irányban zárt).
- A posture metric-katalógus (`posture_metrics.dart`) minden kódja
  kötelezően áthalad a guardon egy dedikált teszten (kör-brief §6
  „Claim-guard teszt" + „Valódi-sértés próba": egy tiltott osztályba eső kód
  ideiglenes felvétele → PIROS → visszaállítás).
- A jövőbeli R23 (feedback policy) és R27 (AI Tutor integráció) erre a
  katalógusra épít; a katalógus bővítése (új claim-kód) mindig új, a guard
  által ellenőrzött bejegyzést igényel, sosem a guard lazítását.
- A tutor-oldali ADR 0177 és a vision-oldali ADR 0188 két **független**, de
  filozófiailag összehangolt fail-closed mechanizmus; egy jövőbeli
  egységesítés (közös safety-kernel) külön ADR döntése volna, nem ennek a
  körnek a hatásköre.

## Elutasított alternatívák

- **A tutor `TutorSafetyPolicy` közvetlen újrahasználata/importja.** Elvetve:
  cross-feature import volna, és a tutor policy szabad **szövegen**
  mintaillesztő regexeket futtat — a vision réteg zárt kód-katalógusára ez
  szerkezetileg nem illik (nincs „szöveg", amin mintát keresni).
- **Csak dokumentált konvenció, gépi guard nélkül.** Elvetve: a kör-brief §9
  kimondja — a „segítő" megfogalmazás észrevétlenül egészségügyi állítássá
  csúszhat, ez a kör legfőbb kockázata; a mért mintázat szerint (M3-nál a
  szöveges tiltás bizonyítottan nem tart, `docs/LESSONS.md`) csak a
  fail-closed allowlist gépi kényszere zár ki ilyen csúszást.
- **Az ADR 0179 bővítése, önálló ADR helyett.** Elvetve: ADR 0179
  kifejezetten capability/confidence/observability kérdés, nem
  tartalom-policy; a hat alapozó vision-ADR egyike sem fedi le a „milyen
  claim-osztály engedélyezett" döntést, és a sibling epic ugyanerre a
  döntés-osztályra saját, dedikált ADR-t kapott (0177) — ez az ADR ugyanazt a
  precedenst követi (konzisztencia elve, ld. `docs/LESSONS.md` mintázat a
  0162/0164→0179/0181 ismételt korrekciókról).
