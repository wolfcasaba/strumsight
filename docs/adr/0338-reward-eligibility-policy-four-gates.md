# ADR 0338 — Reward eligibility: négy különálló kapu, tipizált outcome, egyetlen konfiguráció

- **Státusz:** elfogadva
- **Dátum:** 2026-08-20
- **Kör:** `E08-R05` (Chapter 9, Kör 5)
- **Kapcsolódó:** [`0289`](0289-mastery-is-evidence-not-xp.md) (az elsajátítottság
  bizonyíték, nem XP — ez a döntés kényszeríti ki technikailag),
  [`0290`](0290-compassionate-streaks-and-idempotent-claims.md) (nincs büntető
  gamifikáció — a gyenge teljesítmény nem jogosultsági kérdés),
  [`0301`](0301-reward-ledger-append-only-idempotency.md)
  (`RewardLedgerEntry.policyVersion: int` — ennek a döntésnek a `policyVersion`
  mezője erre illeszkedik), [`0329`](0329-canonical-activity-event-contracts.md)
  (`EvidenceTrust`/`RewardEligibility`/`RewardReason` — a jelen döntés
  bemenete/kimenete ezekre épül)

## Kontextus

Az E08-R05 brief (`docs/rounds/e08-r05-reward-eligibility-and-trust-policy.md`)
öt elvi döntést rögzít (§5.1–§5.5): négy külön kapu, a kezdő erőfeszítés
jutalmának megtartása, stabil indok-kód minden elutasításhoz, tiltott
AI-modell a döntésben, verziózott policy. Ezek a döntések ELVI szinten
helyesek, de nem specifikálják a konkrét Dart-alakot — ez okozná pontosan azt
a hibaosztályt, amit a pre-flight §1 mér: egy „elérhetetlen cél-státusz", ha
az implementer a meglévő `RewardEligibility` (R02) `eligible: bool` + szabad
szöveges `reasonCode: String` párosából próbálná visszafejteni a
`cancelled`/`failed` (R03 `RewardReason`) megkülönböztetést.

**Mért rés.** `lib/features/gamification/domain/activity/reward_eligibility.dart`
(R02, `a3d98ed2`) egyetlen `eligible: bool` + `reasonCode: String` (szabad
szöveg, PÉLDA a saját tesztjéből: `'practice.valid'`, de a konstruktor csak
`.trim().isEmpty`-t ellenőriz — NINCS formátum-kényszer) párost ad. Sem ez,
sem az `EvidenceTrust` enum (bizalmi FOK, nem kimenet-típus) nem hordoz
tipizált módot a „megszakítva" és a „hibára futott" megkülönböztetésére —
pedig az A3 acceptance-cella (brief §6) mindkettőt a
`reward_eligibility_policy_test.dart`-ban, KÖZVETLENÜL a policy-n keresztül
várja mérni. String-mintaillesztés a szabad `reasonCode`-ra törékeny és nem
Dart-idiomatikus (nincs is dokumentált konvenció, ami ezt garantálná) — ez a
döntés ehelyett egy ÚJ, e kör saját fájljában élő tipizált enumot vezet be.

A `reward_eligibility.dart` és a `reward_reason.dart` NINCS a kör
`allowed_paths` listáján (mindkettő korábbi kör lezárt szállítása) — a
feloldás ezért kizárólag ÚJ, e kör saját fájljaiban élő típusokkal
történhet, a meglévő két típus MÓDOSÍTÁSA nélkül.

## Döntés

### 1. A policy bemenete: `RewardEligibilityRequest` + ÚJ `ActivityOutcome` enum

```dart
enum ActivityOutcome { completed, cancelled, failed }

final class RewardEligibilityRequest {
  factory RewardEligibilityRequest({
    required ActivitySource source,
    required ActivityOutcome outcome,
    required EvidenceTrust trust,
    required Duration validDuration,
    required double? quality,
  });
  // validál: validDuration nem negatív; quality (ha nem null) véges és [0,1]
}
```

