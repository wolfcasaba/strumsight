# ADR 0175 — A lánc maradék holtideje, a main egészsége és a kontextus-diéta

**Státusz:** elfogadva (2026-08-05, user-döntés: „csináld meg mindet";
a költség-mérésre külön: „költség nem fontos … nem érdekel — a MiniMax M3
unlimited és a Claude előfizetés").

Az [ADR 0171](0171-pipeline-throughput-program.md) folytatása: ott a merge utáni
cron-várakozás tűnt el, itt a MÉRT maradék.

## Mit mértünk (2026-08-05, `.pipeline/chain.log`, egy nap)

| Kimaradt firing oka | Darab |
|---|---|
| `nyitott PR van` — **governance-PR**, nem kör | **9** |
| `piszkos munkafa` | 3 |
| `fut egy workflow` | 3 |
| `a munkafa nem a main-en van (gov/03-…)` | 1 |

Ugyanezen a napon **három** önjavító kör futott (E04-R14/H6, E04-R15/H3,
E04-R16/H6). Ezekből az R15/H3 gyökéroka nem a kör kódja volt, hanem hogy a
`main` **öröklött piros gate-tel** élt, és ez a KÖVETKEZŐ kör merge-kapuját
fogta meg.

## Döntés

### §1 A blokkoló-őr csak KÖR-branchre néz

A „másik kör lehet folyamatban" őr eredeti célja a párhuzamos kör-driver
kiszűrése. Mostantól csak azok a nyitott PR-ek és futó workflow-k blokkolnak,
amelyek head-branchében ott a kör-azonosító (`[eE]\d\d-[rR]\d\d`) — ez minden
eddigi kör-branch alakja (`codex/e04-r15-…`, `heal/E04-R15-H3-1`,
`minimax/e02-r18-…`). Az `ops/`, `gov/`, `chore/` ágak governance-munkák: nem
versenyeznek körrel, tehát nem is állítják meg a láncot.

Mért ár enélkül: két saját infra-PR kilenc firinget ejtett ki (~45 perc).

### §2 A közös munkafa idegen ága maradék, nem munka

Ha a `main` munkafa tiszta, de nem a `main` ágon áll, a driver **magától
visszaáll** (naplózva). A körök külön munkapéldányban dolgoznak, tehát a fő fán
lévő idegen ág egy korábbi session maradéka. Piszkos fán változatlanul megáll —
ott a helyreállítás munkát semmisítene meg.

### §3 A main egészsége MINDKÉT sávon, és merge után azonnal mérve

* **Indulás előtt:** a lánc a `router-ci.yml` ÉS a `full-gate.yml` main-en futott
  utolsó eredményét is nézi; bármelyik piros → nem indul kör.
* **Merge után:** a driver dispatch-eli a `full-gate.yml`-t a main-re
  (`PIPELINE_MAIN_HEALTH=1`, alap). Ez a KÖVETKEZŐ körrel párhuzamosan fut, tehát
  wall-clockot nem visz, viszont az öröklött piros gate a következő kör ELŐTT
  derül ki — nem annak a merge-kapujánál, egy önjavító kör árán.

Eddig a `full-gate` **soha nem futott** a main-en (dispatch-only workflow).

### §4 Kontextus-diéta

A `HANDOFF.md`-t minden session és minden kör elolvassa (orchestrátor +
implementer), és 2102 sorra hízott. A lezárt körök narratívája átkerült a
`docs/handoff-archive.md`-be: **2102 → 1400 sor (−33%)**. A friss állapot
(§1–§8) és az utolsó két kör bannere marad; a történet archívumban keresendő.

### §5 Költség-főkönyv — bevezetve, de NEM fejlesztjük tovább

A burkoló futásonként egy sort ír (`.pipeline/cost.tsv`: kör, motor, token,
folytatások, státusz), és a `tools/round-metrics.py --cost` kimutatja. A user
döntése szerint **a költség nem szempont** (M3 unlimited, Claude előfizetés),
ezért ez a mérés itt megáll: két teszt őrzi (a sor megszületik; a főkönyv
soha nem buktathat kört), több figyelmet nem kap.

## Őrök

`tools/tests/test_pipeline_plumbing.py` (11 teszt): a governance-branch nem
blokkol, a kör-branch igen, a saját futó kör nem számít idegennek, a minta a
driverben él (nem a tesztben), a tiszta idegen ág helyreáll, a piszkos megáll,
mindkét sáv szerepel az indulási feltételben, a merge utáni dispatch létezik,
és a főkönyv fail-open.

## Következmények

* Governance/infra munka mostantól **nem** fagyasztja le a termék-láncot —
  ez a session három PR-je alatt kb. egy óra veszteség volt.
* A `full-gate` futásszáma nő (körönként +1 a main-en), a merge-kapu ideje nem.
* Visszakapcsolás: `PIPELINE_MAIN_HEALTH=0`; a branch-őr szigorítása egyetlen
  regexp (`ROUND_BRANCH_PATTERN`) a driverben.
