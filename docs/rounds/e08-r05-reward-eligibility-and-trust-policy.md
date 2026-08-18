# E08-R05 — Reward eligibility és evidence-trust policy

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 5
- **Kör-azonosító:** `E08-R05`
- **Branch:** `<motor>/e08-r05-reward-eligibility-and-trust-policy`
- **Előfeltétel:** `E08-R04` merge-elve (activity outbox)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0303` — a szám FOGLALT. Az ADR-t a Claude írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R02 `evidence_trust.dart` és `reward_eligibility.dart` TÉNYLEGES enum-értékeit — a policy ezekre képez le; és az R03 `reward_reason.dart` kódjait, mert az elutasítás indoka onnan jön. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/application/reward_eligibility_policy.dart",
  "lib/features/gamification/infrastructure/default_reward_eligibility_policy.dart",
  "lib/features/gamification/public.dart",
  "test/features/gamification/application/reward_eligibility_policy_test.dart",
  "docs/rounds/e08-r05-reward-eligibility-and-trust-policy.md",
]
gate_tests = [
  "test/features/gamification/application/reward_eligibility_policy_test.dart",
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

Döntsd el KÖZPONTILAG és determinisztikusan, hogy egy esemény jutalmazható-e — és ha
nem, **miért nem**, stabil, lokalizálható indok-kóddal.

Az [`ADR 0289`](../adr/0289-mastery-is-evidence-not-xp.md) itt válik kikényszerítetté:
a bizonytalan bizonyíték NEM old fel elsajátítottságot.

## 2. Jelenlegi állapot — mért tények

- Az R02 szállította az `EvidenceTrust` és `RewardEligibility` típusokat, az R03 a `RewardReason` kódokat.
- `lib/features/gamification/infrastructure/` **nem létezik** — ez a kör hozza létre.
- Az `ADR 0289` kimondja: az elsajátítottság mért teljesítményből származik, nem XP-ből, és minden állítás mögött auditálható session áll.
- A `lib/features/analyze/` és `lib/features/vision/` eredményei confidence-értéket hordoznak — a low-confidence eset valós, nem elméleti.

## 3. Scope

**Benne van:** forrásonkénti minimum érvényes időtartam és trust-szint · a cancelled / failed /
low-confidence / fatal-signal-quality esetek kezelése · az alap-XP, a quality bonus, a
mastery és a verified jogosultság **szétválasztása** · stabil indok-kód minden
elutasításhoz · verziózott, konfigurációból felépíthető policy.

**NINCS benne (tilos):**

- **XP-számítás** — a Kör 6 dolga; ez a kör csak a jogosultságot dönti el.
- AI-modell használata a jogosultsági döntéshez (§5.4) — abszolút tilos.
- Bármely feature bekötése, UI, hálózat.
- A mastery **kiértékelése** — Kör 21; itt csak a jogosultság kapuja van.
- `docs/adr/**` — az ADR 0303-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/application/reward_eligibility_policy.dart` | **ÚJ** — a policy interfésze |
| `lib/features/gamification/infrastructure/default_reward_eligibility_policy.dart` | **ÚJ** — a konfigurációból felépülő alapértelmezés |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `test/features/gamification/application/reward_eligibility_policy_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések (ADR 0303)

### 5.1 A jogosultság NÉGY külön kapu, nem egy

Az alap-XP, a quality bonus, a mastery-feloldás és a verified státusz **külön**
dönthető el. Egy alacsony megbízhatóságú felvétel adhat alap-XP-t az erőfeszítésért, és
közben NEM oldhat fel elsajátítottságot.

**NEM elfogadható gyengítés:** egyetlen `bool isEligible`. Az összevonás vagy elveszi a
kezdő erőfeszítés-jutalmát, vagy hamis elsajátítottságot ad — az ADR 0289 megsértése.

### 5.2 A kezdő erőfeszítés-jutalma MEGMARAD

A gyenge teljesítmény nem jogosultsági kérdés. Aki rosszul játszik, de gyakorolt,
kap alap-XP-t; amit nem kap, az a quality bonus és a mastery. A büntető gamifikáció az
ADR 0290 tiltólistáján van.

### 5.3 Minden elutasításnak STABIL indok-kódja van

Az elutasítás soha nem néma és soha nem szabad szöveg: az R03 `RewardReason`
kódjait használja, hogy a felület lokalizálhatóan meg tudja mondani, miért nem járt jutalom.
Enélkül a felhasználó számára a rendszer önkényesnek látszik.

### 5.4 NINCS AI-modell a jogosultsági döntésben

A policy tiszta, determinisztikus függvény: ugyanaz a bemenet ugyanazt a döntést
adja, minden futtatáskor és minden eszközön. Egy modell-alapú döntés nem reprodukálható,
nem auditálható, és a főkönyv (R03) auditálhatóságát értelmetlenné tenné.

**NEM elfogadható gyengítés:** „heurisztika finomhangoláshoz” behúzott modell-hívás.

### 5.5 A policy VERZIÓZOTT, és a verzió a döntés része

A policy-verzió a főkönyvbe kerül (R03 §5). Enélkül egy későbbi
küszöb-változtatás visszamenőleg értelmezhetetlenné teszi a régi bejegyzéseket.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A négy kapu (alap-XP / quality bonus / mastery / verified) KÜLÖN dönthető el | `reward_eligibility_policy_test.dart` — 4-oszlopos mátrix |
| A2 | Alacsony megbízhatóságú bizonyíték: alap-XP **jár**, mastery **nem** | `reward_eligibility_policy_test.dart` — az ADR 0289 cellája |
| A3 | Megszakított (cancelled) és hibára futott (failed) esemény semmilyen jutalmat nem kap | `reward_eligibility_policy_test.dart` |
| A4 | Végzetes jelminőség (fatal signal quality) esetén nincs quality bonus és nincs mastery | `reward_eligibility_policy_test.dart` |
| A5 | Minden elutasítás stabil `RewardReason` kóddal tér vissza (nincs néma `false`) | `reward_eligibility_policy_test.dart` — minden elutasítási ág |
| A6 | A policy determinisztikus: azonos bemenetre 100 futtatás azonos döntés | `reward_eligibility_policy_test.dart` — ismétléses cella |
| A7 | A döntés hordozza a policy-verziót | `reward_eligibility_policy_test.dart` |
| A8 | A küszöbök EGYETLEN konfigurációból származnak (nincs szórt magic number) | review + `reward_eligibility_policy_test.dart` — a konfiguráció módosítása átüt |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egyetlen `bool isEligible` a négy kapu helyett | **A1** és **A2** (a low-confidence eset vagy mindent ad, vagy semmit) |
| A gyenge teljesítmény elveszi az alap-XP-t | **A2** (a kezdő erőfeszítés-cella) |
| Az elutasítás néma `false` | **A5** |
| Modell-hívás a döntésben | **A6** (az ismétléses cella szór) |
| A küszöbök a metódusokba égetve | **A8** (a konfiguráció módosítása nem üt át) |
| A döntés nem hordozza a policy-verziót | **A7** |

**A küszöb három kötelező cellája** (a minimum érvényes gyakorlási időtartam forrásonként (`minValidDuration`)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `minValidDuration - 1s` | **nincs** alap-XP; a döntés `RewardReason.tooShort` kóddal tér vissza |
| **rajta** (a küszöbön) | pontosan `minValidDuration` | **JÁR** az alap-XP — a küszöb az ELFOGADÓ oldalhoz tartozik (inkluzív) |
| a küszöb **fölött** | `minValidDuration + 1s` | **JÁR** az alap-XP |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd a low-confidence ágat úgy, hogy mastery-t is adjon, futtasd a gate-et → az
**A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/application/reward_eligibility_policy_test.dart
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

1. `reward_eligibility_policy.dart` — az interfész: négy külön kapu, indok-kóddal.
2. A konfigurációs alak: forrásonkénti minimum időtartam és trust-küszöb, EGY helyen.
3. `default_reward_eligibility_policy.dart` — a determinisztikus alapértelmezés.
4. A cancelled / failed / low-confidence / fatal-signal ágak, mindegyik saját indok-kóddal.
5. A policy-verzió beépítése a döntésbe.
6. A `public.dart` export-sorai.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A négy kapu összevonása.** Egyszerűbb felület, és pontosan az ADR 0289 sérül: hamis elsajátítottság vagy elvett erőfeszítés-jutalom (A1/A2).
- **A büntető szigor.** Kézenfekvő a gyenge teljesítményt jutalom-megvonással kezelni; ez az ADR 0290 tiltólistáján van (A2).
- **A szórt küszöbök.** A Kör 29 balance-szimulációja egyetlen konfigurációt vár; a metódusokba égetett számok ott válnak mérhetetlenné (A8).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
