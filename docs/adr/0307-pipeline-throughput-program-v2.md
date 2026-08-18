# ADR 0307 — A kör-pipeline áteresztő-képességének programja v2

**Státusz:** elfogadva (2026-08-18, user-döntés: „csináld meg mindent úgy körökre
bontva hogy hatékony legyen a fejlesztési pipeline … olvass utána az interneten
hogyan fejlesztenek [a nagyok]").

Az [ADR 0171](0171-pipeline-throughput-program.md) (hat lever, 2026-08-05) és az
[ADR 0175](0175-chain-idle-and-context-diet.md) (maradék holtidő) folytatása.
Egyiket sem írja felül: **a mérce változatlan** — a gate lépései, a független
review, a CI-kapuk és a user valódi gitáros APK-tesztje mind érintetlenek.
Ez a program azt a hat MÉRT veszteséget célozza, ami az 0171/0175 bevezetése
ÓTA is megmaradt.

## 1. Kontextus — mit mértünk 2026-08-18-án

Forrás: `.pipeline/chain.log` (141 befejezett kör), `docs/execution/pipeline-queue.tsv`
(75 nyitott brief), `tools/round-metrics.py`, `tools/round-slots.py plan`.

| Mérőszám | Érték | Megjegyzés |
|---|---|---|
| medián kör-idő (utolsó 25 kör) | **82 perc** | 0171 előtt 79 perc volt |
| medián holtidő két kör között | **0 perc** | az 0171 §2 (self-chain) MŰKÖDIK |
| halt-állás 2026-08-01 óta | **115,7 óra / 93 epizód** | a naptári idő ~27%-a |
| ebből egyetlen epizód | **42 óra** | E07-R16, `H-NOSIGNAL`, self-heal 3/3 kimerült |
| önjavítást igénylő kör | 31 / 141 (22%) | 0171 előtt 9/41 (22%) — nem javult |
| `PIPELINE_SLOTS=2` mellett indult párhuzamos kör | **0** | 08-04 óta 120 kör, 1 átfedő pár |
| slot-2 megszerzés → kihagyott firing | 291 → 291 | „nincs diszjunkt, előfeltétel-kész kör" |
| `risk = "high"` a nyitott briefekben | **68 / 75** | a besorolás nem szelektál |

### 1.1 Motorválasztás — mérve 15–20 perc/kör veszteség

A `.pipeline/engine-override` fájl **2026-08-08 óta** `terra`-ra állt (a
2026-08-06-i M3+Terra kvótaválság maradéka), miközben az M3 kerete
2026-08-18-án **92% / heti 98%** volt. Az override minden kört felülírt, tehát
tíz napon át a sor `engine` oszlopa nem érvényesült — és senki nem vette észre,
mert **semmi nem méri az override korát**.

Azonos epicen belül (E07, összemérhető feladat-méret és -típus):

| implementer | mért körök | medián kör-idő | önjavító kör |
|---|---|---|---|
| `sonnet-impl` | 8 | **41 perc** | 6/19 (teljes minta) |
| `minimax` | 5 | **49 perc** | 3/5 |
| `codex` | 1 | 44 perc | 1/2 |
| `terra` | 8 | **63 perc** | 7/27 |

A Terra tehát a leglassabb, és a minőségi mutatója nem jobb. Az override
törlése (2026-08-18) az azonnali intézkedés volt; ez az ADR azt zárja ki, hogy
egy ilyen ideiglenes kapcsoló újra tíz napig észrevétlen maradjon.

### 1.2 A 42 órás állás anatómiája

`E07-R16` 2026-08-16 13:06-kor indult, 14:15-kor `H-NOSIGNAL`-lal halt
(elakadás-őr: 20 perce nem változott a session-napló), majd **három** önjavító
kísérlet futott **ugyanazzal a motorral**, mindhárom ugyanúgy jelzés nélkül halt
el (14:40, 15:05, 15:30). 15:35-kor „az önjavítás KIMERÜLT (3/3)", a lánc
megállt — és **08-18 08:20-ig állt**, mert az egyetlen ntfy-riasztás
(`round-pipeline.sh:1030`) elment, de nem ismétlődött.

Két gépi hiány látszik: (a) az ismétlés **variáció nélküli** — ugyanaz a motor
ugyanazt a hibát hozza; (b) a kimerülés utáni állapot **néma**.

### 1.3 A második sáv strukturális blokkja

A `tools/round-slots.py plan` kimenete szerint a mai sorból egyetlen kör sem
admittálható a második slotba, két, egymástól független ok miatt:

* **előfeltétel-lánc:** az epicen belüli sorrend miatt E07-R23…R30 láncolt, az
  E08-R01 pedig deklaráltan az E07-R30-ra vár;
* **megosztott fájlok:** a 75 nyitott brief `allowed_paths` halmazaiban a
  `lib/l10n/app_en.arb` és `app_hu.arb` **36**-szor, a
  `lib/features/gamification/public.dart` **25**-ször, a
  `lib/core/design_system/public.dart` **18**-szor, a
  `lib/features/practice_generator/public.dart` **8**-szor szerepel.

Az első ok szándékos és konzervatív (ADR 0171 §1) — a második viszont
**mechanikus mellékhatás**: két kör nem azért ütközik, mert ugyanazt a logikát
írja, hanem mert mindkettő hozzáfűz egy sort ugyanahhoz a barrel- vagy
ARB-fájlhoz. Ezt fel lehet oldani a mérce gyengítése nélkül.

## 2. Mit tanultunk kívülről (2026-08-18-i kutatás)

A programot nem csak a saját naplónk alakította. Amit a mezőny mér:

* **A párhuzam csak valóban független munkán fizet.** A 2026-os
  orchestrációs összehasonlítások szerint a több-ügynökös koordináció
  párhuzamosítható feladaton **+81%**, szekvenciális feladaton viszont
  **−39…−70%** teljesítményt hoz ([Digital Applied, 2026](https://www.digitalapplied.com/blog/multi-agent-orchestration-5-patterns-that-work)).
  Ez pontosan a mi mérésünk: a soros soron a `SLOTS=2` nulla nyereség.
* **A centralizált koordináció fékezi a hibaerősítést.** 180 ügynök-konfiguráció
  kiértékelésében a központi koordináció 4,4×, a független párhuzamos ügynökök
  17,2× hibaerősítést mutattak ([amux, 2026](https://amux.io/guides/ai-agent-orchestration-2026/)).
  Ezért a programban **nem** lazítunk az orchestrátor-központú láncon: a második
  sáv is teljes kör (brief → gate → független review → CI → zöld kapu).
* **A párhuzamos worktree a legnagyobb egyéni gyorsító.** A Claude Code
  készítőinek listáján az első tipp 3–5 párhuzamos git-worktree
  ([Anthropic best practices](https://www.anthropic.com/engineering/claude-code-best-practices)) —
  nálunk ez már megvan (körönként külön munkapéldány), csak a *sor* nem
  szolgálja ki.
* **A verifikáció a legfontosabb egyetlen gyakorlat**, és a friss kontextusú
  reviewer kevésbé elfogult ([Anthropic best practices](https://www.anthropic.com/engineering/claude-code-best-practices)).
  Ez nálunk ADR 0055/0138 óta él — a program egyetlen levere sem nyúl hozzá.
* **Batch és merge-queue:** a csapatok 94%-a ma is egyesével merge-el, pedig a
  batchelés 2–5× átbocsátást hoz ([Mergify, State of Merge Queues 2026](https://mergify.com/reports/state-of-merge-queues-2026)).
  Nálunk a CI nem a szűk keresztmetszet (a kör ~8%-a), ezért ebből csak a
  **záró commitok összevonását** vesszük át (§6), a merge-queue-t nem.
* **Az elakadás-őr iparági alapminta** (heartbeat-frissesség figyelése és
  kilövés), a hozzá tartozó **modell-fallback** viszont nálunk hiányzott
  ([AgentCenter, 2026](https://www.agentcenter.cloud/blogs/how-to-detect-agent-stuck-or-looping)).
  A §2 pontosan ezt pótolja.
* **Rövid életű ágak:** a DORA 24 órás ág-élettartam-határa
  ([dora.dev](https://dora.dev/capabilities/trunk-based-development/)) nálunk
  teljesül (medián kör 82 perc) — kivéve a halt-epizódokat, amiket a §2 céloz.

## 3. Döntés — hat lever, hat kör

Minden lever külön kör (`E99` governance-pszeudo-epic), mindegyik gépi őrrel és
alapértelmezésben visszakapcsolható kapcsolóval.

### §1 — E99-R14: a motorválasztás mérésre kötve, az override lejár

* `tools/engine-profile.sh use <motor> [--ttl <óra>]`: az override **lejárati
  bélyeget** kap; a driver a lejárt override-ot törli, naplózza és értesít.
* TTL nélküli override **72 óránál** idősebben minden firingen figyelmeztet
  (naponta egyszer ntfy-jal) — a csendes tíznapos drift megszűnik.
* `tools/round-metrics.py --engines`: motoronkénti medián kör-idő, önjavítási
  arány és mintaszám, `--epic` szűréssel — a §1.1 táblázata ezután egy parancs,
  nem kézi elemzés.

### §2 — E99-R15: a halt-eszkaláció variációt és hangot kap

* A **3. (utolsó) önjavító kísérlet más motorral fut**, mint az előző kettő
  (determinisztikus fallback-sorrend a motor-nyilvántartásból). Indoklás: a két
  valaha mért kimerülés (E03-R09, E07-R16) MINDKETTŐ `H-NOSIGNAL` volt, és a
  variáció nélküli ismétlés ugyanazt a hibát hozta.
* Kimerülés után a lánc **nem néma**: `PIPELINE_HALT_REMINDER_MIN`
  (alap 60 perc) percenként ismételt, magas prioritású ntfy megy, amíg a
  `.pipeline/HALTED` áll, legfeljebb `PIPELINE_HALT_REMINDER_MAX_H` (alap 24)
  órán át, a resume-paranccsal a törzsben.
* **Amit NEM teszünk:** nincs automatikus resume, és a `H-GATEGUARD`
  (az önjavítás a gate-hez nyúlt) változatlanul emberi döntés marad. A
  mérce-gyengítés kockázatát nem cseréljük wall-clockra.

### §3 — E99-R16: a kör-granularitás mérése és az összevonás gépi javaslata

Az ADR 0171 §5 kimondta, hogy a kör-összevonás **mérésre**, ne érzésre menjen —
a mérőeszköz azonban hiányzott. Ez a kör pótolja:

* `tools/round-metrics.py --granularity`: kör-idő a brief méretének
  (`allowed_paths`, `gate_tests` darabszám) függvényében, a fix overhead a
  regresszió tengelymetszeteként — mérve, nem becsülve;
* `tools/brief-merge-plan.py`: összevonásra javasolt brief-PÁROK azon
  feltételekkel, hogy (a) egymás közvetlen előfeltételei, (b) azonos feature-
  gyökér, (c) az `allowed_paths` uniója a mért küszöb alatt marad, (d) egyik sem
  `native_gate`;
* `brief-lint --level strict`: „aránytalanul kicsi kör" lelet.

A tool **nem von össze** semmit: a döntés a brief-előkészítésé, ahogy az
ADR 0171 §5 mondja. A sor-séma nem változik.

### §4 — E99-R17: az ARB-ütközés feloldása (a párhuzam első fizikai blokkja)

`lib/l10n/app_en.arb` + `app_hu.arb` 36 nyitott briefben szerepel, tehát bármely
két kör ütközik. Feloldás **szegmentálással**: a körök feature-szintű
ARB-fragmentumot írnak (`lib/l10n/features/<feature>_{en,hu}.arb`), az aggregált
`app_*.arb` **generált** artefaktum (determinisztikus, kulcs szerint rendezett
unió), amit a gate frissességre ellenőriz. Két kör így csak akkor ütközik, ha
UGYANAHHOZ a feature-fragmentumhoz nyúl.

A kör egy pilot-feature migrációját végzi el; a többi lustán, a rá következő
körök során vándorol át. A `check_l10n_parity` mérce változatlanul fut.

### §5 — E99-R18: generált `public.dart` barrelek

`gamification/public.dart` 25, `core/design_system/public.dart` 18,
`practice_generator/public.dart` 8 briefben szerepel — kizárólag azért, mert
mindegyik kör hozzáfűz egy export-sort. A barrel ezután **generált**:
a körök `lib/features/<feature>/public/<modul>.exports.dart` fragmentumot írnak,
a barrelt `tool/gen_public_barrel.dart` állítja elő, a gate a frissességet méri
(ugyanaz a minta, mint az architektúra-ellenőrzésnél). Pilot: `gamification`.

### §6 — E99-R19: lánc-higiénia

* **Main-szinkron:** tiszta munkafánál a driver magától `fetch + ff-merge`-el,
  ha a lokális `main` LEMARADT az `origin/main` mögött (mérve 7 nap alatt 9
  kihagyott firing). Piszkos fán változatlanul megáll (ADR 0175 §2 határa).
* **Záró commitok összevonása:** a kör két záró pushja (`docs(handoff…)` és
  `chore(pipeline)`) EGY commit-tá és EGY pushsá válik → körönként eggyel
  kevesebb Router CI futás (mérve 4 perc 45 mp/futás) és kevesebb „fut egy
  workflow" blokkolás.
* **Kockázati besorolás:** `brief-lint --level strict` leletet ad, ha
  `risk = "high"`, de a brief nem nevez meg indokot (útvonal-töredék vagy
  explicit „Kockázat:" sor). Mérve 68/75 brief `high` — így a besorolás ma nem
  szelektál, a security-review pedig minden körre fut.

## 4. Miért nem gyengül ettől a mérce

| Kockázat | Őr |
|---|---|
| a §2 eszkaláció automatikus resume-má csúszik | teszt: kimerülés után NINCS session-indítás, csak riasztás |
| a §2 motorváltás a gate-et kerülné meg | a heal-prompt és a `H-GATEGUARD` ág változatlan; teszt őrzi |
| a §4/§5 generátor kimarad a gate-ből | frissesség-lépés a `tools/round-gate.sh`-ban + teszt, hogy a lépés létezik |
| a generált aggregátum kulcsot veszít | `check_l10n_parity` + unió-teszt (minden fragmentum-kulcs megjelenik) |
| a §6 összevont záró commit elnyeli a sor-frissítést | teszt: a `done` státusz és a HANDOFF ugyanabban a commitban van |
| a §1 TTL kikapcsolja az override-ot kör közben | a lejárat csak kör-KIVÁLASZTÁSKOR érvényesül, futó körre nincs hatása; teszt |
| a §3 „kis kör" lelet összevonásra kényszerít | strict szint (nem CI-kapu), és a tool csak javasol |

## 5. Következmények

* A `PIPELINE_SLOTS=2` a §4/§5 után lesz először értelmes: a governance-sáv
  (E99) már MA diszjunkt a termék-epictől, tehát a program saját körei az első
  valódi második-sáv-használat — ez egyben a lever mérése is.
* A cron `PIPELINE_SLOTS=2` beállítása addig marad, ameddig a `plan` kimenete
  ténylegesen admittál kört; ha a program után sem admittál, a kapcsoló
  visszaáll 1-re (őszinte napló elve, ADR 0171 §1).
* A `.ai/router.toml` `high_risk_path_fragments` listája a `privacy`, `camera`,
  `vision`, `share`, `upload` töredékekkel bővül (orchesztrátor-hatáskör: a
  fájl a `protected_paths` listáján van, implementer nem nyúlhat hozzá).

## 6. Várt hatás (a mért alapon, nem ígéret)

| Lever | Mért veszteség ma | Várt megtakarítás |
|---|---|---|
| §1 motorpolitika | 15–20 perc/kör, ha az override rossz motoron ragad | a drift-ablak 10 nap → 3 nap |
| §2 halt-eszkaláció | 42 óra egyetlen epizódban, 115,7 óra összesen | az ismétlődő riasztás az epizódot órákra vágja |
| §3 granularitás | 40–50 perc fix overhead 47–63 perces köröknél | összevont körpáronként ~40 perc |
| §4+§5 ütközés-feloldás | a második sáv 100%-ban blokkolt | a `plan` először admittál valódi párhuzamot |
| §6 higiénia | 9 kihagyott firing/hét + 1 felesleges CI/kör | ~1 óra/hét + CI-terhelés |

A számok a `tools/round-metrics.py` következő futásaiban ellenőrizhetők — a
program sikerét NEM a jelen ADR állítja, hanem a bevezetés utáni mérés.
