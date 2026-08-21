# ADR 0388 — Mastery-mérföldkő: több-sessionös bizonyíték és magyarázható jelvény

- **Státusz:** elfogadva (E08-R21 pre-flight)
- **Dátum:** 2026-08-21
- **Kör:** `E08-R21` — Mastery mérföldkő domain és kiértékelő
- **Kapcsolódó:** [`0289`](0289-mastery-is-evidence-not-xp.md),
  [`0328`](0328-measured-gamification-baseline-contract.md),
  [`0338`](0338-reward-eligibility-policy-four-gates.md),
  [`0374`](0374-achievement-domain-and-catalog-contract.md),
  [`0378`](0378-achievement-presentation-and-privacy-safe-evidence.md)

> **Számozási megjegyzés:** a kör-brief `0315`-öt nevezte meg előre kiosztott
> ADR-számként (2026-08-18-i írás állapota), de `docs/adr/0315-halt-guard-ledger.md`
> egy azóta elfogadott, más témájú ADR — a szám elfogyott. A kötelező
> `tools/round-slots.py reserve-adr --round E08-R21` futás ezért `0388`-at
> adott; a foglaló mért eredménye az irányadó (§0.0 brief-revízió rögzíti).

## Kontextus

Az R05 (`0338`) négy determinisztikus reward-gate-et ad: `baseXp`,
`qualityBonus`, **`mastery`**, `verified`. Ez a `mastery` gate **per-activity**
döntés — egyetlen `LearningActivityEvent` `EvidenceTrust`-szintjét veti össze
egy `ActivitySource`-onkénti küszöbbel
(`default_reward_eligibility_policy.dart:143-155`), és XP-bónuszt enged vagy
tilt. **Nem** azonos azzal, amit ez a kör épít: egy **több sessionön átívelő,
XP-mentes mérföldkő-fogalommal**, amely azt válaszolja meg, hogy a felhasználó
**bizonyítottan elsajátított-e** egy skillt — nem azt, hogy egy adott
aktivitás jogosult-e bónuszra. A névütközés elkerülésére az új típusok
`Mastery*` előtagot kapnak, de a domain-dokumentáció explicit kimondja a
különbséget a meglévő reward-gate-től.

Az `ADR 0289` szerint az elsajátítottság mért teljesítményből származik, nem
XP-ből, és minden állítás mögött auditálható, konkrét bizonyíték áll. A
`vision/` feature-ben már van bevált mintázat a bizonyíték-alapú, fail-closed
küszöbre: a `VisionClaimGuard` `0.70`-es (pozitív állítás) és `0.85`-ös
(negatív állítás) `confidence` küszöbön enged csak claim-et
(`vision_claim_guard.dart:22-23`); a `GeometryConfidence` `0.5`-ös
tracking-küszöböt használ alacsonyabb tétű, folyamatos jelre. A mastery-
állítás tétje (bizonyított tudás, hosszú távú UI-ígéret) a Vision pozitív-
claim tétjéhez áll közelebb, nem a folyamatos tracking-jelhez.

Az `ADR 0378` (achievement presentation) már megoldotta az auditálhatóság és
a privacy-safe megjelenítés feszültségét: a felhasználó felé zárt reason-code
és aggregált érték megy, nyers session-ID, audio vagy free-text nélkül, mégis
a mögöttes adat (ledger, receipt) auditálható marad. Ez a kör ugyanezt az
elvet alkalmazza a domain rétegen: a bizonyíték-lista session-szinten
belsőleg azonosított (auditálhatóság), a kifelé adott jelvény-összefoglaló
viszont zárt, privacy-safe mezőkészlet.

## Döntés

1. **A kiértékelő bemenete zárt, és nem tartalmazza az XP/szint/ledger
   típusokat.** A `MasteryEvaluator` és a `MasteryMilestone`/`MasteryProgress`
   típusok importjai között nem szerepelhet `ExperiencePoints`,
   `RewardLedgerEntry`, `GamificationProfile` vagy más XP-/ledger-hordozó
   típus. Az egyetlen elfogadott bemenet mért teljesítmény: pontosság, tempó,
   ismételhetőség és a hozzá tartozó session-azonosító, nehézség,
   tempó-tartomány és (Vision/Analysis eredetnél) `confidence`.

