# Epic 7 (AI Practice Generator) — batch előkészítési index

- **Státusz:** IN PREPARATION (megkezdve **2026-08-11**, kód olvasva:
  `main` @ `2334136a`; az Epic 6 ekkor indult — E06-R01/R02 futott)
- **SDD-forrás:** [`docs/sdd/08-epic-07-ai-practice-generator.md`](../sdd/08-epic-07-ai-practice-generator.md)
  (Chapter 8, Kör 1–30; 4514 sor)
- **Előfeltétel-epic:** **Epic 6 (Audio Analysis 2.0)** — az SDD
  [`00-index.md`](../sdd/00-index.md) 40–42. sorának gráfja szerint
  `Chapter 7 ──▶ Chapter 8`. Az Epic 6 a batch készítésekor **fut**
  (30 sor `pending`, E06-R01 lezárva).
- **User-döntés (2026-08-11):** „addig amíg ezek futnak készítsd elő az
  epic 7-et fejlesztéshez" → a queue-sorok **`hold`** státusszal kerülnek a
  sor végére; az indítás **emberi döntés** az Epic 6 lezárása után.
- **ADR-tartomány: `0221`–`0232`** (12 szám). Mérve 2026-08-11: a legnagyobb
  létező ADR **0220**, az Epic 6 a 0200–0211-et foglalja; a 0212–0214 a
  GOV-körök, a 0215–0220 az Epic 6 futó köreiből született.

> ⚠ **Ez az index nem futtatható artefaktum.** A körök briefjei az
> `e07-rNN-*.md` fájlok. Minden brief `PREPARED`; élesedéskor a kötelező
> pre-flight méri újra a driftet, és állítja `PLANNING`-re a kör-branchen.

---

## 0. A KULCS-MÉRÉS — mit lehet MA megírni és mit nem

A batch-előkészítés mért kockázata (ez a session tanulsága, `docs/LESSONS.md`
L203/L204): egy brief §2 „Jelenlegi állapot" szakasza **a megírás pillanatának
kódját** méri. Ha a kör hónapokkal később fut, a mérés avul, és az
`allowed_paths` nem létező fájlokra mutat.

Ezért megmértem, **melyik Epic 7 kör hivatkozik olyan rendszerre, ami MA nem
kész**. A `docs/sdd/08-epic-07-ai-practice-generator.md` körönkénti
szakaszaira, szóhatáros illesztéssel (a naiv `vision` minta a **re**vision
szóra is illeszkedik — ez a mérés első, hibás változata volt):

| Kör | Audio Analysis (Epic 6) | Vision | Tutor |
|---|---|---|---|
| **Kör 25** — Analyze és Computer Vision evidence integráció | 1 | 6 | 0 |
| **Kör 28** — Tutor és PlannerAssistGateway integráció | 0 | 0 | 4 |
| **Kör 30** — Evaluation harness, shadow rollout és Epic lezárás | 0 | 0 | 1 |
| **a többi 27 kör** | **0** | **0** | **0** |

**Következmény — a batch két részre bomlik:**

### A. MOST előkészíthető: 27 kör (Kör 1–24, 26, 27, 29)

Ezek a tervező **saját** domainjét, policy-jét, perzisztenciáját és UI-ját
építik, és kizárólag MÁR LEZÁRT epicek felületére támaszkodnak (Practice
Engine V2 — Epic 2, Song Trainer V2 — Epic 3, legacy Learn/Progress). Ezek
briefje ma megírható.

### B. KÉSŐBB, az előfeltétel lezárása UTÁN: 3 kör

| Kör | Mire vár | Miért nem írható meg ma |
|---|---|---|
| **Kör 25** | **Epic 6** lezárása + **vision modell-binárisok** | Az Epic 6 evidence/insight public API-ja MOST készül — a brief §2-je nem tudná megmérni. A vision ráadásul **BLOKKOLT**: a `model_manifest.json` mindkét bejegyzése `deferred`, a `.tflite` fájlok nincsenek a repóban (`HANDOFF.md` §3). |
| **Kör 28** | **GOV-05b** befejezése | Az AI Tutor drótozása kész (E99-R06) és az OpenAI-adapter is (E99-R07), de a `RemoteTutorModelGateway` **bekötése és a flag-rollout még hátravan**, és hosztolás + API-kulcs kell hozzá (user-feladat). |
| **Kör 30** | a fenti kettő | Záró kör: a teljes epic elfogadási mércéjét összegzi, tehát utolsóként írandó (az Epic 5 zárókörének gyakorlata: `ADR 0087` §7 waiver). |

**Szabály erre a batchre:** a B-csoport briefjét **NE írjam meg előre**.
A queue-soruk `hold`-on áll, üres `brief` cellával, amíg a pre-flightjuk
mérhetővé nem válik.

