# ADR 0269 — A kihagyott nap nem termel lemaradást

**Státusz:** elfogadva (2026-08-15). Az Epic 7 folytonossági döntése.
Forrás: [`docs/sdd/08-epic-07-ai-practice-generator.md`](../sdd/08-epic-07-ai-practice-generator.md) Ch8 Kör 27.
Épít: [ADR 0256](0256-practice-plan-revisions-immutable-past.md),
[ADR 0258](0258-hard-and-soft-planning-constraints.md) §3 (hard napi maximum),
[ADR 0261](0261-skill-estimate-bounded-influence-and-unknown-state.md) §2.

## Kontextus

A tanuló ki fog hagyni napokat. A kérdés nem az, hogy megelőzhető-e, hanem
hogy a rendszer mit csinál utána.

A kézenfekvő megvalósítás átviszi a kimaradt gyakorlást a következő napra.
Két kihagyott nap után a keret duplája, három után a tanuló behozhatatlan
lemaradást lát — és feladja. Ez a **backlog-spirál**, és pontosan az ellenkezője
annak, amiért a terv készült.

## Döntés

### 1. A kihagyott nap nem növeli a következő napi keretet

Nincs átvitel. A következő nap kerete a tanuló által megadott hard maximum
marad (ADR 0258 §3).

*A tiltás:* „csak ma egy kicsit több". Ez a spirál első lépése.

### 2. A pihenőnap nem mulasztás

Az ütemező által kijelölt pihenőnap **teljesített** állapot. Ellenkező esetben
a rendszer megbüntetné a tanulót azért, mert betartotta a saját tervét.

### 3. Szünet alatt nem keletkezik lemaradás

A szüneteltetett terv nem termel kihagyott napokat, és a folytatás **új
revíziót** hoz létre korrigált dátumokkal (ADR 0256).

### 4. Hosszabb szünet után készültségi javaslat, nem folytatás a régi szinten

Több hét kihagyás után a régi becslés elavult — az ADR 0261 §2 `unknown`
elvének időbeli megfelelője. A rendszer felmérő/ráhangoló tervet javasol, nem
ott folytatja, ahol abbahagyták.

### 5. A szövegezés nem szégyenítő

Se „elmulasztottad", se „lemaradtál". Ez acceptance-cella, nem stílus-kérés:
a szégyenítő copy mérhetően nehezíti a visszatérést.

## Következmények

- A kihagyás következménye **újratervezés**, nem adósság.
- A „csak az elsődleges cél" újraütemezés adja a folytonosságot: a fontos
  átkerül, a többi elmarad.
- A visszatérő tanuló sikerélménnyel indul, nem kudarccal.

## Mérce

Az `E07-R27` §6.1 mérce-mátrixa, benne a kihagyás-hossz három kötelező
cellájával (egy nap → egyszerű újraütemezés, **nincs** keret-növelés / a
határon → készültségi javaslat / több hét → készültségi javaslat csökkentett
nehézséggel) és a valódi-sértés próbával: a kimaradt időt a következő napra
átvive az **A1** cellának pirosnak kell lennie.
