# E08-R05 — Reward eligibility és evidence-trust policy

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 5
- **Kör-azonosító:** `E08-R05`
- **Branch:** `<motor>/e08-r05-reward-eligibility-and-trust-policy`
- **Előfeltétel:** `E08-R04` merge-elve (activity outbox)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** ~~`ADR 0303`~~ → **`ADR 0338`** (§0.0 R1 — a 0303
  elavult, lásd lent). Az ADR-t a Claude írja meg a kör indítási
  pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti
  (TILOS zóna).

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

## 0.0 Pre-flight brief-revízió (orchestrátor, 2026-08-20) — ADR-szám csere + konkrét típus-alak

| # | Mit állított a brief | Mért valóság | Feloldás |
|---|---|---|---|
| R1 | Fejléc + §5 cím: „Előre kiosztott ADR: `0303`" | `.pipeline/inflight/adr/0303` marker tartalma `round=E07-R17` (2026-08-18 09:03) — a 0303-at MÁR EGY MÁSIK kör foglalta, a brief-beli kiosztás elavult. Élő foglalás (`tools/round-slots.py reserve-adr --round E08-R05`, 2026-08-20 02:32 UTC): **0338** | A kör ADR-száma **0338** (nem 0303) — a fejléc és a §5 cím alább javítva. A `0303` szám felhasználatlan marad E08-R05 szempontjából (más kör tulajdona) |
| R2 | Pre-flight sor: „a policy [`reward_eligibility.dart`-ra és `evidence_trust.dart`-ra] képez le" — de nem mondja meg, HOGYAN különbözteti meg a `cancelled`/`failed` kimenetet, ha az egyetlen releváns bemenet (`RewardEligibility.eligible: bool` + szabad `reasonCode: String`) erre nem elég tipizált | Mérve: `reward_eligibility.dart` konstruktora KIZÁRÓLAG `.trim().isEmpty`-t ellenőriz a `reasonCode`-on — nincs formátum-/érték-konvenció; `grep -rn "cancelled\|failed" lib/features/gamification/` egyetlen találata a `RewardReason` enum SAJÁT két értéke (a kimenet, nem a bemenet oldalán) | ÚJ `ActivityOutcome { completed, cancelled, failed }` enum ebben a körben, a `reward_eligibility.dart` (tiltott zóna) módosítása NÉLKÜL — teljes indoklás [ADR 0338](../adr/0338-reward-eligibility-policy-four-gates.md) §1 |
| R3 | §5.1/A2: „alacsony megbízhatóságú bizonyíték: alap-XP jár, mastery nem"; §6.1/A4: „végzetes jelminőség: nincs quality bonus és nincs mastery" — a két mondat két KÜLÖNBÖZŐ inputra hivatkozik (bizalom vs jelminőség), amit egy naiv implementáció könnyen összemosna | A brief szövege nem mondja ki explicit, hogy a két tengely FÜGGETLEN — enélkül a kaszkád-táblázat nélkül ez a leggyakoribb „gyengítés" hibaosztály (§5.1 „NEM elfogadható gyengítés") egy szinttel lejjebb | A kapu × feltétel × indok táblázat lent és [ADR 0338](../adr/0338-reward-eligibility-policy-four-gates.md) §2 rögzíti: `qualityBonus` KIZÁRÓLAG `quality`-től függ, a `mastery` FÜGGETLENÜL mindkettőtől (ÉS-kapcsolat) |

Ezek a pontosítások **nem bővítik** az `allowed_paths`-t és nem lazítják a §6
acceptance criteria-t — kizárólag az ADR-szám javítása és a §5 elvi
döntéseinek Dart-szintű, egyértelmű alakja, amit a §1.0.1/§1 pre-flight
mérési kötelezettsége kényszerít ki.

