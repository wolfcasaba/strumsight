# E08-R14 — Achievement kiértékelő és haladás-projekció

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 14
- **Kör-azonosító:** `E08-R14`
- **Branch:** `<motor>/e08-r14-achievement-evaluator-and-projection`
- **Előfeltétel:** `E08-R13` merge-elve (achievement katalógus)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0311` — a szám FOGLALT. Az ADR-t a Claude írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R13 objective-típusait és az R03 főkönyv-felületét (a completion a főkönyvhöz kötődik) — ha az objective szignatúrája eltér, §0.0 revízió. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/application/achievement_evaluator.dart",
  "lib/features/gamification/application/achievement_index.dart",
  "lib/features/gamification/public.dart",
  "test/features/gamification/application/achievement_evaluator_test.dart",
  "docs/rounds/e08-r14-achievement-evaluator-and-projection.md",
]
gate_tests = [
  "test/features/gamification/application/achievement_evaluator_test.dart",
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

Kanonikus eseményekből **idempotensen** építs eredmény-haladást: egy achievement soha
nem oldódik fel kétszer, a haladás újraépíthető, és a kiértékelő nem pásztázza feleslegesen
a teljes katalógust.

## 2. Jelenlegi állapot — mért tények

- Az R13 szállította a típusos objective-eket és a katalógust; az R03 a főkönyvet, amelyhez a feloldás kötődik.
- `lib/features/gamification/application/achievement_*` **nem létezik**.
- Az R03 `append-if-absent` művelete a dedup technikai alapja — a feloldás EZEN keresztül idempotens.

## 3. Scope

**Benne van:** az achievementek indexelése esemény-típus és metrika szerint · egy esemény CSAK a
releváns objective-eket értékeli · count / distinct / threshold / compound haladás · a
feloldás **egyszeri** és a főkönyvhöz kötött · **korlátos** backfill később hozzáadott
achievementhez · ismeretlen objective **fail-closed**.

**NINCS benne (tilos):**

- A katalógus tartalmának módosítása (Kör 13) és a felület (Kör 15).
- Új jutalom-típus bevezetése — a nyugta az R06 policy-motorjából jön.
- `docs/adr/**` — az ADR 0311-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/application/achievement_evaluator.dart` | **ÚJ** — a kiértékelő |
| `lib/features/gamification/application/achievement_index.dart` | **ÚJ** — az esemény→objective index |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `test/features/gamification/application/achievement_evaluator_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések (ADR 0311)

### 5.1 A feloldás EGYSZERI, és a főkönyv dedupja garantálja

A feloldás jutalma az R03 főkönyvébe kerül `append-if-absent` művelettel, ahol a
forrás-azonosító az achievement azonosítója + a kiváltó esemény azonosítója. Az ismételt
kiértékelés így technikailag nem tud dupla jutalmat adni.

**NEM elfogadható gyengítés:** memóriabeli „már feloldottam” halmaz a főkönyv helyett.
Az app újraindítása után elvész, és a következő esemény újra feloldana.

### 5.2 A feloldás időbélyege STABIL

Az újraépítés ugyanazt a feloldási időpontot adja, mint az eredeti kiértékelés:
az időbélyeg a KIVÁLTÓ ESEMÉNYBŐL származik, nem a feldolgozás órájából.

**NEM elfogadható gyengítés:** `DateTime.now()` a feloldáskor. Egy projekció-újraépítés
átírná a felhasználó eredmény-előzményét.

### 5.3 INDEXELT kiértékelés — nem teljes katalógus-pásztázás

Egy esemény csak azokat az objective-eket értékeli, amelyek az adott esemény-típusra
és metrikára regisztráltak. A teljes katalógus végigpásztázása minden eseménynél a
katalógus növekedésével négyzetesen romlik.

### 5.4 Ismeretlen objective FAIL-CLOSED

Ha a kiértékelő olyan objective-típussal találkozik, amit nem ismer (régebbi
build, újabb katalógus), **nem** old fel semmit és jelzi a hibát — soha nem old fel
„biztos, ami biztos” alapon.

### 5.5 A backfill KORLÁTOS

Egy később hozzáadott achievement visszamenőleges kiértékelése korlátozott
ablakban történik (a korlát a konfigurációban él). A teljes előzmény minden
alkalmazás-indításkori újrapásztázása használhatatlanná tenné az indulást.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Ugyanaz az esemény kétszer feldolgozva EGY feloldást ad | `achievement_evaluator_test.dart` — idempotencia-cella |
| A2 | App-újraindítás szimulálása (üres memória, meglévő főkönyv) után sincs újra-feloldás | `achievement_evaluator_test.dart` |
| A3 | A feloldás időbélyege a kiváltó eseményből jön, és újraépítéskor VÁLTOZATLAN | `achievement_evaluator_test.dart` — stabilitás-cella |
| A4 | A haladás a főkönyvből TELJESEN újraépíthető | `achievement_evaluator_test.dart` |
| A5 | Egy esemény csak a releváns objective-eket értékeli (az érintett objective-ek száma mérhető) | `achievement_evaluator_test.dart` — index-cella |
| A6 | Ismeretlen objective esetén NINCS feloldás, és hiba keletkezik | `achievement_evaluator_test.dart` |
| A7 | A feloldáshoz jutalom-nyugta jön létre a főkönyvben | `achievement_evaluator_test.dart` |
| A8 | A backfill korlátos: a korlát fölötti előzmény nem kerül feldolgozásra | `achievement_evaluator_test.dart` — korlát-mátrix |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Memóriabeli feloldás-halmaz a főkönyv helyett | **A2** (az újraindítás-cella újra felold) |
| `DateTime.now()` a feloldás időbélyegének | **A3** |
| Minden esemény végigpásztázza a katalógust | **A5** (az érintett objective-ek száma a teljes katalógus) |
| Ismeretlen objective figyelmen kívül hagyva | **A6** |
| A backfill korlátlan | **A8** |
| A feloldás nem ír nyugtát | **A7** |

**A küszöb három kötelező cellája** (a backfill ablak korlátja (`backfillWindowDays`)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | egy `backfillWindowDays - 1` napos esemény | **feldolgozásra kerül** a backfillben |
| **rajta** (a küszöbön) | pontosan `backfillWindowDays` napos esemény | **MÉG feldolgozásra kerül** — a korlát a FELDOLGOZOTT oldalhoz tartozik (inkluzív) |
| a küszöb **fölött** | `backfillWindowDays + 1` napos esemény | **NEM kerül feldolgozásra**; ez a tény a diagnosztikában látszik, nem néma kihagyás |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** cseréld a főkönyv-alapú dedupot memóriabeli halmazra, futtasd a gate-et → az
**A2** (újraindítás) cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/application/achievement_evaluator_test.dart
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

1. `achievement_index.dart` — esemény-típus + metrika → objective index.
2. `achievement_evaluator.dart` — indexelt kiértékelés, objective-típusonként.
3. A feloldás főkönyvhöz kötése (`append-if-absent`, stabil forrás-azonosító).
4. Stabil feloldási időbélyeg a kiváltó eseményből.
5. Fail-closed ág ismeretlen objective-re.
6. Korlátos backfill, a kihagyás jelzésével.
7. A `public.dart` export-sorai; a valódi-sértés próba §10-be.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A memóriabeli dedup.** A fejlesztés közben tökéletesen működik, és az első app-újraindításnál duplikál (A2).
- **A `now()` időbélyeg.** Csak az első projekció-újraépítéskor derül ki, amikor a felhasználó eredmény-előzménye átíródik (A3).
- **A teljes pásztázás.** 25 achievementnél észrevehetetlen, 200-nál a gyakorlás végén akadás (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
