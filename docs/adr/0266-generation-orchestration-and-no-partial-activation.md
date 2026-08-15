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
