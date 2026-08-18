# ADR 0315 — Halt-főkönyv: minden ismétlődő halt-osztályhoz tartozzon őrteszt

- **Státusz:** elfogadva (2026-08-18)
- **Kontextus-ADR-ek:** [`0112`](0112-self-healing-rounds.md) (önjavítás), [`0312`](0312-knowledge-rag.md) (tudás-index), [`0314`](0314-gate-step-taxonomy.md)

## 1. Probléma

A lánc tanul: minden mért tanulság bekerül a `docs/LESSONS.md`-be, és a jó
körökben őrtesztet is kap (mérve: L312 → `test_slot_lock_inheritance.py`,
L313 → `AmbientEnvironmentLeakTest`). Ez ma **fegyelem kérdése**, nem
rendszeré — és a fegyelem mérve elromlik: az `E07-R23/H6` halt-rekord szerint
ugyanaz a hibaosztály **másodszor** fordult elő („2. előfordulás"), és az
`E99-R14` H3 gyökéroka órákkal korábban le volt írva, mégis belefutott egy kör.

Ez pontosan az a hurok, amit az iparág „trace → eval case" néven zár be: a
bukott futásból automatikusan regressziós eset lesz, különben ugyanaz a hiba
visszatér ([agent observability 2026](https://www.braintrust.dev/articles/agent-observability-complete-guide-2026)).

## 2. Döntés

Bevezetünk egy **halt-főkönyvet** (`tools/halt-ledger.py`), ami a
`.pipeline/halted-*.txt` rekordokból és a `docs/LESSONS.md`-ből összeállítja:

| halt-osztály | előfordulás | hivatkozott őrteszt | állapot |
|---|---|---|---|

Az „őrteszt" gépi hivatkozás: a leckében egy `**Őrteszt:** <útvonal>::<név>`
sor. A főkönyv jelentést ír, és **figyelmeztet** (nem blokkol) minden olyan
halt-osztályra, amiből **kettő vagy több** előfordulás van, és nincs hozzá
hivatkozott őrteszt.

### 2.1 Miért figyelmeztet és nem blokkol

Mert a blokkolás rossz helyen állítaná meg a láncot. A halt lezárása az
önjavítás kimenete; ha ezt egy hiányzó őrteszt blokkolja, a lánc **több**
emberi döntést kérő állásba kerül — pontosan az, amit a 42 órás állás után
csökkenteni akarunk. A blokkoló szintre emelés külön, mért döntés, azután, hogy
a jelentésből látszik, hány osztály érintett.

## 3. Amit ez a döntés NEM tesz

- Nem módosítja az önjavítás menetét (ADR 0112) és a halt-kódokat.
- Nem ír automatikusan tesztet — a főkönyv **hiányt mutat**, nem tölt ki.
- Nem szigorítja a CI-kaput: a jelentés artefaktum, nem gate-lépés.

## 4. Következmények

- A `docs/LESSONS.md` konvenciója bővül egy géppel olvasható sorral; a régi
  leckék visszamenőleg NEM kötelesek (a főkönyv hiányként mutatja, nem hibaként).
- A jelentés bemenete a tudás-index halt-korpuszának is jó forrása (ADR 0312).
