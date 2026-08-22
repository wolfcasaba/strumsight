# ADR 0394 — Főkönyv-szinkron szerződés: nyugta-alapú fel-/letöltés, azonosító-uniós összefésülés, igazolt/nem igazolt szétválasztás

- **Státusz:** elfogadva (E08-R28 pre-flight)
- **Dátum:** 2026-08-22
- **Kör:** `E08-R28` — Ledger sync contract és merge
- **Kapcsolódó:** [`0290`](0290-compassionate-streaks-and-idempotent-claims.md)
  (idempotens claim-minta), a Kör 03 (`RewardLedgerEntry`, append-only,
  `sourceEventId`-dedup) és a Kör 07 (profil mint projekció, nem forrás)

> **Számozási megjegyzés:** a kör-brief `0319`-et nevezte meg előre kiosztott
> ADR-számként (2026-08-18-i írás állapota), de az azóta elkelt korábbi,
> független köröknél — ugyanaz a minta, mint az E08-R27 stale `0318`-ja. A
> kötelező `tools/round-slots.py reserve-adr --round E08-R28` futás ezért
> `0394`-et adta; a foglaló mért eredménye az irányadó (§0.0 brief-revízió
> rögzíti).

## Kontextus

A `backend/` FastAPI + SQLite + JWT szolgáltatás ma kizárólag login és
felhő-beállítás szinkront szolgál ki (`settings_sync.dart` mintája:
szinkronizáltnak jelölés csak szerver-megerősítés után); a felismerés
100%-ban eszközön marad. A gamifikációs réteg saját, helyi forrása a Kör 03
`RewardLedgerEntry` — immutable, append-only, `sourceEventId`-re helyi
idempotenciával dedupolt nyugta —, a Kör 07 profilja pedig ebből
SZÁRMAZTATOTT projekció, nem önálló forrás. `backend/app/gamification/` ma
nem létezik.

Ez a kör a KÉSŐBBI fiók- és közösségi (Epic 9) használathoz készíti elő az
offline-first, duplikációmentes szinkron-szerződést — anélkül, hogy bármilyen
tényleges felhő-funkciót aktiválna. A legfontosabb, nem tárgyalható határ: a
szerver soha nem fogadhat el kliens-oldali összesített XP-t, mert egy ilyen
mező triviálisan hamisítható és a teljes jutalom-rendszer hitelességét vinné.

## Döntés

1. **A kliens nyugtákat küld, nem összeget — a szerver saját maga összegez.**
   A fel-/letöltési szerződés (`gamification_sync_contract.dart`,
   `backend/app/gamification/schemas.py`) request-sémájában NINCS `totalXp`
   vagy ezzel ekvivalens előre számolt aggregátum mező — sem kötelezőként,
   sem opcionális ellenőrző mezőként. A `backend/app/gamification/service.py`
   a beérkező nyugták listájából számol összesítést; a §6 A2 cella
   (`backend/tests/test_gamification_ledger.py`) egy `totalXp`-t tartalmazó
   kérést küld, és azt méri, hogy a szerver ELUTASÍTJA vagy figyelmen kívül
   hagyja, sosem fogadja el mezőértékként.

2. **Az összefésülés a főkönyv-azonosító ÉS a forrás-esemény azonosító
   kettős kulcsán unióként történik — sosem teljes profil last-write-wins.**
   `ledger_merge_policy.dart` a két oldal (helyi + szerver) nyugta-halmazát
   uniózza; egy nyugta akkor és csak akkor számít duplikátumnak, ha MINDKÉT
   kulcs (`ledgerId`, `sourceEventId`) egyezik egy már ismert bejegyzéssel.
   Csak a `ledgerId`-ra dedupolás alul-egyesít (két eszközön külön
   `ledgerId`-vel, de ugyanarra a `sourceEventId`-re keletkezett nyugta
   duplán számítana → A1 pirosra vált). Csak a `sourceEventId`-re dedupolás
   túl-egyesít (két legitim, eltérő forrás-eseményű nyugta ütköző
   `sourceEventId` mellett összeolvadna → A3 pirosra vált, adatvesztés — ez
   pontosan az a hibaosztály, amit a projekt a beállítás-szinkronon már
   mért). A teljes profil frissebb `updatedAt` alapú felülírása kizárt.

