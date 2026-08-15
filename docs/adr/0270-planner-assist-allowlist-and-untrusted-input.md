# ADR 0270 — A modell javaslata allowlistelt, és a felhasználói szöveg nem utasítás

**Státusz:** elfogadva (2026-08-15). Az Epic 7 AI-integrációs döntése.
Forrás: [`docs/sdd/08-epic-07-ai-practice-generator.md`](../sdd/08-epic-07-ai-practice-generator.md) Ch8 Kör 28.
Épít: [ADR 0255](0255-deterministic-first-practice-planning.md) §2 (a modell
javasol, nem hajt végre), [ADR 0262](0262-catalog-snapshot-revisions-and-capability-truth.md)
§1 (csak létező forrás), [ADR 0263](0263-bounded-deterministic-plan-repair.md).

## Kontextus

Az `plannerAssistEnabled` mögött a rendszer nyelvi modellt hívhat magyarázatért
és javaslatokért. A modell kimenete **nem megbízható bemenet**: hivatkozhat
nem létező gyakorlatra, félreértheti a sémát, és a promptba került felhasználói
szöveg utasításnak látszhat.

## Döntés

### 1. A modell soha nem aktivál tervet

A javaslat a determinisztikus validátoron megy át (ADR 0263), és az aktiválás
felhasználói megerősítéshez kötött. Nincs olyan út, amelyen a modell kimenete
közvetlenül végrehajtott tervvé válik (ADR 0255 §2).

### 2. Csak allowlistelt azonosító fogadható el

A modell kizárólag **létező** goal-, skill- és jelölt-ID-t hivatkozhat.
Ismeretlen vagy kitalált azonosító → a javaslat elutasítva.

*A tiltás:* fuzzy illesztés a modell által kitalált névre. A rendszer
megkeresné a „leghasonlóbbat", és a tanuló mást gyakorolna, mint amit bárki
eldöntött — kitalált tartalom a tervben (ADR 0262 §1 rokona).

### 3. A felhasználói szabad szöveg adat, nem utasítás

A tanuló megjegyzése nem befolyásolhatja a modellnek adott instrukciót. A
prompt-szerkezet elkülöníti; a promptba ágyazott „felejtsd el az eddigieket"
típusú tartalom hatástalan.

### 4. A séma-sértés elutasítás, nem javítgatás

Ha a válasz nem illeszkedik a sémára, elutasítjuk. Nincs „kiolvassuk belőle,
ami használható" — az részleges, ellenőrizetlen adatot engedne be.

### 5. AI nélkül minden alapfunkció működik

Timeout, hálózati hiba, rate limit, kikapcsolt flag → a tervezés zavartalanul
fut, determinisztikus magyarázattal. A felhő hibája nem veszíthet draftot.
Ez az offline-first ígéret (SDD Ch8 §2.4) betartása.

## Következmények

- A `plannerAssistEnabled` rollout külön kockázati profilú döntés marad
  (adatvédelem, költség, hálózat) — nem csúszhat be a funkció-rollouttal
  (ADR 0255 §3).
- A magyarázat minősége mérhető: a determinisztikus és az AI-segített változat
  összevethető (`E07-R30` §5.5).
- Egy modell-hiba legrosszabb következménye egy **elutasított javaslat**, nem
  egy rossz terv.

## Mérce

Az `E07-R28` §6.1 mérce-mátrixa, benne a javaslat-érvényesség három kötelező
cellájával (séma-sértő vagy ismeretlen ID → elutasítva / séma-helyes és
allowlistelt → elfogadva **javaslatként**, aktiválás nélkül / a tanuló
elutasítja → nem lép életbe, auditálható) és a valódi-sértés próbával: fuzzy
ID-illesztést engedve az **A2** cellának pirosnak kell lennie.
