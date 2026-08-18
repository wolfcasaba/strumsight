# ADR 0266 — Megszakítás után nincs írás, részleges terv nem aktiválódik

**Státusz:** elfogadva (2026-08-15). Az Epic 7 folyamatvezérlésének döntése.
Forrás: [`docs/sdd/08-epic-07-ai-practice-generator.md`](../sdd/08-epic-07-ai-practice-generator.md) Ch8 Kör 18.
Épít: [ADR 0254](0254-analysis-run-request-and-v2-runner-wiring.md) §5.4
(megszakított futás nem ad részleges dokumentumot),
[ADR 0256](0256-practice-plan-revisions-immutable-past.md) (immutable múlt),
[ADR 0263](0263-bounded-deterministic-plan-repair.md) (érvénytelen terv nem aktiválható).

## Kontextus

A generálás sok lépésből áll (evidence → becslés → prioritás → jelöltek → idő →
ütemezés → validáció). A felhasználó bármikor megszakíthatja, és bármelyik
lépés hibázhat. A kérdés nem az, hogy **lehet-e** részeredményt menteni, hanem
hogy **szabad-e**.

## Döntés

### 1. Megszakítás után nincs perzisztens írás

A `cancel()` után a folyamat semmit nem ír. A projekt ezt a mintát már
megoldotta az elemzésnél (ADR 0254 §5.4); ugyanaz érvényes a tervezőre.

### 2. Részleges terv soha nem aktiválódik

Ha bármely lépés hibázik vagy megszakad, a terv nem válik aktívvá. A félkész
terv **rosszabb, mint a semmilyen**: a tanuló hiányos napokat kapna, és nem
tudná, mi hiányzik.

### 3. Az újrapróbálás tiszta futást indít

A retry nem örökölhet részállapotot. Ez a legnehezebben észrevehető hiba:
szennyezett állapot mellett a második futás **más eredményt** ad ugyanarra a
kérésre, ami az ADR 0255 determinizmusát rontja el.

### 4. Azonos kérés párhuzamos futása kontrollált

Ugyanarra a kérésre nem indul két versenyző futás. Vagy a második nem indul,
vagy az első megszakad — de nem versenyeznek.

### 5. Az állapotgép immutable, az átmenetek kikényszerítettek

Az UI immutable állapotból olvas, és érvénytelen átmenet hiba.

### 6. Minden hiba `AppFailure`-re képezve

Nyers kivétel nem lép át a határon.

## Következmények

- A felhasználó bármikor megszakíthat anélkül, hogy „félig kész" tervet
  örökölne.
- A generálás megismételhető: ugyanaz a kérés ugyanazt adja, retry után is.
- A repository (Kör 19) csak befejezett, validált tervet lát.

## Mérce

Az `E07-R18` §6.1 mérce-mátrixa, benne a megszakítás három kötelező cellájával
(korán / **az utolsó lépés alatt, az aktiválás előtt → nincs írás** / a
sikeres aktiválás után → no-op) és a valódi-sértés próbával: részeredményt
mentve megszakításkor az **A1** cellának pirosnak kell lennie.

## Módosítás (ADR 0112 önjavító kör, 2026-08-18)

**Pontosítás, nem tartalmi változás.** A 2. döntés („Részleges terv soha nem
aktiválódik") kizárólag a MEGSZAKÍTOTT vagy hibás futásra vonatkozik — nem
mondja ki, és nem is mondta ki soha, hogy egy TELJES, sikeresen validált terv
a `generate()` hívó felé való visszatérése ELŐTT, emberi megerősítés nélkül
automatikusan aktiválódjon. Az, hogy `GenerationOrchestrator._run()`
(`generation_orchestrator.dart:150-154`) egy sikeres validálás/javítás után
azonnal, a `generate()` saját záró hatásaként hívja
`activation.activate(activePlan)`-t, **implementációs választás volt ezen az
ADR-en BELÜL**, nem annak a 2. döntésnek a szükségszerű következménye.

Ezt a pontosítást az **E07-R21** (Plan preview, explanation és kézi
szerkesztés) halt-je (H2, 2026-08-18) tette szükségessé: a brief saját
frontmatterje az ADR-t „nincs automatikus aktiválás"-ként glosszázta, ami a
fenti, szűkebb 2. döntéssel összekeverve téves premisszát adott, és a
generálás-előtti előnézet + explicit megerősítés UX-et hibásan az
application-réteg módosítását igénylőnek mérte. A self-heal feloldása
(`docs/rounds/e07-r21-plan-preview-and-explanation.md` §0.0) R21-et egy
önálló, a valódi `GenerationOrchestrator`-t nem hívó preview-komponensre
szűkítette — ez NEM ennek az ADR-nek a döntéseit módosítja.

**Nyitott follow-up** (még ki nem osztott kör): amíg `generate()` a
validálást/javítást és az aktiválást egyetlen, megszakítás nélküli hívásban
fuzionálja, semmilyen jövőbeli kör nem tudja a preview-képernyőt a VALÓDI
generálási folyamathoz kötni úgy, hogy az aktiválás előtt egy MÉG NEM aktív,
csak validált tervet kapjon vissza. Az éles bekötéshez `generate()`
aktivációs lépését explicit, elkülönített hívássá kell szétválasztani —
ez sem az E07-R18, sem az E07-R21 scope-ja nem volt/lesz, `HANDOFF.md`-ben
nyitott tételként rögzítve.