---

## 1. A 30 kör (SDD Chapter 8 tagolása szerint)

| # | Kör | SDD sor | Csoport |
|---|---|---|---|
| 1 | Baseline, ADR-ek és feature flag | 2936 | A |
| 2 | Typed ID-k, enumok és domain primitívek | 2982 | A |
| 3 | Goal, availability és learner constraint domain | 3027 | A |
| 4 | PracticeGenerationRequest és draft persistence | 3073 | A |
| 5 | SkillEvidence normalizálás és evidence repository | 3120 | A |
| 6 | SkillEstimate reducer és konfliktuskezelés | 3167 | A |
| 7 | Legacy Learn és Progress evidence adapterek | 3215 | A |
| 8 | Practice catalog capability adapter | 3262 | A |
| 9 | ExercisePrescription és success criteria | 3309 | A |
| 10 | AdaptivePracticePlan, day, block és revision domain | 3356 | A |
| 11 | PlanValidator és deterministic repair | 3404 | A |
| 12 | SkillPriorityEngine és policy config | 3452 | A |
| 13 | CandidateSelector, hard filter és diversity | 3500 | A |
| 14 | TimeBudgetAllocator és micro-plan | 3548 | A |
| 15 | WeeklyScheduler és terhelésrotáció | 3596 | A |
| 16 | Progression és regression policy | 3644 | A |
| 17 | Spaced repetition és maintenance queue | 3692 | A |
| 18 | GenerationOrchestrator, progress és cancellation | 3740 | A |
| 19 | Local repository, migráció és korrupcióvédelem | 3788 | A |
| 20 | Plan setup wizard és input UX | 3836 | A (UI) |
| 21 | Plan preview, explanation és kézi szerkesztés | 3884 | A (UI) |
| 22 | Weekly Plan és Today screen | 3932 | A (UI) |
| 23 | PlanCompiler és Practice Engine végrehajtás | 3981 | A |
| 24 | Song goal és Song Trainer integráció | 4029 | A |
| **25** | **Analyze és Computer Vision evidence integráció** | 4077 | **B — VÁR** |
| 26 | Outcome ingestion, review update és plan revision | 4125 | A |
| 27 | Missed day, catch-up, pause és returning flow | 4173 | A |
| **28** | **Tutor és PlannerAssistGateway integráció** | 4221 | **B — VÁR** |
| 29 | Accessibility, localization, privacy és safety hardening | 4269 | A |
| **30** | **Evaluation harness, shadow rollout és Epic lezárás** | 4319 | **B — VÁR** |

---

## 2. Motor-hozzárendelés

A motort **nem én becslem meg**, hanem a mért szabály
(`tools/tests/test_pipeline_integration.py::test_open_rounds_follow_the_measured_engine_rule`)
számolja a brief `allowed_paths`-ából:

```
risk == "normal"                            → minimax
risk == "high" ÉS UI/ARB > domain+app+data  → minimax
egyébként                                   → codex (Terra)
```

Ezért a queue `engine` oszlopát **brief-írás után** töltöm ki, a tényleges
útvonalak alapján — előre beírt becslés pirosra váltaná a Router CI-t
(mért eset: E05-R24 H5).

**Várható kép:** a Kör 20–22 (UI) minimax, a többi codex/Terra. A GOV-05b-1
tanulsága (`E99-R06`) viszont figyelmeztet: a `presentation/providers/` alatti
**drótozás** is „UI"-nak számít a proxynál, pedig nem az — ha a szabály
félremér, a kör a queue-n kívül, kézzel indul (a GOV-05a/E99-R06 mintájára).

---

## 3. Indítás — a `hold` feloldása

Előfeltétel: **Epic 6 lezárva** (E06-R30 merge), és a B-csoport három köréhez
a saját előfeltételük is (§0.B tábla).

```bash
sed -i -E 's/^(E07-R[0-9]+\t.*\t)hold$/\1pending/' docs/execution/pipeline-queue.tsv
```

**A lánc egyesével viszi** — `PIPELINE_SLOTS` marad **1**
(user-döntés 2026-08-11: „nem kell dupla kör haladunk sorban"). A
párhuzamosítás mért akadályai: `docs/rounds/epic-06-batch-index.md` és a
memória `parallel-rounds-epic5-plan`.

---

## 4. Készültség

| Rész | Állapot |
|---|---|
| Függőség-mérés (§0) | ✅ kész |
| ADR-tartomány foglalás (0221–0232) | ✅ kész |
| Kör-lista (§1) | ✅ kész |
| A-csoport briefjei (27 db) | ⏳ folyamatban |
| B-csoport briefjei (3 db) | ⛔ szándékosan később |
| Queue-sorok (`hold`) | ⏳ a briefek után |
