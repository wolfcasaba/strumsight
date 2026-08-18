# E08-R25 — Song Trainer és setlist integráció

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 25
- **Kör-azonosító:** `E08-R25`
- **Branch:** `<motor>/e08-r25-song-trainer-and-setlist-integration`
- **Előfeltétel:** `E08-R24` merge-elve (practice/learn integráció)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** nincs — ez a kör nem hoz kötött architekturális döntést.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/songs/` és `lib/features/song_trainer/` TÉNYLEGES public szerződését (szakasz, hurok, teljes dal, setlist eredmények), és ellenőrizd, hogyan azonosítja az importált dalokat — a privacy-safe azonosító ebből származik. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/songs/application/gamification_song_adapter.dart",
  "test/features/gamification/integration/song_reward_flow_test.dart",
  "docs/rounds/e08-r25-song-trainer-and-setlist-integration.md",
]
gate_tests = [
  "test/features/gamification/integration/song_reward_flow_test.dart",
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

Jutalmazd a dalgyakorlást **szülő-gyermek dedupolással** és személyes rekord
mérföldkövekkel — jutalom-infláció nélkül, és **privacy-safe** dal-azonosítóval.

## 2. Jelenlegi állapot — mért tények

- Az R06 §5.3 explicit `parentEventId` alapján kezeli a szülő-gyermek viszonyt — ez a kör ezt használja.
- A `lib/features/songs/` és `lib/features/song_trainer/` (Epic 3) szakasz-, hurok-, teljes dal- és setlist-eredményeket ad.
- Az importált dal címe és a fájl neve **felhasználói tartalom** — nem kerülhet azonosítóként a főkönyvbe.
- `test/features/songs/` MA zöld — elbukása `blocked`.

## 3. Scope

**Benne van:** szakasz, hurok, teljes dal és setlist befejezés esemény · a gyermek események
összekötése szülő session-azonosítóval · a teljes dal bónusza NEM duplikálja a szakaszok
alap-jutalmát · tempó-mérföldkő és tiszta felvétel esemény · ugyanazon felvétel újrajátszása
NEM ad második jutalmat · importált dalnál **privacy-safe** azonosító.

**NINCS benne (tilos):**

- A `lib/features/song_trainer/**` és a `lib/features/songs/` többi fájljának módosítása.
- A dal-haladás (`song progress`) logikájának átvétele — az a `songs` feature saját mérőszáma.
- A gamification belső fájljainak importálása (csak `public.dart`).

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/songs/application/gamification_song_adapter.dart` | **ÚJ** — a dal-adapter |
| `test/features/gamification/integration/song_reward_flow_test.dart` | a §6 cellái |
| `docs/rounds/e08-r25-song-trainer-and-setlist-integration.md` | a §10 handoff |

**Tilos zóna:** `lib/features/songs/` MINDEN más fájlja · `lib/features/song_trainer/**` · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**` · `lib/features/gamification/` belső (nem `public.dart`) fájljai

## 5. Kötött architekturális döntések

### 5.1 A TELJES DAL BÓNUSZ, NEM ÖSSZEG

Ha a felhasználó végigjátssza a dalt, a teljes dal esemény **bónuszt** ad — nem
kapja meg újra a szakaszok alap-jutalmát. A szakaszok gyermek események, a teljes dal a
szülő; a dedup az R06 `parentEventId` mechanizmusán megy.

**NEM elfogadható gyengítés:** a szakasz-jutalmak összeadása és a bónusz hozzáadása.
Ez jutalom-infláció: ugyanaz a gyakorlás kétszer fizet.

### 5.2 AZ ÚJRAJÁTSZÁS UGYANAZZAL AZ EREDMÉNNYEL NEM AD ÚJ JUTALMAT

A felvétel (take) azonosítója stabil; ugyanazt az eredményt újra megnyitva vagy
újrajátszva a főkönyv `append-if-absent` művelete blokkol. Az ÚJ felvétel természetesen
új esemény.

### 5.3 PRIVACY-SAFE dal-azonosító

Az importált dal címe, előadója vagy fájlneve **nem** kerül a főkönyvbe. Helyette
stabil, nem visszafejthető azonosító (a dal belső azonosítójából származtatva).

**NEM elfogadható gyengítés:** „csak a cím, hogy a felületen ki tudjuk írni”. A főkönyv
szinkronizálható (Kör 28); a felhasználó dallistája nem mehet fel.

### 5.4 A SZEMÉLYES REKORD MAGYARÁZHATÓ

A tempó-mérföldkő megmondja, mihez képest rekord (előző legjobb, mikor). A
puszta „Új rekord!” üzenet nem ellenőrizhető.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az összes szakasz + a teljes dal együtt NEM ad kétszeres alap-jutalmat | `song_reward_flow_test.dart` — infláció-cella |
| A2 | A gyermek események szülő session-azonosítót hordoznak | `song_reward_flow_test.dart` |
| A3 | Ugyanazon felvétel újrajátszása NEM ad második jutalmat | `song_reward_flow_test.dart` |
| A4 | Új felvétel ÚJ jutalmat ad (a dedup nem zárja ki a valódi új gyakorlást) | `song_reward_flow_test.dart` |
| A5 | A főkönyvben NEM szerepel dalcím, előadó vagy fájlnév | `song_reward_flow_test.dart` — privacy-cella |
| A6 | A tempó-mérföldkő megadja az előző legjobbat és annak idejét | `song_reward_flow_test.dart` |
| A7 | A dal-haladás (`songs` feature) VÁLTOZATLAN | a `test/features/songs` suite a §7 gate-ben |
| A8 | A folyamat offline teljes | `song_reward_flow_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A szakasz-jutalmak összeadódnak a teljes dal bónuszához | **A1** |
| Az újrajátszás új eseményt generál | **A3** |
| A dalcím bekerül a főkönyvbe | **A5** |
| A rekord nem adja meg az előző legjobbat | **A6** |
| Az adapter átveszi a dal-haladás számítását | **A7** |
| A gyermek esemény szülő nélkül megy | **A2** |

**A küszöb három kötelező cellája** (a szülő-gyermek dedup: a teljes dal bónusza a szakaszok alap-jutalmához képest):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | csak szakaszok játszva (nincs teljes dal) | a szakaszok **alap-jutalma** jár, bónusz nincs |
| **rajta** (a küszöbön) | minden szakasz + a teljes dal ugyanabban a sessionben | a szakaszok alap-jutalma **EGYSZER** + a teljes dal **bónusza** — összesen NEM a kétszerese |
| a küszöb **fölött** | teljes dal szakasz-gyakorlás nélkül | a teljes dal alap-jutalma + bónusza; a nem játszott szakaszokért nem jár semmi |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** add hozzá a szakasz-jutalmakat a teljes dal bónuszához, futtasd a gate-et → az
**A1** infláció-cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/integration/song_reward_flow_test.dart test/features/songs
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

1. `gamification_song_adapter.dart` — a négy eseménytípus a `songs` public szerződéséből.
2. Szülő session-azonosító a gyermek eseményeken.
3. A teljes dal bónusz-jellegének biztosítása (nem összeg).
4. Stabil felvétel-azonosító az újrajátszás dedupjához.
5. Privacy-safe dal-azonosító származtatása.
6. Magyarázható tempó-mérföldkő.
7. A valódi-sértés próba §10-be; `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A jutalom-infláció.** A szakasz+teljes dal összeadása a legkézenfekvőbb implementáció, és ugyanazt a gyakorlást kétszer fizeti (A1).
- **A dalcím a főkönyvben.** Kényelmes a felület számára, és a Kör 28 szinkronjával a felhasználó dallistája elhagyná az eszközt (A5).
- **A dal-haladás átvétele.** A `songs` feature saját mérőszáma; az átvétel scope-sértés és regresszió (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