2. **A bizonyíték-küszöb session-szintű, minimum 2, a küszöb inkluzív.**
   `MasteryMilestone.minEvidenceSessions >= 2`. A kiértékelő a bizonyítékokat
   `sessionId` szerint deduplikálja **mielőtt** a küszöbhöz hasonlítja — egy
   session több szegmense egy bizonyítéknak számít. A `minEvidenceSessions`
   határon (`==`) a mérföldkő **teljesül** (§6.1 „rajta" sora).

3. **A Vision/Analysis eredetű bizonyíték megbízhatósági küszöbe `0.70`**, a
   `VisionClaimGuard` pozitív-claim küszöbével (`_minimumConfidence = 0.70`,
   `vision_claim_guard.dart:22`) megegyezően — a mastery-állítás tétje a
   pozitív felhasználói claim-ekével esik egy kategóriába, nem a folyamatos
   tracking-jelével (`GeometryConfidence` `0.5`). A küszöb alatti Vision/
   Analysis bizonyíték nem kerül be a deduplikált session-halmazba — nem
   részleges súlyt kap, hanem teljes egészében kizáródik ennél a
   mérföldkőnél. Nem-Vision/Analysis eredetű (pl. eszköz által közvetlenül
   mért) bizonyítéknál a `confidence` mező opcionális; hiánya nem zárja ki a
   bizonyítékot.

4. **Az össze nem hasonlítható session kizáródik, nem külön kategóriaként
   kezelt.** A bizonyíték csak akkor számít a mérföldkőhöz, ha a nehézsége
   megegyezik a mérföldkő nehézségével ÉS a session tempója a mérföldkő
   tempó-tartományán belül esik. Eltérő nehézségű/tempójú session-bizonyíték
   nem kerül a deduplikált halmazba (nem hibát dob, egyszerűen nem számít).

5. **A teljesítés monoton — egyszer elért mérföldkő nem vehető vissza.** A
   `MasteryProgress` egy nullable `achievedAt` időbélyeget hordoz. Ha a
   kiértékelő korábbi állapota már `achievedAt != null`, az új kiértékelés
   megőrzi ezt az időbélyeget és a hozzá tartozó jelvényt, függetlenül attól,
   hogy az újonnan átadott bizonyíték-lista gyengébb vagy hiányos-e. A
   kiértékelő tehát explicit előző állapotot fogad be bemenetként (nem csak
   nyers bizonyíték-listát), és a monoton ág ELSŐ lépésben fut le, mielőtt a
   friss bizonyítékot egyáltalán kiértékelné.

6. **A jelvény magyarázható és privacy-safe — zárt mezőkészlet, nincs nyers
   azonosító.** A `MasteryBadge` a mérföldkő azonosítóját, a mért metrikát/
   nehézséget/tempó-tartományt és a hozzájáruló session-ek **darabszámát**
   (nem az ID-jukat) tartalmazza magyarázatként. Tilos mező: nyers audio/
   waveform, session-ID, szabad szöveg, bármilyen testtartás-/
   sérülés-/egészségügyi következtetés. Ez az `ADR 0378` 2. pontjának
   (zárt reason-code, nincs event/session-ID) domain-rétegbeli megfelelője.

## Következmények

A mastery-mérföldkő ellenőrizhetően független az XP-rendszertől — egy
jövőbeli XP-gyorsítósáv-kísérlet fordítási hibát adna, nem csendes
szemantikai csúszást. A session-szintű dedup és a monoton teljesítés ára,
hogy a domain réteg maga tárolja a hozzájáruló session-azonosítókat
(auditálhatóság), miközben a kifelé adott jelvény ezt szándékosan nem
mutatja — a jövőbeli UI-kör (Kör 22/23) csak a zárt mezőkészletet kapja,
nem nyúlhat vissza nyers session-adatért.

A `0.70`-es Vision/Analysis küszöb szigorúbb, mint a `GeometryConfidence`
tracking-küszöbe — alacsony megbízhatóságú, de technikailag "megfigyelt"
session-ek nem járulnak hozzá a mastery-hez, még akkor sem, ha egyébként
alap-XP-t adnak (R05). Ez tudatos ár: kevesebb mérföldkő teljesül gyorsan,
cserébe egyik sem hazudik.

## Mérce

Az E08-R21 brief §6/§6.1 cellái (A1–A8): XP/szint/ledger típus hiánya a
kiértékelő importjaiból; a bizonyíték-hármas (alatt/rajta/fölött) a
`minEvidenceSessions` küszöbön; szegmens-szintű vs. session-szintű
számlálás (valódi-sértés próba: egy session két szegmense NEM két
bizonyíték); megbízhatósági mátrix a Vision/Analysis eredetre; immutabilitás
egy gyengébb második kiértékelés után; nehézség/tempó-tartomány szerinti
összehasonlíthatatlanság; a jelvény és az összefoglaló forrás-vizsgálata
tiltott mezőkre (audio, session-ID, egészségügyi szöveg).