3. **Igazolt (`verified`) és nem igazolt (`unverified`) két külön,
   auditálható státusz — a kliens sosem állíthatja magát `verified`-re.**
   A lokálisan keletkezett nyugta állapota `unverified`; kizárólag a szerver
   válasza (a letöltési/visszaigazolási úton) állíthatja `verified`-re. A §6
   A4 cella ezt méri: a `verified` mező kliens-oldali direkt beállítása nem
   befolyásolhatja a ténylegesen auditált státuszt. Ez a Kör 22 közösségi
   felhasználásának előfeltétele (egy közösségi felületen csak `verified`
   nyugta jelenhetne meg hitelesként).

4. **Fiók kikapcsolva vagy kijelentkezve → nulla hálózati kérés — nem
   próbálkozás, nem sorolás.** A szinkron-réteg ugyanazt a mért mintát
   követi, mint a `settings_sync.dart` (`accountEnabledProvider` a
   konstruktorban, mielőtt bármilyen listener regisztrálódna): ha a kapu
   zárva, a réteg egyetlen kérést sem indít, és nem sorol be later-küldésre
   sem. A §6 A5 hálózat-cella a SAJÁT transport-mockot kell hívja
   (`L140` — a garanciát a tényleges turn-úton, gateway/transport-spy-vel
   kell mérni, nem egy örökölt, más transportra épülő network-probe-bal),
   különben a próba vak marad az új sync-transportra.

5. **A szerződés verziózott; ismeretlen verzió hiba, a policy-verzió eltérés
   pedig megőrzés + explicit superseding, nem eldobás vagy csendes
   újraszámolás.** Egy eltérő `policyVersion`-ű nyugta a merge során
   MEGŐRZŐDIK; egy felülíró (superseding) nyugta csak explicit
   hivatkozással (a lecserélt nyugta azonosítójára mutatva) válthatja le. Az
   ismeretlen szerződés-verzió (a `gamification_sync_contract.dart`
   burkológ verziója, nem a `policyVersion`) mind a Dart, mind a backend
   oldalon hibát ad, nem csendes best-effort feldolgozást (§6 A7).

## Következmények

A kör NEM aktivál semmilyen tényleges hálózati útvonalat vagy UI-t — a
szerződés és az összefésülési szabály e körben tisztán tesztelhető,
caller-fed egységekként készül el, hívó (feltételezhetően egy jövőbeli
fiók-bekötő kör) nélkül. Ennek ára, hogy a `backend/app/gamification/`
router-szintű regisztrációja (a FastAPI route maga) ennek a körnek NEM
tárgya — a `schemas.py`/`service.py` a szerver-oldali logikát hordozza, a
tényleges HTTP-végpont bekötése egy jövőbeli kör dolga marad, ha a fiók-
funkció ténylegesen aktiválódik.

A dedup-kulcs kettőssége (`ledgerId` + `sourceEventId`) egy új, a szinkron-
rétegre szűkített szabály — nem módosítja a Kör 03 HELYI
`RewardLedgerRepository.hasProcessedEvent` egykulcsos (`sourceEventId`)
idempotenciáját, amely továbbra is a helyi append-útra érvényes és
változatlan marad.

## Mérce

A brief §6/§6.1 cellái (A1–A8): az idempotencia — kétszeri szinkron nem
duplikál (A1, valódi-sértés próba KÖTELEZŐ: csak `ledgerId`-ra dedup →
pirosra kell váltania); a kliens-összeg elutasítása (A2, backend teszt); az
unió-alapú összefésülés, egyik oldal bejegyzése sem vész el (A3); az
igazolt/nem igazolt megkülönböztethetőség (A4); a fiók-kikapcsolt nulla
hálózat (A5, transport-szintű mérés); a policy-verzió eltérés megőrzése és
az explicit superseding (A6); a szerződés-verziózás és ismeretlen verzió
hibája (A7); és a teljes lokális offline működés a szinkron nélkül (A8).
