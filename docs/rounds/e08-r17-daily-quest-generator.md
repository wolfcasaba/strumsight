# E08-R17 — Napi küldetés-generátor

- **Státusz:** PREFLIGHT COMPLETE (2026-08-21, újramérve: `main @ d5701b61`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 17
- **Kör-azonosító:** `E08-R17`
- **Branch:** `<motor>/e08-r17-daily-quest-generator`
- **Előfeltétel:** `E08-R16` merge-elve (quest domain)
- **Brief szerzője:** Claude (Opus 5)
- **Foglalóval kiosztott ADR:** `ADR 0384`. Az ADR-t az orchestrátor írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R16 `quest_schedule.dart` mezőit és a `lib/features/practice_generator/` napi terv-szerződését; ellenőrizd a `lib/features/vision/` és `lib/features/analyze/` elérhetőségi (permission/capability) jelzéseit — a generátor ezekre szűr. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

### 0.0 Pre-flight mérés és brief-revízió (2026-08-21)

- A kötelező `tools/round-slots.py reserve-adr --round E08-R17` futás
  `0384`-et adott. Az előre írt `0313` már az elfogadott kör-landoló ADR,
  ezért változatlan marad; a jelen kör döntése az új `0384` számot kapja.
- A quest schedule tényleges mezői: `generationEpochDay`,
  `timezoneOffsetMinutes`, pozitív `catalogVersion`, UTC `expiresAt`; az aktív
  felső határ exkluzív (`QuestSchedule.isActiveAt`).
- A terv tényleges pihenőnapi útja
  `ScheduleDecisionReason.restDay.code` → `TodayPlanMode.restDay`
  (`today_plan_controller.dart:85-93`). A generátor caller-fed, immutable
  napi terv-pillanatképet olvas; nem szerez repositoryt és nem módosít tervet.
- A kamera permission contract külön read-only `currentState()` és mutáló
  `request()` metódust ad (`camera_permission.dart:88-95`). A generátor egyik
  permission/capability gatewayt sem hívja: explicit availability booleánokat
  kap a hívótól. Az Analyze publikus contractban nincs külön permission API.
- **Visszakeresett előzmény:** a szűkített RAG-találatok közül az
  `adr/0382` ([ADR 0382](../adr/0382-quest-objective-and-lifecycle-contract.md))
  rögzíti a quest instance/schedule contractot, [L384](../LESSONS.md#l384)
  (`lessons/L384`) pedig bizonyítja, hogy az ismétlődő katalógus-definíció és a napi példány
  identityje nem mosható össze. Az [ADR 0352](../adr/0352-qualified-day-planned-rest-and-recovery-policy.md)
  megerősíti, hogy a planned rest nem implicit gyakorlási kötelezettség.
  A permission-kényszerre nem került elő ennél specifikusabb korábbi halt.
- A `[1, 3]` határokat `python3 -c 'print(0 < 1, 1 <= 3, 4 > 3)'` számolta:
  `True True True`; a 0/1/3/4 cellák a §6.1-ben maradnak kötelezők.

**Kockázat = high, indoklás:** a kör permission- és cloud-availability
határt modellez. Egy hibás szűrés végrehajthatatlan küldetéssel burkolt
engedélykérést okozhat, ezért fail-closed availability-mátrix és független
security review kötelező akkor is, ha a diff nem érint platform adaptert.

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
- A kamera jelenlegi olvasási contractja `CameraPermissionGateway.currentState()`;
  a `request()` külön, explicit user-action út, amelyet a generátor nem hívhat.
- Az R11 pihenőnapját a production út
  `ScheduleDecisionReason.restDay.code` → `TodayPlanMode.restDay` alakban adja.

## 3. Scope

**Benne van:** a mai terv-objective-ek, a funkció-elérhetőség és az eszköz-képesség felhasználása ·
**legalább egy rövid** és **legfeljebb három** objective · pihenőnapon visszatérő/reflexiós,
**opcionális** küldetés · kamera/fiók/felhő igényű küldetés kizárása, ha nem elérhető ·
determinisztikus mag (seed) · tartalék (fallback) küldetés üres katalógusra és új felhasználóra.

**NINCS benne (tilos):**

- A terv MÓDOSÍTÁSA — a generátor olvas, nem ír (§5.3).
- Heti küldetés (Kör 18), challenge (Kör 19), felület (Kör 20).
- Engedélykérés kiváltása a generátorból — abszolút tilos.
- `docs/adr/**` — az ADR 0384-et az orchestrátor írja a pre-flightban.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/application/daily_quest_generator.dart` | **ÚJ** — a determinisztikus generátor |
| `lib/features/gamification/infrastructure/default_quest_catalog.dart` | **ÚJ** — a küldetés-katalógus |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `test/features/gamification/application/daily_quest_generator_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**` · `lib/features/practice_generator/**` (a terv ÉRINTETLEN)

## 5. Kötött architekturális döntések (ADR 0384)

### 5.0 Típusos bemenet és kimenet

A generátor egy immutable, caller-fed napi snapshotot kap: explicit schedule,
stabil profile snapshot key, opcionális terv-objective-ek, planned-rest jelző,
valamint kamera/fiók/felhő availability booleánok. A snapshot előállítása és a
gatewayk meghívása scope-on kívüli composition feladat; a generátor nem olvas
órát, repositoryt, permission plugint vagy hálózatot.

A katalóguselem a stabil objective és reward mellett hordozza a szükséges
capabilityket, a rövidség és a pihenőnapi alkalmasság jelzőjét. A generált
eredmény a verziózott `QuestDefinition` mellett explicit `isOptional`
metaadatot ad; planned rest esetén ez mindig igaz. A visszaadott lista és a
katalógus nézete nem módosítható.

### 5.1 DETERMINISZTIKUS: nap + profil-pillanatkép + katalógus-verzió → ugyanaz a küldetés

A generálás tiszta függvény a teljes snapshoton. A stabil seed material a
`generationEpochDay`, a profile snapshot key és a `catalogVersion` egyértelmű,
UTF-8 reprezentációja; a rendezési kulcs ehhez és a stabil katalógus-ID-hoz
kötött, dokumentált 64 bites FNV-1a hash. Nem használható a Dart
`String.hashCode`, mert annak cross-runtime stabilitása nem contract. Így
ugyanaz a snapshot app-újraindítás után sem változik, és a támogatás
reprodukálni tudja.

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
| A1 | Ugyanaz a teljes immutable snapshot 100 futtatásra AZONOS, azonos sorrendű küldetés-halmazt ad; a seednek kipinnelt golden értéke van | `daily_quest_generator_test.dart` — determinizmus + golden-seed cella |
| A2 | A halmaz mérete a `[1, 3]` sávban van, és van benne legalább egy RÖVID objective | `daily_quest_generator_test.dart` — méret-hármas |
| A3 | Nem elérhető kamera/fiók/felhő esetén az azt igénylő küldetés NEM generálódik | `daily_quest_generator_test.dart` — elérhetőség-mátrix |
| A4 | A generátor SEMMILYEN gatewayt vagy engedélykérést nem birtokol/hív; API-ja csak caller-fed adatokból áll | `daily_quest_generator_test.dart` + import/API review |
| A5 | Tervezett pihenőnapon opcionális, nem kötelező küldetés jön létre | `daily_quest_generator_test.dart` |
| A6 | A terv fájljai ÉRINTETLENEK, és a generátor csak a practice-generator `public.dart` határát használhatja, ha onnan típust importál | gépi scope-audit + import review |
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
| `String.hashCode` vagy más runtime-függő seed kerül be | **A1** golden-seed cella |
| Planned-rest eredményről lemarad az optional metaadat | **A5** |
| A visszaadott lista vagy katalógus módosítható | **A2/A7** immutability cella |

**A küszöb három kötelező cellája** (a napi objective-ek száma (a specifikált `[1, 3]` sáv)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | 0 objective (üres katalógus vagy új felhasználó) | **NEM elfogadható** — a tartalék küldetésnek be kell lépnie, tehát legalább 1 |
| **rajta** (a küszöbön) | pontosan 1, illetve pontosan 3 objective (a sáv két vége) | **ELFOGADVA** — a sáv MINDKÉT vége inkluzív |
| a küszöb **fölött** | 4 objective | **NEM elfogadható** — a generátornak vágnia kell 3-ra |

A hármas tömören: **alatt** → fallbackkel korrigál · **rajta** → elfogad · **fölött** → háromra vág.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próbák (KÖTELEZŐK, §10-ben dokumentálva):** (1) cseréld a
stabil FNV seedet `Random()`-ra, futtasd a célzott tesztet → az **A1**
determinizmus/golden cellának PIROSNAK kell lennie; (2) fordítsd meg a kamera
availability ellenőrzését → az **A3** mátrix legyen PIROS; majd mindkét
mutációt állítsd vissza.

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

- `lib/features/gamification/infrastructure/default_quest_catalog.dart`:
  típusos, stabil azonosítójú napi quest-katalógust, capability-követelményt és
  lokális alap-katalógust vezet be; a katalógus nézete nem módosítható.
- `lib/features/gamification/application/daily_quest_generator.dart`:
  caller-fed snapshotból, gateway-, óra-, repository- és hálózathívás nélkül
  szűr, majd legfeljebb három questet választ. A rendezés seedje pontosan
  `generationEpochDay|profileSnapshotKey|catalogVersion`; a seed és a stabil
  catalog-ID UTF-8 bytejaira alkalmazott 64-bites FNV-1a adja a sorrendet.
  Hiányzó terv, új profil, üres/alkalmatlan katalógus vagy rövid objective
  hiánya a helyi, rövid fallbackhez vezet. Planned rest esetén csak
  rest-eligible, `isOptional = true` eredmény jöhet létre.
- `lib/features/gamification/public.dart`: exportálja a napi quest generátor
  és katalógus publikus contractját.
- `test/features/gamification/application/daily_quest_generator_test.dart`:
  A1–A3, A5 és A7 mércék: 100 futásos determinisztika és golden FNV érték,
  0/1/3/4 határ, rövid objective, immutable nézetek, capability-mátrix,
  pihenőnap és fallback.

Futtatott parancsok és tényleges eredmény:

- `dart format lib/features/gamification/application/daily_quest_generator.dart lib/features/gamification/infrastructure/default_quest_catalog.dart lib/features/gamification/public.dart test/features/gamification/application/daily_quest_generator_test.dart` → 4 fájl formázva, 0 további változás.
- `flutter test test/features/gamification/application/daily_quest_generator_test.dart` → `6` teszt zöld.
- Valódi-sértés 1: a stabil FNV kulcsot `Random().nextInt(...)`-re cserélve
  ugyanaz a célzott teszt A1-ben piros lett (eltérő quest-sorrend); visszaállítva.
- Valódi-sértés 2: a kamera availability ellenőrzését megfordítva ugyanaz a
  célzott teszt A3-ban piros lett (`daily_camera` bekerült); visszaállítva.
- Kötelező gate: `tools/round-gate.sh test/features/gamification/application/daily_quest_generator_test.dart` → format, analyze, célzott teszt (6/6), architecture, secrets és l10n mind zöld.

Nem futtatott ellenőrzés: a teljes suite, randomizált property gate és APK
CI-orchestrátor feladat; CI-dispatch, PR és merge implementer-scope-on kívül
maradt. Eltérés nincs.

## 11. Review — a Claude tölti ki
