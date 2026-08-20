# ADR 0341 — Magyarázható XP policy és csökkenő hozam

- **Státusz:** elfogadva (E08-R06 pre-flight)
- **Dátum:** 2026-08-20
- **Kör:** `E08-R06` (Chapter 9, Kör 6)
- **Kapcsolódó:** [`0289`](0289-mastery-is-evidence-not-xp.md), [`0290`](0290-compassionate-streaks-and-idempotent-claims.md), [`0301`](0301-reward-ledger-append-only-idempotency.md), [`0338`](0338-reward-eligibility-policy-four-gates.md)

## Kontextus

Az R05 a reward jogosultságát négy külön kapuval dönti el, az R03 ledger pedig versionált, append-only nyugtát tárol. Az XP policynek ebből kell determinista, ellenőrizhető és farmolás-álló jutalmat számolnia anélkül, hogy átvenné a canonical activity event contract vagy a ledger schema tulajdonát.

## Döntés

1. A policy új application contractja `RewardPolicyRequest`: a már kiértékelt `RewardEligibilityDecision`, a session mért adatai, `practiceKey`, opcionális `parentEventId` és event ID. A canonical `LearningActivityEvent` nem változik.
2. A requesthez tartozó `RewardPolicyHistory` explicit módon átadja az adott napi már jóváírt XP-t, a practiceKey korábbi előfordulásszámát, a már jutalmazott event ID-ket és a korábbi gyermekek parent ID-it. Gyermek akkor kap nulla XP-t, ha a parent már jutalmazott; parent akkor, ha korábbi gyermek már hivatkozott rá. Ez a kétirányú explicit kapcsolat mindkét sorrendet lefedi, időalapú heurisztika nélkül.
3. Az eligibility kapuk a komponensek egyetlen belépési pontjai: `baseXp` → base/duration, `qualityBonus` → quality, `mastery` → improvement, `verified` → diversity. Elutasított komponens nulla és a kapu reasonja megmarad a receiptben. XP sosem állít mastery-t (ADR 0289).
4. A `RewardPolicyConfig` az összes hangolható szám egyetlen, versionált helye: pozitív `policyVersion`, komponensértékek/súlyok, napi XP cap és az exercise-repeat csökkenő hozam paraméterei. A repeat csak a kiszámított XP-t csökkenti; az activity historyt és a receiptet soha nem törli vagy tiltja.
5. A napi cap a számított pre-cap totalra alkalmazott `max(cap - earnedToday, 0)` maradékra vág. A capen vagy afölött is készül receipt, nulla XP-vel és `dailyCapApplied` indokkal; a tevékenység nem vész el. A policy receiptje mind az öt komponenst, a policy verzióját, a total XP-t és minden reduction reasont megtartja.

## Következmények

Az R06 kalkulátor önmagában még nem ír ledgerbe: egy későbbi bekötő kör a receiptet az R03 schema megfelelő mezőire képezi. Ez szándékosan elkerüli a lezárt ledger és canonical event contract scope-on kívüli módosítását, miközben a későbbi audit számára a részletes számítás rendelkezésre áll.

## Elutasított alternatívák

- `parentEventId` hozzáadása a canonical activity eventhez: lezárt, scope-on kívüli contract módosítás.
- Időközelségből kikövetkeztetett parent/child kapcsolat: nem determinisztikus.
- A cap fölötti esemény eldobása: sérti a gyakorlási előzmény megőrzését.
- Egyetlen `totalXp` visszaadása: a felület és audit nem tudná megmagyarázni a jutalom összetételét.
