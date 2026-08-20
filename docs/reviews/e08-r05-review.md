# E08-R05 — Review

Brief: docs/rounds/e08-r05-reward-eligibility-and-trust-policy.md
Diff: `git diff df41b69b..03085b4d1c4b` (pre-flight commit → implementer commit, branch `codex/e08-r05-reward-eligibility-and-trust-policy`)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-20
Verdikt: CHANGES REQUIRED

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 0 · NOTE: 2

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | A négy kapu (alap-XP / quality bonus / mastery / verified) KÜLÖN dönthető el | ⚠️ részben | A kód ténylegesen független logikát futtat mind a négy kapura (`default_reward_eligibility_policy.dart:114-168`); DE lásd **F1** — a `mastery`/`verified` függetlenségét jelenleg egyetlen teszt sem bizonyítja |
| A2 | Alacsony megbízhatóságú bizonyíték: alap-XP jár, mastery nem | ✅ | `reward_eligibility_policy_test.dart:6-15` (`trust: EvidenceTrust.deviceObserved` < `masteryThreshold: scored` → baseXp+qualityBonus granted, mastery+verified denied `insufficientTrust`); önállóan reprodukálva: a mastery trust-küszöb ideiglenes kiiktatása a §10 handoff szerint 2 tesztet vitt pirosra (implementer-oldali valódi-sértés próba, nem csak bemondás — a kódban a küszöb-ág ténylegesen jelen van és a hívási láncban ül) |
| A3 | Megszakított/hibára futott esemény semmilyen jutalmat nem kap | ✅ | `reward_eligibility_policy_test.dart:29-51`, mind a 4 kapu `cancelled`/`failed` indokkal, `trust: verified` mellett is (bizonyítja, hogy az outcome felülír mindent) |
| A4 | Végzetes jelminőség: nincs quality bonus és nincs mastery | ✅ | `reward_eligibility_policy_test.dart:53-74` — a küszöbön (`quality: 0.2` == `fatalSignalQualityThreshold: 0.2`) ÉS `quality: null` esetén is `fatalSignalQuality`; a `_hasUsableQuality` (`default_reward_eligibility_policy.dart:170-171`) explicit `quality != null && quality > threshold`, NEM `(quality ?? 0.0)` — a null-eset nem konvertálódik számmá |
| A5 | Minden elutasítás stabil `RewardReason` kóddal tér vissza | ✅ | `RewardGateDecision._` konstruktor-invariáns (`isGranted == (reason == null)`) + a két factory (`.granted()`/`.denied(reason)`) a típusrendszer szintjén kizárja a néma `false`-t; minden denial-ág a teszt szerint konkrét `RewardReason`-t hordoz |
| A6 | A policy determinisztikus (100 futtatás) | ✅ | `reward_eligibility_policy_test.dart:105-113`, 100 iteráció, azonos eredmény |
| A7 | A döntés hordozza a policy-verziót | ✅ | `reward_eligibility_policy_test.dart:115-119` (`policyVersion: 7` → `decision.policyVersion == 7`) |
| A8 | A küszöbök EGYETLEN konfigurációból származnak | ✅ | `reward_eligibility_policy_test.dart:121-150` — KÉT különböző `minValidDurationBySource`/`masteryTrustThresholdBySource` értékkel épített config UGYANARRA a requestre eltérő döntést ad (nem csak konstrukció — a viselkedés ténylegesen átüt, [[L295]] szerint ez a bizonyíték szintje) |
| §6.1 küszöb-hármas | alatt/rajta/fölött, a küszöb inkluzív az elfogadó oldalon | ✅ | `reward_eligibility_policy_test.dart:76-103` — `4:59` tooShort, `5:00` és `5:01` granted |

## Scope-audit

```
python3 tools/scope-audit.py --repo /tmp/review-e08-r05 \
  --brief /tmp/review-e08-r05/docs/rounds/e08-r05-reward-eligibility-and-trust-policy.md \
  --base df41b69b
→ Legacy scope audit OK (df41b69b..03085b4d1c4b, 5 changed path(s), 0 generated/ignored)
```

Engedélyezett fájlokon kívüli változás: **nincs**. Az 5 megváltozott fájl
pontosan a brief `allowed_paths` 5 bejegyzése (policy interfész, default
implementáció, `public.dart` bővítés, célteszt, a brief saját §0.0
pre-flight revíziója utáni handoff-frissítése).

## Megállapítások

### F1 — MAJOR — A `verified` kapu függetlensége a `mastery`-től nincs tesztelve

