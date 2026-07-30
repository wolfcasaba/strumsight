# ADR 0064 — A Codex `code-complete`-nél átadja a CI-t, és nem futtat semmit kétszer

- **Státusz:** elfogadva (2026-07-29, user-döntés)
- **Kontextus:** [ADR 0052](0052-ci-apk-automerge-session-per-round.md) (zöld-kapus
  merge), [ADR 0053](0053-ci-full-test-suite.md) (teljes suite a CI-ban),
  [ADR 0055](0055-agent-role-protocol.md) (ágensszerepek), `AGENTS.md` §12, §15
- **Szám:** 0064 (a 0059–0063 az E01-R11…R15 köröknek van kiosztva)

## Kontextus

Az ADR 0053 óta a teljes regresszió a CI-ban fut, lokálisan „a kör érintett
területe". A gyakorlatban ez két veszteséget termelt:

1. **Kétszeres futtatás.** Az E01-R11-ben a Codex lokálisan lefuttatta a
   `test/app` (26), `test/tooling` (8), `test/features/live` (160+2 skipped) és
   `test/features/library` (12) készletet — ~210 tesztet, percekben mérve ezen az
   egy magon —, majd a CI ugyanezeket még egyszer lefuttatta a teljes ~993-as
   suite részeként. A lokális futás semmilyen bizonyítékot nem adott hozzá: a
   merge-bar úgyis a CI-run.
2. **Soros várakozás.** A CI csak akkor indult el, amikor az orchestrátor a
   Codex kilépése után ránézett a körre — pedig a kód addigra rég készen és
   feltolva volt. A CI ~10 perce így a review IDEJÉHEZ adódott, ahelyett hogy
   alatta futott volna.

## Döntés

**1. A Codex `code-complete`-tel adja át a CI-t.** Amint a kód kész, formázott,
analyze-zöld és **fel van tolva**, kiadja:

```bash
tools/codex-signal.sh code-complete "<egy soros összegzés>"
```

A `tools/codex-watch.sh` figyelő ezt látva **azonnal** dispatch-eli a
`build-apk.yml`-t a kör-branchre, majd kilép (= értesíti az orchestrátort).
A dispatch Claude-oldali marad — a Codex nem hív `gh`-t (ADR 0055) —, és csak
akkor fut le, ha a lokális HEAD megegyezik az `origin/<branch>` HEAD-jével,
különben a bizonyíték régi commitra vonatkozna. A `done` jelzés ezután jön, a
brief §10 handoff kitöltésével.

**2. Lokálisan csak a kör SAJÁT új/módosított tesztjei futnak.** A tágabb
területi suite futtatása lokálisan tilos. A lokális teszt szerepe innentől egy
smoke-teszt („az új teszt tényleg zöld"), nem regresszió-bizonyíték.

## Következmények

- A CI a jelentésírás és a review alatt fut → a kör wall-clock ideje a CI-idővel
  csökken, a bizonyíték szintje változatlan.
- **A merge-bar NEM változik** (ADR 0052/0053): teljes suite + randomizált-seedű
  property gate + release APK a CI-ban, mind zöld, különben nincs merge.
- Ha egy teszt csak a CI-ban bukik, a visszacsatolás lassabb, mint egy lokális
  futásé. Ezt elfogadjuk: a duplikált lokális futás sem előzte meg a hibát, csak
  a saját területén szűrt, és a CI úgyis kötelező.
- A `code-complete` utáni jelentés nélküli kilépés nem mosódik el: a
  `tools/codex-round.sh` ilyenkor `status=unknown`-t ír, expliciten megjelölve,
  hogy a kód megvan, de a §10 handoff hiányzik.

## Alternatívák

- **A CI elhagyása kód-körökön, a Codex lokális zöldjére hagyatkozva** —
  elutasítva: a lokális futás a suite ~20%-át fedte, property gate és APK
  nélkül, egy olyan körben (routing), amin minden képernyő átmegy. A
  self-reportált zöld amúgy sem bizonyíték (ADR 0055 §15.1).
- **A teljes suite lokális futtatása** — elutasítva, ez az ADR 0053 eredeti oka:
  ~15 perc ezen a boxon, az analyze+test lánc OOM-ol.
