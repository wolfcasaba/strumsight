# ADR 0495 — A párhuzamot a KIMONDOTT előfeltétel dönti el, és a megállt lánc soha nem hallgat el

- **Státusz:** elfogadva (2026-09-03)
- **Kontextus:** ADR 0171 (párhuzamos slotok), ADR 0087 (kör-sor és halt-protokoll),
  ADR 0112 (önjavító lánc), ADR 0494 (származtatott completion-matrix),
  `docs/execution/ch13-throughput-diagnosis.md`
- **Döntéshozó:** user-döntés 2026-09-03 („teljes csomag"), mérés alapján

## Kontextus — hol megy el a fejlesztési idő, mérve

A kérdés az volt, hogy az „állandó automatikus pipeline-javítás" megelőzhető-e.
A mérés szerint **nem az önjavítás a szűk keresztmetszet**:

| forrás | mérés |
| --- | --- |
| `tools/round-metrics.py` | 291 kör, medián **94 perc**, ebből 64 (22%) igényelt önjavítást |
| `tools/round-metrics.py --granularity` | kör-idő ≈ **91 perc fix + 1,8 perc/fájl**, R²=0,066 |
| `.pipeline/chain.log`, 2026-08-30/31 | **576 firing, 0 kör** — `E15-R07 / H2`, kimerült önjavítás, emberi feloldásra várva |
| `.pipeline/chain.log`, 2026-08-28 | 57 firing (~4,75 óra) `H-AUTH` — lejárt GitHub-PAT |
| `.pipeline/chain.log`, 2026-08-16 óta | **1607 firing (~134 óra)** „a lánc továbbra is áll — feloldás: `--resume`" |
| `tools/round-slots.py plan --slots 2` | a 10 nyitott körből **egy sem** volt indítható a futó mellett |

Két, egymástól független hibaosztály:

1. **A 2. slot szerkezetileg használhatatlan.** Az `unmet_prerequisites` első
   forrása egy VAK szabály volt: „minden korábbi, nem `done` kör ugyanabból az
   epicből blokkol" — fájl-átfedéstől függetlenül. Mivel a hátralévő teljes sor
   `E15` + `E16`, a lánc egyszálú lett. MÉRVE: az `E15-R10` és `E15-R11`
   briefje az `E15-R03`-at (KÉSZ) nevezi meg előfeltételként, az `E15-R12`
   pedig (`backend/**` + docs) **egyetlen fájlban sem** ütközik egyetlen
   UI-körrel sem. A soros futás tehát deklaráció volt, nem mérés.
2. **A megállt lánc elhallgat.** A halt-emlékeztető a halt után
   `PIPELINE_HALT_REMINDER_MAX_H` (24) órával VÉGLEG néma lett
   (`[ "$now" -lt "$(( halted_epoch + max_seconds ))" ] || return 1`) — pontosan
   akkor, amikor a baj a legnagyobb. Ez engedte a 2026-08-30/31-i, kétnapos
   kiesést.

## Döntés

**D1 — A blokkolás forrása a brief `Előfeltétel` sora, nem az epic-sorrend.**
Aki nem mondja ki, hogy függ, az párhuzamosan futhat; a fájl-átfedést a
`plan_slots` külön, változatlan szigorúsággal méri. Az importfüggés (a
fájllistából nem látszó „a második kör az elsőben SZÜLETŐ API-t használja")
kimondására a brief prózája az egyetlen csatorna — ez ma minden nyitott
briefen jelen van és MÉRTEN pontos.

**FAIL-CLOSED tartalék:** ha a brief NEM mondja ki az előfeltételét, a régi,
epicen belüli sorosítás lép életbe rá. A hallgatás nem enged párhuzamot.

**D2 — A `docs/ui/migration-status.md` a merge-zár sorosítottja.**
MÉRVE: ez volt az EGYETLEN ütközési felület az `E15-R09` és `E15-R10` között, és
nincs olyan gépi mérce, amely a TARTALMÁT a fa ellen olvasná (a
`screen_reachability_test.dart` és a `theme_adoption_test.dart` a FÁT méri, a
fájlt csak prózában említi). Minden kör a saját dátumozott blokkját fűzi hozzá,
ezért a `tools/round-land.sh` ugyanazzal az append-only unióval oldja fel, mint
a `HANDOFF.md`-t és a `docs/LESSONS.md`-t.

**D3 — A halt-emlékeztető ESZKALÁL, nem hallgat el.** A `MAX_H` küszöb ma nem
elnémítási határ, hanem eszkalációs küszöb: alatta óránként `high`, fölötte
`PIPELINE_HALT_REMINDER_BACKOFF_H` (6) óránként `urgent`, és az üzenet
kiírja, **hány órája** áll a lánc. Nincs olyan időpont, amikor a megállt lánc
némán áll.

**D4 — A GitHub-PAT lejárata előre jelzett.** A `gh` a saját válaszfejlécében
megmondja a lejáratot (`Github-Authentication-Token-Expiration`); a driver ezt
`PIPELINE_GH_TOKEN_PROBE_H` (6) óránként egyszer kérdezi le, gyorsítótárazva, és
a `PIPELINE_GH_TOKEN_WARN_DAYS` (7) napos küszöb alatt szól — két napon belül
`urgent`. Ha a lejárat nem mérhető, a driver CSENDBEN megy tovább: az
előrejelzés kényelem, nem kapu.

**D5 — A `git fetch` HITELESÍTVE megy (kiegészítés, 2026-09-03 08:05).**
MÉRVE: a lánc három egymást követő firingen `HIBA: git fetch origin main
sikertelen`-nel esett ki; a szerver üzenete *„GitHub is temporarily limiting
some unauthenticated downloads"*. Az ok szerkezeti: a repó PUBLIKUS, ezért a
szerver a fetch-re nem küld 401-et, a `store` credential-helper viszont
KIZÁRÓLAG kihívásra tölt — vagyis minden fetch-ünk hitelesítetlen volt (a push
nem: az mindig hitelesít). A git 2.43 nem ismeri a `http.proactiveAuth`-ot
(2.46+), ezért a driver a fejlécet KÖRNYEZETEN át adja át (`GIT_CONFIG_COUNT` /
`GIT_CONFIG_KEY_0` / `GIT_CONFIG_VALUE_0`): a titok se config-fájlba, se
argv-be nem kerül, és a gyerekfolyamatok öröklik. Token nélkül néma no-op.

**D6 — A brief KIMONDHATJA, hogy egy megnevezett körtől FÜGGETLEN (kiegészítés,
2026-09-04).** A D1 a blokkolást a brief `Előfeltétel` sorára bízta, a
kiolvasás viszont MINDEN kör-tokent előfeltételnek vett — tehát pont az
ellenkezőjét értette annak, amit a mondat állít. MÉRVE az E14 sáv
visszakapcsolásakor: három brief szó szerint kimondja, hogy párhuzamosítható
(`E14-R03` ↔ R02, `E14-R06` ↔ R02…R05, `E14-R11` ↔ R10), a terv mégis
EGYETLEN kört engedett a 18-ból.

Két javítás:

1. **A blokkot olvassuk, nem a sort.** A kikötés tipikusan a következő sorra
   van tördelve (`… Az E14-R02-től` / `FÜGGETLEN — …`), amit a soronkénti
   olvasás el sem ért. A `prerequisite_blocks()` az `Előfeltétel` sort és a
   folytatás-sorait fűzi össze (a következő felsorolás-elemig vagy üres sorig).
2. **Mondatonként döntünk, fail-closed.** Egy mondat tokenjeit akkor — és csak
   akkor — hagyjuk ki, ha a mondat függetlenséget mond ki (`független`), és
   NEM állít mellette pozitív kötést (`merge-elve`, `lezárva`, `kész`,
   `szükséges`). A vegyes mondatot MEGTARTJUK: a félreolvasás veszélyes iránya
   két függő kör párhuzamos indítása volna, egy elmaradt párhuzam csak lassabb.

MÉRT hatás: az E14 sáv eleje egyszálúból kétszálúvá vált (`E14-R02` ∥
`E14-R03`), és az `E14-R06` is előfeltétel-kész.

## Mérce

| döntés | őrteszt |
| --- | --- |
| D1 | `tools/tests/test_pipeline_throughput.py::MeasuredPrerequisiteRegimeTest` (6 cella; a javítás előtti eszközzel 4 PIROS) |
| D2 | `…::test_the_migration_journal_is_not_a_collision_surface` + `tools/tests/test_round_land.py` |
| D3 | `tools/tests/test_halt_reminder_escalation.py` (5 cella; a javítás előtt mind PIROS, a kulcscella `QUIET`-et adott) |
| D4 | `tools/tests/test_gh_token_expiry_guard.py` (5 cella) |
| D5 | `tools/tests/test_authenticated_git_fetch.py` (4 cella) |
| D6 | `tools/tests/test_pipeline_throughput.py::IndependenceClauseTest` (6 cella; a javítás előtti eszközzel 3 PIROS) |

A `…::test_the_real_queue_admits_a_second_round_beside_the_running_one` cella a
MÉRT defektet őrzi: ha a nyitott sorból egyetlen kör sem indítható a futó
mellett, a cella PIROS — a 2. slot néma kiesése többé nem maradhat észrevétlen.

## Következmények

- A hátralévő sáv (10 kör) sorosan ~16 óra lánc-idő; valódi kettes párhuzammal
  ~8. MÉRVE a javítás után: az `E15-R09` futása mellett az `E15-R11` azonnal
  indítható (a javítás előtt: egy kör sem).
- A kör-idő regressziója (91 perc fix + 1,8 perc/fájl) azt is kimondja, hogy a
  kör DARABSZÁMA a költség, nem a mérete: a jövőbeli sávokat kevesebb, nagyobb
  briefre érdemes bontani. Ez a jelen ADR-en kívüli, brief-írás oldali
  következmény.
- A `PIPELINE_HALT_REMINDER_MAX_H` jelentése MEGVÁLTOZOTT (elnémítás →
  eszkaláció). Aki eddig magas értékkel „csendesítette" a láncot, ma ritkább,
  de sürgősebb értesítést kap.