- **Fájl:** `test/features/gamification/application/reward_eligibility_policy_test.dart` (hiányzó cella); az érintett termékkód `lib/features/gamification/infrastructure/default_reward_eligibility_policy.dart:157-168`
- **Probléma:** a `_evaluateVerified` a saját `trust.index < EvidenceTrust.verified.index` ellenőrzést helyesen végrehajtja a termékkódban, DE a tesztsorozat egyetlen cellája sem különbözteti meg a `mastery` és a `verified` kimenetét — minden meglévő teszt olyan bemenetet használ, ahol a kettő MINDIG egyezik (vagy mindkettő granted, mert `trust: verified`, vagy mindkettő denied ugyanazzal a kaszkádolt indokkal).
- **Mért, reprodukált próba:** ideiglenesen `_evaluateVerified`-et lecseréltem `return mastery;`-re (a `verified` szó szerint a `mastery` döntést tükrözi, elveszítve a saját küszöbét), izolált `/tmp/review-e08-r05` klónban, majd visszaállítottam. `flutter test test/features/gamification/application/reward_eligibility_policy_test.dart` — **15/15 továbbra is zöld** a mutáció alatt. Ez azt jelenti: egy jövőbeli regresszió, ami a `verified`-et a `mastery` álnevévé egyszerűsítené (pl. „duplikált kód összevonása" refaktor), jelen pillanatban ÉSZREVÉTLEN maradna, holott az A1 kritérium szó szerint négy KÜLÖN dönthető kaput ír elő, és a §5.1 explicit tiltja az összevonást.
- **Hatás:** ha ez a regresszió valaha bekövetkezne, a `verified` mező hamis `true`-t adna vissza `scored`-szintű (nem `verified`-szintű) bizalom mellett is — ez pont az ADR 0289 „auditálható bizonyíték" elvét sértené a legszigorúbb kapunál, csendben, zöld gate mellett.
- **Kötelező javítás:** egy új teszt-cella, ahol `mastery` GRANTED, de `verified` DENIED — pl. `trust: EvidenceTrust.scored` (eléri az alapértelmezett `masteryThreshold: scored`-ot, tehát `mastery` granted) ÉS ugyanez a `trust` NEM éri el `EvidenceTrust.verified`-et, tehát `verified` denied `insufficientTrust`-tal. (A jelenlegi `_request()`/`_policy()` alapértelmezett paraméterei — `trust: EvidenceTrust.scored`, `masteryThreshold: EvidenceTrust.scored` — már MA is pontosan ezt a helyzetet termelik; csak egyetlen `test(...)` blokk hiányzik, ami ezt ténylegesen ASSERTálja.)
- **Ellenőrzés:** az új cella hozzáadása UTÁN a fenti `return mastery;` mutáció megismétlése — a célteszt-fájlnak PIROSRA kell váltania; visszaállítás után ismét 15/15 zöld.
- **Státusz:** OPEN

### N1 — NOTE — `ActivityOutcome` és a meglévő `RewardEligibility.eligible`/`reasonCode` (R02) fogalmi átfedése

Már dokumentálva és tudatosan vállalva [ADR 0338](../adr/0338-reward-eligibility-policy-four-gates.md)
„Következmények / Negatív" szakaszában — a `reward_eligibility.dart` ennek a
körnek tiltott zónája, az összehangolás egy jövőbeli bekötő kör feladata. Nem
blokkol.

### N2 — NOTE — a forrás-térkép teljesség-ellenőrzése csak a duration oldalon tesztelt explicit hiányzó kulccsal

`RewardEligibilityPolicyConfig._validateCompleteSourceMap` egyetlen generikus
segédfüggvény, amit MINDKÉT map-re (duration, trust) azonos módon hív a
konstruktor; a teszt (`reward_eligibility_policy_test.dart:163-190`) egy
explicit hiányzó kulccsal (`ActivitySource.practice` törölve) csak a duration
oldalt próbálja. Mivel a hívott mechanizmus azonos, ez alacsony kockázatú
hézag — nem blokkol, de egy jövőbeli körben olcsó pótolni egy tükör-cellával a
trust map-re.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer, §10) | Ellenőrizve (reviewer, saját /tmp klón) |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld (3 item, No issues found) | ✅ zöld |
| test (célzott) | 15/15 zöld | ✅ 15/15 zöld, saját futtatás |
| architecture | zöld | ✅ zöld (`Architecture dependencies OK, 12 allowlisted deviation(s)`) |
| secrets | zöld | ✅ zöld (3002 file scanned, 0 finding) |
| l10n | zöld | ✅ zöld |
| scope-audit | 5 changed, 0 generated/ignored, OK | ✅ megegyezik, saját futtatás |
| CI (teljes suite + property + APK) | — (implementer nem futtatja) | folyamatban — az orchestrátor a review után dispatcheli |

Minden gate-bizonyítékot **saját kézzel, izolált `/tmp/review-e08-r05`
klónban, a GitHub originról húzott, ténylegesen pusholt commitról**
(`03085b4d1c4b`) reprodukáltam — nem az implementer önjelentésére
hagyatkoztam.

## Security review

Kockázatos kör (`risk = "high"` az `ai-router` blokkban) — a
`security-reviewer` agent független futása folyamatban/lezárva; eredménye
ennek a jelentésnek a frissítésekor kerül be, vagy a merge előtti külön
lépésben rögzítve.

## Merge-döntés

Az ADR 0052 szerint minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge.
**Jelenleg egy nyitott MAJOR (F1) van** → **merge tilos**, amíg nincs zárva.
Javító kör szükséges: **ugyanaz a motor (codex)**, a leletlistával (F1) a
promptban, a meglévő branchen.
