# ADR 0263 — A terv-javítás korlátos, determinisztikus és megindokolt

**Státusz:** elfogadva (2026-08-15). Az Epic 7 validáció/javítás döntése.
Forrás: [`docs/sdd/08-epic-07-ai-practice-generator.md`](../sdd/08-epic-07-ai-practice-generator.md) Ch8 Kör 11.
Épít: [ADR 0255](0255-deterministic-first-practice-planning.md) (determinizmus,
magyarázhatóság), [ADR 0256](0256-practice-plan-revisions-immutable-past.md)
(immutable múlt), [ADR 0258](0258-hard-and-soft-planning-constraints.md)
(hard korlátok).

## Kontextus

A tervező kimenete és a kézi szerkesztés is sérthet invariánst: hiányzó asset,
nem támogatott capability, rossz hangolás, hard-avoid ütközés, túl sűrű
terhelés. A rendszer ilyenkor **javíthat** — és pont ez a képesség tud
csendben ártani.

Három konkrét veszély:

1. **Nem termináló javítás.** Egy „amíg minden invariáns teljesül" ciklus
   éles adaton befagyaszthatja az appot.
2. **Az idő-hozzáadás mint univerzális megoldás.** A legtöbb ütközés
   feloldható több idővel — épp azt sértve, amit a tanuló megadott.
3. **A csendes szerkesztés.** Ha a javítás nem indokolt, a terv
   magyarázhatatlan lesz, és az ADR 0255 kimondott célja vész el.

## Döntés

### 1. `error`/`fatal` mellett a terv nem aktiválható

A validáció **kapu**, nem tanács.

### 2. A javítás terminál — kimondott iterációs korláttal

A lépésszám felülről korlátos. A korláton belüli sikertelenség **feladás és
hibajelzés**, nem további próbálkozás.

*A terminálást bizonyítani kell, nem érvelni mellette:* a kör property-tesztet
ad (`test/property/`, `PROPERTY_SEED` konvenció), mert a fuzz talál olyan
bemenetet, amit a kézzel írt eset nem.

### 3. A javítás soha nem lépi túl a hard időmaximumot

Az ADR 0258 §3 a javításra is érvényes. Ha csak több idővel lenne megoldható,
az **nem megoldás** — a javítás feladja.

### 4. Minden javítási lépés okkal naplózott a change setbe

Strukturáltan, gépi olvashatóan (ADR 0256 §4). Ok nélküli változtatás tilos.

### 5. A javítás determinisztikus

Ugyanaz a hibás terv ugyanazt a javított tervet adja; nincs `Random`, nincs
óra-olvasás, a lépések sorrendje rögzített.

### 6. A javítás a jövőt rendezi át, a múltat nem

Az ADR 0256 §1 a repairre is vonatkozik: `completed` nap vagy blokk nem
módosítható.

## Következmények

- A tervező (Kör 12-től) számíthat rá, hogy érvénytelen terv nem jut el a
  felhasználóig.
- A felhasználó minden változtatásra kap magyarázatot — beleértve a
  rendszer saját javításait.
- A property-teszt a `PROPERTY_SEED` konvenció szerint fut: dev-loopban
  determinisztikus (42), CI-ban külön HARD lépés véletlen seeddel.

## Mérce

Az `E07-R11` §6.1 mérce-mátrixa, benne a súlyosság három kötelező cellájával
(csak `info`/`warning` → aktiválható / **pontosan egy `error`** → nem / `fatal`
→ nem, és a repair sem próbálkozik) és a valódi-sértés próbával: az iterációs
korlátot kivéve az **A2** property-cellának pirosnak (vagy timeoutosnak) kell
lennie.
