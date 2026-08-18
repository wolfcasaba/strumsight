# E08-R17 — Napi küldetés-generátor

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 17
- **Kör-azonosító:** `E08-R17`
- **Branch:** `<motor>/e08-r17-daily-quest-generator`
- **Előfeltétel:** `E08-R16` merge-elve (quest domain)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0313` — a szám FOGLALT. Az ADR-t a Claude írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R16 `quest_schedule.dart` mezőit és a `lib/features/practice_generator/` napi terv-szerződését; ellenőrizd a `lib/features/vision/` és `lib/features/analyze/` elérhetőségi (permission/capability) jelzéseit — a generátor ezekre szűr. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/application/daily_quest_generator.dart",
  "lib/features/gamification/infrastructure/default_quest_catalog.dart",
  "lib/features/gamification/public.dart",
  "test/features/gamification/application/daily_quest_generator_test.dart",
  "docs/rounds/e08-r17-daily-quest-generator.md",
]
gate_tests = [
  "test/features/gamification/application/daily_quest_generator_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

Offline működő, **elérhető** és a napi tervhez illeszkedő küldetések generálása —
determinisztikusan: ugyanaz a nap + profil + katalógus-verzió UGYANAZT a küldetést adja.

## 2. Jelenlegi állapot — mért tények

- Az R16 szállította a típusos objective-et és az életciklust.
- `daily_quest_generator.dart` **nem létezik**.
- A `lib/features/vision/` kamerát, a felhő-funkciók fiókot igényelnek — a generátornak ezekre szűrnie kell.
- Az R11 bevezette a tervezett pihenőnapot — a generátornak ezt tisztelnie kell.

## 3. Scope

**Benne van:** a mai terv-objective-ek, a funkció-elérhetőség és az eszköz-képesség felhasználása ·
**legalább egy rövid** és **legfeljebb három** objective · pihenőnapon visszatérő/reflexiós,
**opcionális** küldetés · kamera/fiók/felhő igényű küldetés kizárása, ha nem elérhető ·
determinisztikus mag (seed) · tartalék (fallback) küldetés üres katalógusra és új felhasználóra.

**NINCS benne (tilos):**

- A terv MÓDOSÍTÁSA — a generátor olvas, nem ír (§5.3).
- Heti küldetés (Kör 18), challenge (Kör 19), felület (Kör 20).
- Engedélykérés kiváltása a generátorból — abszolút tilos.
- `docs/adr/**` — az ADR 0313-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/application/daily_quest_generator.dart` | **ÚJ** — a determinisztikus generátor |
| `lib/features/gamification/infrastructure/default_quest_catalog.dart` | **ÚJ** — a küldetés-katalógus |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `test/features/gamification/application/daily_quest_generator_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**` · `lib/features/practice_generator/**` (a terv ÉRINTETLEN)

## 5. Kötött architekturális döntések (ADR 0313)

### 5.1 DETERMINISZTIKUS: nap + profil-pillanatkép + katalógus-verzió → ugyanaz a küldetés

A generálás tiszta függvény ezen a három bemeneten. A magot (seed) ezekből
származtatjuk, és **dokumentáljuk**. Így a küldetés az app újraindítása után sem változik,
és a támogatás reprodukálni tudja.

**NEM elfogadható gyengítés:** `Random()` mag nélkül vagy `DateTime.now()` a generálásban.
A felhasználó a nap közepén más küldetést kapna, mint reggel.

### 5.2 NINCS ENGEDÉLY-KÉNYSZER: nem elérhető képesség → nem generálódik

Ha a kamera nincs engedélyezve, fiók nincs, vagy a felhő nem elérhető, az azt
igénylő küldetés **nem kerül be** a napi halmazba. A küldetés soha nem lehet burkolt
engedélykérés.

**NEM elfogadható gyengítés:** „generáljuk le, a felhasználó majd megadja az engedélyt”.
Ez sötét minta, és a küldetés végrehajthatatlanná válik (A2).

### 5.3 A generátor NEM ÍRJA FELÜL A TERVET

A Practice Generator (Epic 7) terve az elsődleges; a küldetés arra **hivatkozik**.
A generátor a terv fájljait nem módosítja — ez a tilos zóna és acceptance-cella (A6).

### 5.4 PIHENŐNAPON opcionális, visszatérő jellegű küldetés

Tervezett pihenőnapon nem kötelező gyakorlás-darálás generálódik, hanem
opcionális, reflexiós vagy könnyű visszatérő küldetés — az ADR 0290 §1 alkalmazása.

### 5.5 TARTALÉK küldetés mindig van

Üres katalógus, új felhasználó vagy hiányzó terv esetén is generálódik legalább
egy végrehajtható küldetés. Az üres napi lista a felület számára megkülönböztethetetlen a
hibától.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Ugyanaz a nap + profil + katalógus-verzió 100 futtatásra AZONOS küldetés-halmazt ad | `daily_quest_generator_test.dart` — determinizmus-cella |
| A2 | A halmaz mérete a `[1, 3]` sávban van, és van benne legalább egy RÖVID objective | `daily_quest_generator_test.dart` — méret-hármas |
| A3 | Nem elérhető kamera/fiók/felhő esetén az azt igénylő küldetés NEM generálódik | `daily_quest_generator_test.dart` — elérhetőség-mátrix |
| A4 | A generátor SEMMILYEN engedélykérést nem vált ki | `daily_quest_generator_test.dart` + review |
| A5 | Tervezett pihenőnapon opcionális, nem kötelező küldetés jön létre | `daily_quest_generator_test.dart` |
| A6 | A terv fájljai ÉRINTETLENEK | `git diff --stat` |
| A7 | Üres katalógus / új felhasználó esetén is van végrehajtható tartalék küldetés | `daily_quest_generator_test.dart` |
| A8 | A determinisztikus mag származtatása DOKUMENTÁLT (a §10-ben és kódkommentben) | review |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `Random()` mag nélkül | **A1** (a determinizmus-cella szór) |
| A kamera-küldetés engedély nélkül is generálódik | **A3** |
| A generátor a terv-fájlba ír | **A6** |
| Pihenőnapon kötelező gyakorlás generálódik | **A5** |
| Üres katalógusnál üres lista | **A7** |
| Négy objective generálódik | **A2** (a méret-hármas felső cellája) |

**A küszöb három kötelező cellája** (a napi objective-ek száma (a specifikált `[1, 3]` sáv)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | 0 objective (üres katalógus vagy új felhasználó) | **NEM elfogadható** — a tartalék küldetésnek be kell lépnie, tehát legalább 1 |
| **rajta** (a küszöbön) | pontosan 1, illetve pontosan 3 objective (a sáv két vége) | **ELFOGADVA** — a sáv MINDKÉT vége inkluzív |
| a küszöb **fölött** | 4 objective | **NEM elfogadható** — a generátornak vágnia kell 3-ra |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** cseréld a determinisztikus magot `Random()`-ra, futtasd a gate-et → az **A1**
determinizmus-cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/application/daily_quest_generator_test.dart
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. `default_quest_catalog.dart` — a küldetés-katalógus, képesség-igényekkel megjelölve.
2. A determinisztikus mag származtatása (nap + profil-pillanatkép + katalógus-verzió), dokumentálva.
3. `daily_quest_generator.dart` — szűrés elérhetőségre, majd determinisztikus választás.
4. A `[1, 3]` sáv betartása, legalább egy rövid objective-vel.
5. Pihenőnapi, opcionális küldetés ága.
6. Tartalék küldetés üres katalógusra és új felhasználóra.
7. A `public.dart` export-sorai; a valódi-sértés próba §10-be.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A nem determinisztikus generálás.** A tesztben egyszer lefut és jónak látszik; a felhasználónál a nap közben cserélődik a küldetés (A1).
- **A burkolt engedélykérés.** „Majd megadja” — sötét minta, és végrehajthatatlan küldetést ad (A3).
- **Az üres lista.** A felület számára megkülönböztethetetlen a hibától; a tartalék küldetés nem opcionális (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