**Visszakeresett előzmény (ADR 0312 §4.1, brief-lint S8):**
- `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "reward eligibility gate policy trust evidence mastery"` — legjobb releváns találat: `adr/0333` (Activity outbox kontextusa — a policy-hiány pontosan ott van megnevezve, ami ezt a kört motiválja); nincs korábbi kör, ami ezt a policy-t már megépítette volna.
- `node tools/knowledge-rag.mjs --corpus lessons,halts --top 5 "policy version threshold config single source magic number inclusive boundary"` — **L295** (bm25#8 emb#5, score 2.0011): „A publikus policy-mező constructor-validációja nem bizonyítja, hogy a mező vezérli a viselkedést" — KÖZVETLENÜL alkalmazva A8-ra lent.

**L295 alkalmazása az A8 gate-mátrixra:** a `reward_eligibility_policy_test.dart`-nak
a §8 „a küszöbök módosítása átüt" cellájához NEM elég a
`RewardEligibilityPolicyConfig` konstruktorát érvényes értékekkel meghívni —
kell egy cella, ami KÉT, egymástól ELTÉRŐ `minValidDurationBySource` (vagy
`masteryTrustThresholdBySource`) értékkel épített configot ad ugyanannak a
policy-nak, és megméri, hogy a `baseXp`/`mastery` döntés TÉNYLEGESEN
különbözik — a puszta konstrukció nem bizonyíték (L295).

### Konkrét típus-alak (teljes indoklás: [ADR 0338](../adr/0338-reward-eligibility-policy-four-gates.md))

```dart
// application/reward_eligibility_policy.dart
enum ActivityOutcome { completed, cancelled, failed }

final class RewardEligibilityRequest {
  factory RewardEligibilityRequest({
    required ActivitySource source,
    required ActivityOutcome outcome,
    required EvidenceTrust trust,
    required Duration validDuration,
    required double? quality,       // null = nincs mérve; ADR 0286 §1
  });
}

final class RewardGateDecision {
  factory RewardGateDecision.granted();
  factory RewardGateDecision.denied(RewardReason reason);
  // granted <=> reason == null (a másik sosem fordulhat elő)
}

final class RewardEligibilityDecision {
  factory RewardEligibilityDecision({
    required int policyVersion,
    required RewardGateDecision baseXp,
    required RewardGateDecision qualityBonus,
    required RewardGateDecision mastery,
    required RewardGateDecision verified,
  });
}

abstract interface class RewardEligibilityPolicy {
  RewardEligibilityDecision evaluate(RewardEligibilityRequest request);
}
```

```dart
// infrastructure/default_reward_eligibility_policy.dart
final class RewardEligibilityPolicyConfig {
  factory RewardEligibilityPolicyConfig({
    required int policyVersion,                                              // >= 1
    required Map<ActivitySource, Duration> minValidDurationBySource,         // ActivitySource.values MINDEGYIKÉRE kötelező
    required Map<ActivitySource, EvidenceTrust> masteryTrustThresholdBySource, // ua.
    double fatalSignalQualityThreshold = 0.0,                                // véges, [0,1]
  });
  factory RewardEligibilityPolicyConfig.standard(); // gyártási alapértékek
}

final class DefaultRewardEligibilityPolicy implements RewardEligibilityPolicy {
  DefaultRewardEligibilityPolicy({required RewardEligibilityPolicyConfig config});
  @override
  RewardEligibilityDecision evaluate(RewardEligibilityRequest request) { ... }
}
```

**A négy kapu kiértékelési sorrendje (kaszkád — az alsó kapu indoka öröklődik, nem generál újat):**

| Kapu | Feltétel (ÉS-lánc) | Indok tiltáskor |
|---|---|---|
| `baseXp` | `outcome == completed` ÉS `validDuration >= minValidDurationBySource[source]` (a küszöbön ELFOGADVA — §6.1 inkluzív) | `cancelled` / `failed` / `tooShort` |
| `qualityBonus` | `baseXp` adott ÉS `quality != null` ÉS `quality > fatalSignalQualityThreshold` | kaszkád vagy `fatalSignalQuality` |
| `mastery` | `baseXp` adott ÉS a fenti quality-feltétel ÉS `trust.index >= masteryTrustThresholdBySource[source].index` | kaszkád, `fatalSignalQuality` vagy `insufficientTrust` |
| `verified` | `mastery` adott ÉS `trust.index >= EvidenceTrust.verified.index` | kaszkád vagy `insufficientTrust` |

`qualityBonus` SZÁNDÉKOSAN nem függ `trust`-tól (A2 csak a `mastery`-t
párosítja alacsony bizalommal); `verified` fix küszöbe (`EvidenceTrust.
verified`) NEM kerül a configba (definíciós, nem üzleti szám — nem sérti
A8-at).

`public.dart`: mindkét ÚJ fájl exportálva (interfész ÉS
`DefaultRewardEligibilityPolicy` — nincs DI-réteg ebben a körben, ami a
konkrétot helyettesítené).

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
- `docs/adr/**` — az ADR 0338-at a Claude írja (§0.0 R1: a brief eredeti 0303 száma elavult).

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/application/reward_eligibility_policy.dart` | **ÚJ** — a policy interfésze |
| `lib/features/gamification/infrastructure/default_reward_eligibility_policy.dart` | **ÚJ** — a konfigurációból felépülő alapértelmezés |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `test/features/gamification/application/reward_eligibility_policy_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések (ADR 0338 — §0.0 R1: 0303 elavult)

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
