# E08-R04 — Activity outbox és megbízható feldolgozás

- **Státusz:** IN PROGRESS — pre-flight revízió 1 (2026-08-19, `main @ bf6f9507`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 4
- **Kör-azonosító:** `E08-R04`
- **Branch:** `minimax/e08-r04-activity-outbox-and-reliable-processing`
- **Előfeltétel:** `E08-R03` merge-elve (reward ledger)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0333` — a `tools/round-slots.py reserve-adr --round E08-R04`
  által foglalt szám. Az ADR-t az orchestrátor írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R03 `reward_ledger_repository.dart` tényleges felületét (append-if-absent szignatúra) — az ingestor erre hív; és ellenőrizd a `lib/features/diagnostics/` meglévő felületét, mert a karantén ott lesz látható. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/application/activity_event_ingestor.dart",
  "lib/features/gamification/data/activity_outbox_repository.dart",
  "lib/features/gamification/data/local_activity_outbox_repository.dart",
  "lib/features/gamification/public.dart",
  "test/features/gamification/application/activity_ingestor_test.dart",
  "docs/rounds/e08-r04-activity-outbox-and-reliable-processing.md",
]
gate_tests = [
  "test/features/gamification/application/activity_ingestor_test.dart",
]
native_gate = false
```

## §0.0 Pre-flight revízió 1 — mért feloldások

- **ADR-foglalás.** A briefben korábban szereplő `0302` nem volt használható:
  `.pipeline/inflight/adr/0302` szerint az `E07-R15` foglalta. A foglaló
  `0333`-at adott; a döntés ezért [`ADR 0333`](../adr/0333-activity-outbox-reliable-processing.md).
- **A ledger tényleges szerződése.** A mért R03-felület
  `RewardLedgerRepository.appendIfAbsent(RewardLedgerEntry) -> Future<bool>`;
  nincs `LearningActivityEvent -> RewardLedgerEntry` átalakító és a
  `RewardLedgerEntry` kötelező XP/policy/ok mezőket kér. Az ingestor ezért
  **nem számol és nem dönt** jutalmat: a hívó egy, az esemény `eventId`-jével
  azonos `sourceEventId`-jű kész bejegyzést ad át az enqueue-hoz. Eltérő ID
  argument error; a későbbi R05 policy lesz a hívó előállítója. Ez az
  [`ADR 0301`](../adr/0301-reward-ledger-append-only-idempotency.md) atomikus
  dedupját használja, nem kerüli meg.
- **Karantén láthatósága.** A mért `lib/features/diagnostics/` ma csak Lab UI- és
  upload-szerződést exportál; outbox-state contract nincs. Ebben a körben a
  `ActivityOutboxRepository` lekérdezhető karantén-listája a diagnosticsnak
  szánt adatforrás, UI/provider-bekötés nélkül.
- **Retry és kapacitás.** A repository konstruktorban kötelező, pozitív
  `capacity` és `maxAttempts` értéket kap; nincs rejtett product-küszöb. A
  kapacitás a pending rekordok maximuma: `capacity + 1` enqueue a legrégebbi
  pending rekordot karanténba helyezi és az újat megtartja. A ledger-írási
  hiba növeli a kísérletszámot; a határt elérő rekord karanténba kerül.
- **Hívási/tulajdonlási lánc.** `rg -n "\\.acquire\\(" lib/` nem adott
  gamification-találatot; a körnek nincs lease/lock tulajdonosa. A lokális
  repository explicit hívó-adta `KeyValueStore`-t és `AppLogger`-t kap,
  ugyanúgy, mint R03; nem nyit platform-erőforrást.
- **Visszakeresés (S8).** A kötelező, szűkített RAG a `lessons,halts,adr`
  korpuszban az [`ADR 0301`](../adr/0301-reward-ledger-append-only-idempotency.md)
  idempotens Future-tail döntését és `L340` gate-log hamis pozitívját hozta;
  a teljes korpusz megerősítette az R04 briefet. Közvetlen korábbi outbox-
  implementációs lecke nincs. A review ezért saját izolált gate-futtatást
  végez, nem a `gate_shape` önjelentését fogadja el.

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

A gyakorlási eredmény mentése és a jutalom feldolgozása közötti hibákat **adatvesztés
nélkül** kezeld — és úgy, hogy a jutalom-feldolgozás hibája SOHA ne tegye sikertelenné
magát a gyakorlási sessiont.

## 2. Jelenlegi állapot — mért tények

- Az R03 létrehozta a főkönyvet atomikus append-if-absent művelettel.
- `lib/features/gamification/application/` **nem létezik** — ez a kör hozza létre.
- A projekt MÉRT hibaosztálya (`CLAUDE.md`, „Critical build gotchas”): a `try/catch`-be fojtott írás néma no-opot ad, és a felület sikert mutat. A settings-szinkron (kör 17) ezért csak szerver-megerősítés után jelöl szinkronizáltnak.
- `lib/features/diagnostics/` létezik — a karantén-állapotnak itt kell láthatóvá válnia (a felület bekötése későbbi kör).

## 3. Scope

**Benne van:** korlátos (bounded) lokális outbox a függőben lévő eseményeknek · a feature-eredmény
mentése UTÁN enqueue, majd feldolgozás · a feldolgozási hiba elszigetelése a session
eredményétől · újrapróbálkozás app-indításkor és explicit `drain()` művelettel ·
ismeretlen vagy sérült esemény **karanténba** helyezése · végtelen retry-hurok kizárása.

**NINCS benne (tilos):**

- Bármely feature bekötése (`practice`, `learn`, `songs`) — Kör 24–26.
- XP-számítás, eligibility — Kör 5–6. Az ingestor a főkönyvbe ír, a policy-t még nem hívja.
- Diagnosztikai **felület** — ez a kör csak a lekérdezhető karantén-állapotot adja.
- Hálózati szinkron — Kör 28.
- `docs/adr/**` — az ADR 0302-t a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/application/activity_event_ingestor.dart` | **ÚJ** — az enqueue → feldolgozás vezérlő |
| `lib/features/gamification/data/activity_outbox_repository.dart` | **ÚJ** — az interfész |
| `lib/features/gamification/data/local_activity_outbox_repository.dart` | **ÚJ** — a korlátos lokális sor |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `test/features/gamification/application/activity_ingestor_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések (ADR 0302)

### 5.1 A session eredménye NEM függ a jutalomtól

A sorrend kötött: **előbb** a feature elmenti a saját eredményét, **utána** kerül
esemény az outboxba. Az outbox vagy a feldolgozás bármely hibája a session sikerét
érintetlenül hagyja.

**NEM elfogadható gyengítés:** a jutalom-feldolgozás beemelése a session mentési
tranzakciójába „a konzisztencia kedvéért”. Onnantól egy gamifikációs hiba elveszi a
felhasználó gyakorlását — a termék magját áldozzuk fel a jutalomrétegért.

### 5.2 Az újrapróbálkozás IDEMPOTENS — az R03 dedupjára támaszkodik

A drain többször is lefuthat ugyanarra az eseményre (app-indítás, kézi drain,
crash utáni helyreállítás). A dupla jutalmat az R03 `append-if-absent`-je zárja ki,
NEM az outbox „óvatossága”. Az ingestor tehát bátran újrapróbálhat.

**NEM elfogadható gyengítés:** az esemény törlése az outboxból a feldolgozás ELŐTT
(„hogy ne duplikáljon”). Az crash esetén néma adatvesztés — a törlés a sikeres
főkönyv-írás UTÁN történik.

### 5.3 Sérült vagy ismeretlen esemény KARANTÉNBA kerül, nem tűnik el

A nem dekódolható esemény nem törlődik és nem blokkolja a sort: külön karantén-
állapotba kerül, ahonnan lekérdezhető és diagnosztizálható. Enélkül egyetlen rossz
esemény vagy megállítja a teljes feldolgozást, vagy némán elvész.

### 5.4 A sor KORLÁTOS, és a túlcsordulás SZABÁLYA kimondott

Az outboxnak felső korlátja van. Telítettségkor a **legrégebbi feldolgozatlan**
esemény kerül karanténba (nem törlődik), és ez diagnosztikában látszik — a korlátlan sor
offline hetek alatt megeszi a tárhelyet.

### 5.5 Nincs végtelen retry — kísérletszámlálóval

Minden esemény tárolja a kísérletek számát; a felső korlát elérésekor karanténba
kerül. A végtelen hurok akkumulátort és tárhelyet éget, és elrejti a valódi hibát.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A feldolgozás hibája NEM teszi sikertelenné a session mentését | `activity_ingestor_test.dart` — hibát dobó főkönyv mellett a session-eredmény érintetlen |
| A2 | Érvényes esemény nem vész el: crash-szimuláció (drain közbeni megszakítás) után újra feldolgozódik | `activity_ingestor_test.dart` |
| A3 | A drain kétszeri futtatása EGY főkönyv-bejegyzést ad (idempotens) | `activity_ingestor_test.dart` |
| A4 | Az esemény az outboxból csak a SIKERES főkönyv-írás után törlődik | `activity_ingestor_test.dart` — a hibát dobó írás után az esemény még a sorban van |
| A5 | Sérült esemény karanténba kerül, és NEM blokkolja a mögötte lévőket | `activity_ingestor_test.dart` — a sérült utáni esemény feldolgozódik |
| A6 | A karantén lekérdezhető (diagnosztikában látható) | `activity_ingestor_test.dart` |
| A7 | A sor korlátos: a korlát fölött a legrégebbi feldolgozatlan karanténba kerül, nem törlődik | `activity_ingestor_test.dart` — kapacitás-mátrix |
| A8 | A kísérletszám felső korlátja karanténba visz, nincs végtelen hurok | `activity_ingestor_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A feldolgozás a session mentési tranzakciójában fut | **A1** (a főkönyv hibája elveszi a sessiont) |
| Az esemény a feldolgozás ELŐTT törlődik az outboxból | **A4** (a hibát dobó írás után a sor üres) és **A2** |
| A sérült esemény megállítja a drain-t | **A5** (a mögötte lévő nem dolgozódik fel) |
| A sérült esemény törlődik | **A6** (a karantén üres) |
| A sor korlátlan | **A7** (a kapacitás-mátrix fölső cellája nem karanténoz) |
| A retry számláló nélkül fut | **A8** |

**A küszöb három kötelező cellája** (az outbox kapacitás-korlátja (`capacity`)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `capacity - 1` esemény a sorban | mind feldolgozásra vár, karantén ÜRES |
| **rajta** (a küszöbön) | pontosan `capacity` esemény | **még mind a sorban** — a korlát INKLUZÍV, a telítettség még nem túlcsordulás |
| a küszöb **fölött** | `capacity + 1` esemény | a **legrégebbi feldolgozatlan** karanténba kerül (NEM törlődik), és a karantén lekérdezhető |

A hármas tömören: **alatt** → az enqueue elfogadott · **rajta** → az enqueue még elfogadott · **fölött** → a legrégebbi pending rekord karanténba kerül, az új rekord a sorban marad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** töröld az eseményt az outboxból a főkönyv-írás ELŐTT, futtasd a gate-et → az **A4**
cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/application/activity_ingestor_test.dart
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

1. `activity_outbox_repository.dart` — az interfész (enqueue, peek, ack, quarantine, lekérdezés).
2. `local_activity_outbox_repository.dart` — korlátos lokális sor kísérletszámlálóval.
3. `activity_event_ingestor.dart` — enqueue a session mentése UTÁN; drain; ack CSAK sikeres főkönyv-írás után.
4. Karantén: sérült / ismeretlen / kísérlet-korlátot elért esemény, lekérdezhetően.
5. Kapacitás-szabály: a korlát fölött a legrégebbi feldolgozatlan karanténba.
6. A `public.dart` export-sorai.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A „takarítsunk a sorban” korai ack.** Crash esetén néma adatvesztés — pontosan az a hibaosztály, amit a projekt a settings-szinkronon már megmért (A4).
- **A jutalom beemelése a session tranzakciójába.** Konzisztensnek hangzik, és a termék magját (a gyakorlást) teszi a jutalomréteg túszává (A1).
- **A karantén elhagyása.** Egy rossz esemény vagy megállítja a feldolgozást, vagy némán eltűnik — mindkettő diagnosztizálhatatlan (A5/A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
