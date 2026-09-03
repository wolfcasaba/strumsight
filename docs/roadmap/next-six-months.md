# StrumSight — Next six months roadmap (outcome-based)

- **Készült:** E12-R36, 2026-09-02
- **Kiindulás:** `docs/sdd/program-completion-report.md` §3–§5 mért állapota.

Ez a roadmap **kimeneteket** (outcome) nevez meg, nem funkciólistát. A
hátralévő SDD-körök átmásolása feature-listaként a §5.2 tiltott gyengítése
lenne (`docs/rounds/e12-r36-program-completion-and-next-roadmap.md`). Minden
tétel három kötelező sort tartalmaz — `**Outcome:**`, `**Mérőszám:**` (számmal),
`**Forrás:**` (mi méri) —, amit
`test/tooling/program_completion_test.dart` gépileg ellenőriz (A4).

## 1. A valódi gitáros elfogadja a kiadást élő eszközön

**Outcome:** Legalább egy valódi gitáros (akusztikus vagy elektromos) egy
fizikai Android eszközön, a release APK-val végigvisz egy élő gyakorlást, és
a hangnem/pengetésirány-felismerés elég jónak bizonyul ahhoz, hogy tovább
gyakoroljon vele — ez a program végső elfogadási próbája, amit szintetikus
zöld gate soha nem helyettesít.

**Mérőszám:** legalább 1 dokumentált, valós eszközön futtatott munkamenet
jegyzőkönyve, amelyben ≥10 akkordváltás és ≥3 pengetésirány-váltás közül a
felismerés szubjektív "elég jó"-nak minősül, és nulla összeomlás történik a
munkamenet alatt.

**Forrás:** dokumentált manuális teszt-jegyzőkönyv `docs/release/` alatt (nem
CI-artefaktum) — a `docs/sdd/program-completion-report.md` §5 táblázatának
"Valódi gitáros APK-teszt" sora ezt a mérőszámot zárja NYITOTTból.

## 2. A legacy UI biztonságosan visszavonul

**Outcome:** minden képernyő átköltözik az adaptív shell-re, a legacy
képernyők elérhetetlenné válnak navigációból, és a funkció-elérhetőség nem
csökken a migráció során.

**Mérőszám:** a `docs/execution/pipeline-queue.tsv` `E15`/`E16` előtagú
sorainak `pending` száma 11-ről (mai mérés: E15 6 + E16 5) 0-ra csökken, és
`test/tooling/screen_reachability_test.dart` a migráció után is ugyanannyi
vagy több elérhető route-ot mér, mint a migráció előtt.

**Forrás:** `docs/execution/pipeline-queue.tsv` (E15/E16 előtag) +
`test/tooling/screen_reachability_test.dart`.

## 3. A közösségi platform (Epic 9) biztonsági és skálázási kapui zárulnak

**Outcome:** a privacy export/deletion, az offline szinkron-ütközés
kezelése, a rate-limit/biztonsági keményítés, az akadálymentesítési/
lokalizációs csiszolás és az integrációs terhelés-értékelés mind mérve és
elfogadva — az 5 `hold` kör felszabadul.

**Mérőszám:** a `pipeline-queue.tsv` `E09` előtagú sorainak `hold` száma
5-ről 0-ra csökken.

**Forrás:** `docs/execution/pipeline-queue.tsv` (E09 előtag).

## 4. Az Offline AI (Epic 10) sáv valódi döntést kap

**Outcome:** vagy megjelenik legalább egy on-device tanár/generálás
képesség mért eszköz-benchmark bizonyítékkal, vagy a sáv dokumentáltan
lezárásra kerül — a mai `hold`-on-mind-a-32-kör állapot önmagában NEM
döntés, csak egy fel nem oldott várakozás.

**Mérőszám:** a `pipeline-queue.tsv` `E10` előtagú soraiból legalább 1 kör
`done`-ná válik valós eszköz-benchmark bizonyítékkal, VAGY egy ADR
dokumentáltan lezárja (retirement) az epicet.

**Forrás:** `docs/execution/pipeline-queue.tsv` (E10 előtag) + egy jövőbeli
ADR a `docs/adr/` alatt.

## 5. A felismerési pontosság program (Chapter 14) mért alapvonalat ér el

**Outcome:** a felismerés-helyreállítási briefek (R02–R19) ténylegesen
lefutnak valós hangmintákon, nem maradnak `prepared` státuszban; az
R20–R42 briefjei csak azután íródnak meg, hogy az alapvonal-körök igazolják
a megközelítést.

**Mérőszám:** a `pipeline-queue.tsv` `E14` előtagú `done` sorainak száma
1-ről (a mai R01) legalább 10-re nő a hat hónap alatt, és a hard-negative /
false-visible mérőszám (E14-R15 definíciója) első valós mérése megtörténik.

**Forrás:** `docs/execution/pipeline-queue.tsv` (E14 előtag) +
`docs/rounds/e14-r09-baseline-dashboard-and-release-gate.md` release-gate
definíciója.

## 6. Az emberi release-kapuk ténylegesen megnyílnak

**Outcome:** az E12-R27…R33 körök által szállított eszközök (zárt béta
tooling, rollout-automatizálás, GA runbook) egy VALÓS zárt bétához, egy
VALÓS szakaszos rollouthoz és egy VALÓS GA-hoz kerülnek felhasználásra — nem
maradnak használatlan eszközök.

**Mérőszám:** legalább 1 valós Play Console béta sáv aktiválva dokumentált
tesztelői létszámmal, és a szakaszos rollout százaléka 0%-ról ténylegesen
elmozdul egy valós konzolon, a jelen roadmap következő felülvizsgálata
előtt.

**Forrás:** dokumentált manuális/Play Console bizonyíték `docs/release/`
alatt (nem CI) — a `docs/sdd/program-completion-report.md` §5 táblázatának
hét `E12-R27`…`E12-R33` sora ezt a mérőszámot zárja NYITOTTból.

## 7. A technikai adósság leltár csökkenő trendet mutat

**Outcome:** az E12-R35 adósság-audit eszköz (`tool/check_deprecations.dart`)
mért alapvonala nem nő, hanem csökken a következő fél évben.

**Mérőszám:** az `architectureAllowlistBaseline` (ma: 12 bejegyzés) és a
`@Deprecated` helyszínek száma (ma: 12 helyszín 9 fájlban) egyik negyedéves
méréskor sem nő a mai érték fölé, és legalább az egyikük csökken.

**Forrás:** `tool/check_deprecations.dart` (`test/tooling/deprecation_audit_test.dart`
futtatja negyedévente a gate részeként).
