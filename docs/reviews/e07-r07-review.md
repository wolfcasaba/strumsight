# E07-R07 — Független review

- **Review SHA:** `22e66d11dd3af592835e24d21394a4cf172f380c`
- **Reviewer:** Terra orchestrátor, izolált remote-klón: `/tmp/review-e07-r07`
- **Verdict:** **CHANGES REQUESTED**

## Bizonyíték

- Scope audit: `python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e07-r07 --brief docs/rounds/e07-r07-legacy-evidence-adapters.md --base a797eb9f` → `OK`, 8 módosított út.
- Független gate az izolált remote-klónban: format, analyze, 7 Learn- és 11 Progress-teszt, architecture, secrets, l10n → mind zöld.
- Eltávolított, eldobható review-próba két hibát pirosra vitt: a `Lessons.firstStrums` built-in mappingje üres evidence-et adott; a két-skill mappingből ugyanazzal az outcome ID-val kiadott második evidence az `EvidenceAggregator`/`InMemoryPracticeEvidenceRepository` után eltűnt.

## Leletek

| ID | Súlyosság | Lelet | Bizonyíték és javítási irány |
|---|---|---|---|
| F1 | MAJOR | A `LegacyMappingTable.builtIn` (`legacy_mapping_table.dart`) `g-major-first-strum`, `c-to-g-swap`, `d-major-basics` lesson ID-kat tartalmaz, amelyek nem részei a publikus `Lessons.all` beépített katalógusának (pl. a tényleges ID `first-strums`). Emiatt a shipping mapping minden valódi beépített leckét `unmappedLesson`-ként kihagy, tehát nem állít elő használható Learn evidence-et. | Az eldobható `Lessons.firstStrums` próba `Expected: non-empty / Actual: []` hibával bukott. A táblát a `Lessons.all` mért, tényleges ID-ira kell rögzíteni, és a tesztben a valódi publikus katalógus legalább egy eleme legyen fixture. |
| F2 | MAJOR | A mapping modell több `skillIds`-t enged ugyanahhoz a lesson outcome-hoz, a Learn adapter pedig mindegyikhez változatlan `sourceOutcomeId`-t ad ki. Az R05 repository globálisan ezen az ID-n deduplikál, így a második skill evidence elveszik. | Az eldobható két-skill próba `skill.b`-re `Expected length 1 / Actual length 0` hibát adott az `EvidenceAggregator.ingest` után. A szerződést egy outcome → egy skill kapcsolatra kell szűkíteni (vagy a több outcome-ról valós, forrás-oldali azonosítót kell átadni); adapter nem képezhet skill-szuffixed új ID-t. A regressziós teszt az adapter utáni repository-ingestet is mérje. |

## Következő lépés

Azonos Sonnet implementer-javító kör: csak az F1/F2-höz szükséges engedélyezett
mapping/adapter/teszt/brief fájlok módosíthatók. Javítás után friss remote-klónos
gate, scope-audit és teljes tételes re-review szükséges.