`source`/`trust`/`validDuration`/`quality` a meglévő `ActivitySource`,
`EvidenceTrust` és a `RewardEligibility` (R02) mező-SZEMANTIKÁJÁRA képez le
(azonos típus, azonos érvényességi tartomány) — ez teljesíti a brief
pre-flight sorát („a policy ezekre képez le"). Az `ActivityOutcome` az
egyetlen ÚJ input-fogalom: a hívó fél (egy jövőbeli kör bekötése) dönti el,
melyik érték illeti az eseményt — ez a felelősség NEM ennek a körnek a
dolga, csak a TÍPUS létrehozása.

### 2. Két FÜGGETLEN tengely: bizalom (trust) ÉS jelminőség (quality) — nem ugyanaz

Mérve a brief §6 szövegén: az A2 („alacsony megbízhatóságú bizonyíték") a
BIZALMI fokra (`EvidenceTrust`) hivatkozik és KIZÁRÓLAG a `mastery` kaput
tiltja; az A4 („végzetes jelminőség") a MÉRT teljesítmény-jelre (`quality`)
hivatkozik és a `qualityBonus` ÉS a `mastery` kaput is tiltja. A két tengelyt
ÖSSZEVONNI (pl. alacsony bizalom is tiltaná a quality bonust) ellentmond az
A2 szó szerinti szövegének, és éppen azt az „NEM elfogadható gyengítés"
mintát reprodukálná egy szinttel lejjebb, amit a brief §5.1 tilt.

A **kaszkád-sorrend** (a legalacsonyabb tiltott kapu indoka öröklődik
felfelé, nem generál újat):

| Kapu | Feltétel (ÉS-lánc, sorrendben) | Indok tiltáskor |
|---|---|---|
| `baseXp` | `outcome == completed` ÉS `validDuration >= minValidDuration[source]` | `cancelled` / `failed` (outcome-ból) vagy `tooShort` |
| `qualityBonus` | `baseXp` ADOTT ÉS `quality != null` ÉS `quality > fatalSignalQualityThreshold` | `baseXp` indoka (kaszkád) vagy `fatalSignalQuality` |
| `mastery` | `baseXp` ADOTT ÉS `quality` nem fatális (ua. mint fent) ÉS `trust.index >= masteryTrustThresholdBySource[source].index` | kaszkád vagy `fatalSignalQuality` vagy `insufficientTrust` |
| `verified` | `mastery` ADOTT ÉS `trust.index >= EvidenceTrust.verified.index` | kaszkád (mastery indoka) vagy `insufficientTrust` |

`qualityBonus` SZÁNDÉKOSAN nem néz `trust`-ot — a brief A2 cellája csak a
`mastery`-t párosítja az alacsony bizalommal.

### 3. „Fatal signal quality" konvenció: `quality == null` ÉS a mért-de-fatális eset UGYANAZ a kimenet

A meglévő `RewardReason` enum (R03, tiltott zóna, nem bővíthető) nem
különbözteti meg a „nincs mérve" és a „mérve, de használhatatlan" esetet —
mindkettő `RewardReason.fatalSignalQuality`-ként jelenik meg. Ez tudatos:
mindkét eset ugyanazt a felhasználó felé mutatandó állítást hordozza („ehhez
a felvételhez nem tudtunk minőséget megállapítani"), és az ADR 0286 elve
(§1, hiányzó adat nem nulla) itt ÚGY érvényesül, hogy a hiányzó adat (`null`)
és a mért nulla-közeli adat AZONOS szigorú KEZELÉST kap, de nem azonos
ÉRTÉKKÉNT (a `null` sosem `<= 0.0`; az összehasonlítás explicit
`quality == null || quality <= threshold` alakú, NEM `(quality ?? 0.0) <=
threshold`).

`fatalSignalQualityThreshold` (`double`, alapérték `0.0`, kötelezően véges
és `[0, 1]` tartományban) a `qualityBonus`/`mastery` ELUTASÍTÓ oldalához
tartozik (inkluzív: pontosan a küszöbön mérve is fatális) — tükrözve a brief
§6.1 duration-küszöbének ELFOGADÓ-oldali inkluzivitását, csak itt a TILTÓ
oldalon.

### 4. `verified` fix küszöbe NEM a konfiguráció része

A `mastery` kapu forrásonként HANGOLHATÓ bizalmi küszöböt kap
(`masteryTrustThresholdBySource: Map<ActivitySource, EvidenceTrust>`, a
konfiguráció része). A `verified` kapu ellenben az `EvidenceTrust.verified`
(a legmagasabb, FIX fokozat) — ez definíciós, nem üzleti hangolású szám,
ezért NEM kerül a konfigurációba: a „verified" fogalmilag azt jelenti, hogy
a bizonyíték a legmagasabb fokozatot érte el, forrástól függetlenül. Ez nem
sérti a brief A8 („egyetlen konfiguráció") elvárását — az A8 a HANGOLHATÓ
üzleti számokra vonatkozik (időtartam, mastery bizalmi sáv), nem az
`EvidenceTrust` enum saját, strukturális maximumára.

### 5. `RewardEligibilityPolicyConfig` — teljesség konstruktor-időben, fail-fast

```dart
final class RewardEligibilityPolicyConfig {
  factory RewardEligibilityPolicyConfig({
    required int policyVersion,
    required Map<ActivitySource, Duration> minValidDurationBySource,
    required Map<ActivitySource, EvidenceTrust> masteryTrustThresholdBySource,
    double fatalSignalQualityThreshold = 0.0,
  });
  factory RewardEligibilityPolicyConfig.standard(); // gyártási alapértékek
  // validál: policyVersion >= 1; MINDKÉT map az ActivitySource.values ÖSSZES
  // elemét tartalmazza (külön-külön ArgumentError, ha bármelyik hiányos);
  // fatalSignalQualityThreshold véges és [0,1]
}
```

Egy hiányos forrás-bejegyzés PROGRAMHIBA (fejlesztő felejtett el egy forrást
konfigurálni), nem futásidejű adathiba — ezért a konstruktor ELUTASÍTJA, nem
egy új, a tiltott zónában élő `RewardReason` értékkel jelzi futásidőben. A
`DefaultRewardEligibilityPolicy` a konfigurációt KÖTELEZŐ, nem opcionális
paraméterként kapja (nincs rejtett beépített alapérték a policy-osztályban);
a modul emellett egy `RewardEligibilityPolicyConfig.standard()` factory-t
szállít a gyártási alapértékekkel — ez különíti el a MECHANIZMUST (a
policy-osztály) a TARTALOMTÓL (a konkrét számok), és teszi lehetővé, hogy
egy teszt egyetlen forrás küszöbét eltérő értékre cserélje a viselkedés
bizonyításához (lásd `L295`, brief §0.0).

### 6. `policyVersion: int`, nem `String`

A kódbázis másik policy-mintája (`ProgressionPolicy`, ADR 0265) `String
version`-t használ, DE az R03 `RewardLedgerEntry.policyVersion` már
`int`-ként szállított és validált (`>= 1`,
`lib/features/gamification/domain/rewards/reward_ledger_entry.dart:36-41`) —
mivel EZ a döntés `policyVersion`-je a főkönyvbe kerül (brief §5.5), a
típusnak a MEGLÉVŐ, szállított ledger-mezővel kell egyeznie, nem az elvben
hasonló, de független `ProgressionPolicy`-mintával.

### 7. `EvidenceTrust` összehasonlítás `.index` alapon

Az enum deklarációs sorrendje (`unverified < userConfirmed < deviceObserved
< scored < verified`) MÉRTEN bizalmi fok szerint növekvő
(`lib/features/gamification/domain/activity/evidence_trust.dart`, doc-
komment: „confidence grade"). A küszöb-összehasonlítás `.index`-en megy
(`trust.index >= threshold.index`), nem kimerítő switch-en — ez a szokásos
Dart-idióma egy MÁR bizonyítottan rendezett enumhoz.

### 8. `public.dart` mindkét új fájlt exportálja

Az interfész (`RewardEligibilityPolicy`) ÉS az alapértelmezett implementáció
(`DefaultRewardEligibilityPolicy`) is exportálódik — ellentétben az R03
mintával (ahol a `LocalRewardLedgerRepository` szándékosan NEM exportált),
mert itt NINCS DI-keret vagy provider-réteg ebben a körben, ami a konkrét
típust helyettesítené; egy jövőbeli bekötő kör (Kör 6+) közvetlenül a
`DefaultRewardEligibilityPolicy` konstruktorát fogja hívni. Ha egy későbbi
kör DI-t vezet be, a barrel szűkíthető — ez nem ennek a körnek a döntése.

## Következmények

**Pozitív.** A négy kapu ténylegesen független (a bizalom és a jelminőség
tengelye külön mérhető és külön tesztelhető cellákat termel); a
konfiguráció hiányossága fejlesztési időben bukik, nem néma futásidejű
lyukként; a `policyVersion` típusa a már szállított ledger-mezővel
konzisztens.

**Negatív / ár.** Egy ÚJ enum (`ActivityOutcome`) kerül a kódbázisba, ami
átfedésben van a `RewardEligibility.eligible`/`reasonCode` (R02) fogalmi
terével — ez a két típus egy jövőbeli körben (a `RewardEligibility` tényleges
bekötésekor) összehangolásra szorulhat; ez a döntés TUDATOSAN nem oldja fel
most, mert a `reward_eligibility.dart` ennek a körnek tiltott zónája.

**Amit ez a döntés TILT.** `qualityBonus` gate bizalmi-fok alapú tiltását;
`(quality ?? 0.0)` alakú fatal-quality összehasonlítást; opcionális/rejtett
alapértelmezett konfigurációt a policy-osztályban; string-mintaillesztést a
`RewardEligibility.reasonCode`-ra a kimenet-indok levezetéséhez.
