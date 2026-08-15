# E07-R07 — Független review

- **Első review SHA:** `22e66d11dd3af592835e24d21394a4cf172f380c`
- **Javítás utáni review SHA:** `d8e678bca61d89503f288862e8560ef8ecc8234a`
- **Reviewer:** Terra orchestrátor, izolált remote-klónok: `/tmp/review-e07-r07`, `/tmp/review-e07-r07-fix`
- **Verdict:** **APPROVED**

## Bizonyíték

- Scope audit: `python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e07-r07 --brief docs/rounds/e07-r07-legacy-evidence-adapters.md --base a797eb9f` → `OK`, 8 módosított út.
- Független gate az izolált remote-klónban: format, analyze, 7 Learn- és 11 Progress-teszt, architecture, secrets, l10n → mind zöld.
- Eltávolított, eldobható review-próba két hibát pirosra vitt: a `Lessons.firstStrums` built-in mappingje üres evidence-et adott; a két-skill mappingből ugyanazzal az outcome ID-val kiadott második evidence az `EvidenceAggregator`/`InMemoryPracticeEvidenceRepository` után eltűnt.

## Leletek

| ID | Súlyosság | Lelet | Bizonyíték és javítási irány |
|---|---|---|---|
| F1 | MAJOR | A `LegacyMappingTable.builtIn` (`legacy_mapping_table.dart`) `g-major-first-strum`, `c-to-g-swap`, `d-major-basics` lesson ID-kat tartalmaz, amelyek nem részei a publikus `Lessons.all` beépített katalógusának (pl. a tényleges ID `first-strums`). Emiatt a shipping mapping minden valódi beépített leckét `unmappedLesson`-ként kihagy, tehát nem állít elő használható Learn evidence-et. | Az eldobható `Lessons.firstStrums` próba `Expected: non-empty / Actual: []` hibával bukott. A táblát a `Lessons.all` mért, tényleges ID-ira kell rögzíteni, és a tesztben a valódi publikus katalógus legalább egy eleme legyen fixture. |
| F2 | MAJOR | A mapping modell több `skillIds`-t enged ugyanahhoz a lesson outcome-hoz, a Learn adapter pedig mindegyikhez változatlan `sourceOutcomeId`-t ad ki. Az R05 repository globálisan ezen az ID-n deduplikál, így a második skill evidence elveszik. | Az eldobható két-skill próba `skill.b`-re `Expected length 1 / Actual length 0` hibát adott az `EvidenceAggregator.ingest` után. A szerződést egy outcome → egy skill kapcsolatra kell szűkíteni (vagy a több outcome-ról valós, forrás-oldali azonosítót kell átadni); adapter nem képezhet skill-szuffixed új ID-t. A regressziós teszt az adapter utáni repository-ingestet is mérje. |

## Javító kör és lezáró ellenőrzés

- A Sonnet javító kör `d8e678bc` commitja a built-in táblát a valódi
  `Lessons.all` ID-kra (`first-strums`, `two-chord-change`, `eighth-drive`)
  rögzítette, és az adattípust egy outcome → legfeljebb egy skill szerződésre
  szűkítette.
- Az izolált javítás utáni gate: format, analyze, 9 Learn- és 11
  Progress-teszt, architecture, secrets, l10n → mind zöld.
- Scope audit: `python3 tools/scope-audit.py --repo /tmp/review-e07-r07-fix
  --brief docs/rounds/e07-r07-legacy-evidence-adapters.md --base a797eb9f`
  → `OK`, 9 módosított út, 1 generált/ignorált út.
- Valódi-sértés próba: a review-klón mindhárom shipping lesson ID-ját fiktívre
  módosítva a F1 regressziós teszt piros lett (`no Lessons.all entry is mapped
  by LegacyMappingTable.builtIn`); a változtatást azonnal visszaállítottuk.
- Az F2 regressziós teszt az adapterből kimenő evidence-et az
  `EvidenceAggregator`on és az R05 repository-n is átengedi, ezért a korábbi,
  azonos `sourceOutcomeId` miatti csendes elvesztést közvetlenül méri.

Az F1 és F2 MAJOR lelet javítva; új BLOCKER vagy MAJOR nincs.
