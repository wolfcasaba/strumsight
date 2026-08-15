# ADR 0259 — A generálási kérés determinisztikusan hash-elhető, a draft izolált

**Státusz:** elfogadva (2026-08-15). Az Epic 7 request- és draft-kezelésének döntése.
Forrás: [`docs/sdd/08-epic-07-ai-practice-generator.md`](../sdd/08-epic-07-ai-practice-generator.md) Ch8 Kör 4.
Épít: [ADR 0255](0255-deterministic-first-practice-planning.md) (determinizmus),
[ADR 0256](0256-practice-plan-revisions-immutable-past.md) (immutable múlt),
[ADR 0257](0257-planner-typed-ids-and-stable-enum-codes.md).

## Kontextus

A generálás bemenete összetett: célok, heti elérhetőség, hard/soft korlátok,
mód és horizont. Ez a bemenet két okból is dokumentummá kell váljon:

1. **Reprodukálhatóság.** Az ADR 0255 §1 szerint ugyanaz a bemenet ugyanazt a
   tervet adja. Ehhez a bemenetet azonosítani kell tudni.
2. **Folytathatóság.** A setup wizard több képernyős; az app bezárása nem
   veszejtheti el a félkész bemenetet.

## Döntés

### 1. A seed a kérésből SZÁMÍTOTT, nem véletlen

A determinisztikus seed a kérés tartalmának stabil hash-e. `Random` vagy a
létrehozási időbélyeg bekeverése tilos — az elrontaná a reprodukálhatóságot,
és a „miért ezt a tervet kaptam?" kérdés megválaszolhatatlan lenne.

### 2. A hash kanonikus: a jelentésen alapul, nem a mezősorrenden

A hash bemenete rendezett kulcsokból és normalizált értékekből épül. A
szerializáció átrendezése **nem** változtathatja meg a hash-t — különben egy
ártatlan refaktor minden korábbi tervet „megváltozottnak" mutatna.

### 3. A draft és az aktív terv KÜLÖN tárolóhelyen él

A wizard félkész állapota soha nem írhatja felül a végrehajtott tervet.
Külön kulcs/fájl, nem közös rekord státusz-mezővel — az utóbbinál egy hibás
írás az aktív tervet vinné el.

### 4. A sérült draft kontrollált hiba, az újabb séma elutasítás

Olvashatatlan draft → `AppResult` failure, és a draft eldobható; az app nem
omlik össze. A kódnál **újabb** `schemaVersion` → hiba, nem „best effort"
olvasás. Ugyanaz az elv, mint az ADR 0257 §4 ismeretlen enum-kódjánál: a
hiányzó vagy ismeretlen bemenet nem álcázható sikeres eredménynek.

## Következmények

- A terv magyarázhatóvá válik: a kérés hash-e a terv provenance-ének része
  lesz (a későbbi körökben).
- A migráció mindig **felfelé** történik; a lefelé-kompatibilitás
  szándékosan nincs — egy régebbi kliens nem próbálja értelmezni az újabb
  adatot.
- A wizard megszakítás után folytatható, és a draft törlése idempotens.

## Mérce

Az `E07-R04` §6.1 mérce-mátrixa, benne a schema version három kötelező
cellájával (régebbi → migrálódik / aktuális / **újabb → kontrollált hiba**) és
a valódi-sértés próbával: az aktuális időt a seed-hash bemenetébe keverve az
**A2** cellának pirosnak kell lennie.
