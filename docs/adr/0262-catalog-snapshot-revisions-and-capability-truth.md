# ADR 0262 — A jelölt csak létező forrásra mutat, a capability kimondott

**Státusz:** elfogadva (2026-08-15). Az Epic 7 katalógus-oldalának döntése.
Forrás: [`docs/sdd/08-epic-07-ai-practice-generator.md`](../sdd/08-epic-07-ai-practice-generator.md) Ch8 Kör 8.
Épít: [ADR 0255](0255-deterministic-first-practice-planning.md) (determinizmus),
[ADR 0259](0259-generation-request-versioning-and-draft-isolation.md) (provenance).

## Kontextus

A tervező csak abból válogathat, ami **ténylegesen végrehajtható**. A
katalógus két külön dolog metszete: mely gyakorlatok léteznek, és azok mit
tudnak (tempó-vezérlés, hurok, offline futtatás). A kettő külön ütemben
változik, és a terv évekig él (ADR 0256).

## Döntés

### 1. A jelölt csak létező, végrehajtható forrásra mutathat

Nincs szintetikus vagy placeholder jelölt. Ami bekerül a katalógus-pillanatképbe,
azt a végrehajtó réteg le tudja futtatni.

*Miért:* egy placeholder a tervezés fejlesztését kényelmesebbé teszi, és
végrehajthatatlan tervet szül a felhasználónál.

### 2. A nem támogatott capability KIMONDOTT, nem hiányzó

`unsupported` explicit érték, nem `null`/hiányzó mező. A hiányzó mezőt a
tervező „ismeretlennek" veszi, és megpróbálja használni — ugyanaz a
hibaosztály, mint az ADR 0261 §2 `unknown`-ja: a hiány és a nemleges válasz
nem ugyanaz.

### 3. A pillanatkép KÉT revíziót hordoz

**Katalógus-revízió** (mely gyakorlatok vannak) és **tartalom-revízió** (azok
tartalma). A terv provenance-e mindkettőt rögzíti, így később elkülöníthető,
hogy a terv változott, vagy a katalógus alatta.

### 4. A rendezés determinisztikus és stabil

Stabil rendezési kulcs — nem `hashCode`, nem `Map` iterációs sorrend, nem
beolvasási sorrend. Két azonos bemenetből bitre azonos sorrend (ADR 0255 §1).

### 5. Hiányzó kötelező metaadat: kimarad, jelzéssel

Skill-tag vagy előfeltétel nélküli gyakorlat nem kerül a pillanatképbe, és ez
figyelmeztetésként látszik. Default értékkel pótolni tilos — az kitalált adat
(ADR 0253 §3).

## Következmények

- A jelölt-választó (Kör 13) biztosan végrehajtható halmazból dolgozik.
- Az offline-first ígéret (SDD Ch8 §2.4) **metaadatból** teljesíthető, nem
  futásidejű találgatásból.
- A katalógus bővítése nem érinti a meglévő terveket: azok a saját
  revíziójukra hivatkoznak.

## Mérce

Az `E07-R08` §6.1 mérce-mátrixa, benne a metaadat-teljesség három kötelező
cellájával (teljes / **kötelező megvan, opcionális hiányzik → bekerül
`unsupported`-dal** / kötelező hiányzik → kimarad) és a valódi-sértés
próbával: a hiányzó kötelező metaadatot default értékkel pótolva az **A6**
cellának pirosnak kell lennie.
